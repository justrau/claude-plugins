#!/usr/bin/env bash
# One read-only OpenCode review of a prepared brief, on one allowlisted model.
#
# Usage: opencode-review.sh <checkout> <run-dir> <model>
#   <checkout>  the repository under review; OpenCode runs from it
#   <run-dir>   a folder directly under ~/.local/state/opencode-review/ that holds brief.md
#   <model>     an allowlisted model id, optionally with #low, #high or #max
#
# Writes into <run-dir>, per model: events-<slug>.jsonl, stderr-<slug>.log, report-<slug>.md and
# metrics-<slug>.json (wall seconds, steps, tokens, cost). Exits with OpenCode's status, or 2 when
# it refuses to start.
set -euo pipefail

# Models allowed to read code: Zen models whose hosting is confirmed in the EU or the US.
# Source: https://opencode.ai/docs/zen/ section "Privacy": "All our models are hosted in the US
# and EU." (checked 2026-11-27). Add a model only with a source line like this one.
ALLOWED_MODELS=(
  "opencode/deepseek-v4.1-flash"
  "opencode/glm-5.3"
)
ALLOWED_VARIANTS=(low high max)
STATE_ROOT="$HOME/.local/state/opencode-review"
TIMEOUT_S=1800

die() { printf 'opencode-review: %s\n' "$*" >&2; exit 2; }

[ $# -eq 3 ] || die "usage: opencode-review.sh <checkout> <run-dir> <model>"
checkout=$1 run_dir=$2 model=$3

base=${model%%#*}
in_list() { local x=$1; shift; local y; for y in "$@"; do [ "$x" = "$y" ] && return 0; done; return 1; }
in_list "$base" "${ALLOWED_MODELS[@]}" ||
  die "model '$model' is not on the allowlist (${ALLOWED_MODELS[*]}; variants: ${ALLOWED_VARIANTS[*]})"
if [ "$model" != "$base" ]; then
  in_list "${model#*#}" "${ALLOWED_VARIANTS[@]}" ||
    die "variant in '$model' is not one of: ${ALLOWED_VARIANTS[*]}"
fi

[ -d "$checkout" ] || die "checkout '$checkout' is not a directory"
checkout_real=$(cd "$checkout" && pwd -P)
# Only a repository's top level, so $HOME or a parent folder cannot pass as a checkout.
top=$(git -C "$checkout_real" rev-parse --show-toplevel 2>/dev/null) ||
  die "checkout '$checkout' is not a git repository"
[ "$(cd "$top" && pwd -P)" = "$checkout_real" ] ||
  die "checkout '$checkout' is not the top level of its repository"
# OpenCode checks that a read stays in the project without resolving symlinks, so a change could
# add a link to a file outside (a key, a secret). Refuse a link that leaves the checkout or does
# not resolve.
while IFS= read -r -d '' link; do
  [ -e "$link" ] || die "symlink '$link' does not resolve"
  target=$(realpath "$link") || die "symlink '$link' does not resolve"
  case $target in
    "$checkout_real" | "$checkout_real"/*) ;;
    *) die "symlink '$link' points outside the checkout" ;;
  esac
done < <(find "$checkout_real" -path "$checkout_real/.git" -prune -o -type l -print0)
[ -d "$STATE_ROOT" ] || die "state folder $STATE_ROOT does not exist"
[ -d "$run_dir" ] || die "run dir '$run_dir' is not a directory"
root_real=$(cd "$STATE_ROOT" && pwd -P)
run_real=$(cd "$run_dir" && pwd -P)
[ "$(dirname "$run_real")" = "$root_real" ] || die "run dir must sit directly under $STATE_ROOT"
[ -f "$run_real/brief.md" ] || die "run dir has no brief.md"

# The checkout is untrusted: OpenCode loads a project's own config, plugins and agents from the
# folder it runs in, so a change under review could replace our agent or run code on load. Turn
# project config off, take config (and the agent) only from a folder this script writes in the run
# dir, and run standalone: the background service would ignore these variables.
# The plugin's agent file is a template: its one __RUN_DIR__ becomes this run dir, so the model
# can read this run's brief but not the briefs and reports of earlier runs.
template="$(cd "$(dirname "$0")/.." && pwd -P)/opencode/agents/second-look-reviewer.md"
[ -f "$template" ] || die "agent file $template is missing"
[ "$(grep -o '__RUN_DIR__' "$template" | wc -l | tr -d ' ')" = 1 ] ||
  die "agent file $template must hold __RUN_DIR__ exactly once"
case $run_real in *[\"\\]* | *$'\n'*) die "run dir path must not hold a quote, a backslash or a newline" ;; esac
chmod 700 "$run_real"
config_dir="$run_real/opencode"
mkdir -p "$config_dir/agents"
agent=$(<"$template")
printf '%s\n' "${agent//__RUN_DIR__/"$run_real"}" >"$config_dir/agents/second-look-reviewer.md"

# The caller's environment is untrusted too: OPENCODE_CONFIG, OPENCODE_CONFIG_CONTENT and others
# can add permissions, and OPENCODE_CONFIG_PROJECT_DISABLE overrides OPENCODE_DISABLE_PROJECT_CONFIG
# (even when it is 0). Unset every OPENCODE_* variable, then set only ours.
# OPENCODE_DISABLE_CLAUDE_CODE=1 stops OpenCode's Claude Code compatibility, which loads
# ~/.claude/CLAUDE.md as an instruction and so sends the owner's private rules to the model.
scrub=()
while IFS= read -r name; do
  case $name in OPENCODE_*) scrub+=(-u "$name") ;; esac
done < <(compgen -e)
our_env=(OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_CONFIG_PROJECT_DISABLE=1
  OPENCODE_DISABLE_CLAUDE_CODE=1 "OPENCODE_CONFIG_DIR=$config_dir")

slug=${model//\//-}
slug=${slug//#/-}
events="$run_real/events-$slug.jsonl"
report="$run_real/report-$slug.md"
run_id=$(basename "$run_real")
prompt="Read $run_real/brief.md and follow it. Your final message is the report."

start=$(date +%s)
status=0
(cd "$checkout_real" && exec env "${scrub[@]}" "${our_env[@]}" \
  timeout "$TIMEOUT_S" opencode2 run --standalone --agent second-look-reviewer -m "$model" \
  --title "review $run_id" --format json "$prompt") \
  >"$events" 2>"$run_real/stderr-$slug.log" </dev/null || status=$?
wall=$(( $(date +%s) - start ))

# The report is the text of the last assistant message that has text; text events are deltas.
jq -Rnr '[inputs | fromjson? | select(type == "object" and .type == "text")] as $t
  | ($t | last | .part.messageID) as $m
  | [$t[] | select(.part.messageID == $m) | .part.text] | join("")' "$events" >"$report"

jq -Rn --arg model "$model" --argjson status "$status" --argjson wall "$wall" \
  --argjson report_chars "$(wc -c <"$report" | tr -d ' ')" '
  [inputs | fromjson? | select(type == "object" and .type == "step_finish") | .part] as $s
  | def total(f): [$s[] | f // 0] | add // 0;
  { model: $model, exit_status: $status, wall_s: $wall, steps: ($s | length),
    tokens: { input: total(.tokens.input), output: total(.tokens.output),
              reasoning: total(.tokens.reasoning), cache_read: total(.tokens.cache.read),
              cache_write: total(.tokens.cache.write) },
    cost_usd: total(.cost), report_chars: $report_chars }' "$events" >"$run_real/metrics-$slug.json"

exit "$status"

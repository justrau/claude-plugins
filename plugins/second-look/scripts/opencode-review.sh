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
[ -d "$STATE_ROOT" ] || die "state folder $STATE_ROOT does not exist"
[ -d "$run_dir" ] || die "run dir '$run_dir' is not a directory"
root_real=$(cd "$STATE_ROOT" && pwd -P)
run_real=$(cd "$run_dir" && pwd -P)
[ "$(dirname "$run_real")" = "$root_real" ] || die "run dir must sit directly under $STATE_ROOT"
[ -f "$run_real/brief.md" ] || die "run dir has no brief.md"

slug=${model//\//-}
slug=${slug//#/-}
events="$run_real/events-$slug.jsonl"
report="$run_real/report-$slug.md"
run_id=$(basename "$run_real")
prompt="Read $run_real/brief.md and follow it. Your final message is the report."

start=$(date +%s)
status=0
(cd "$checkout" && exec timeout "$TIMEOUT_S" opencode2 run --agent second-look-reviewer -m "$model" \
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

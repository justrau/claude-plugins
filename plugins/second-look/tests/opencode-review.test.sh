#!/usr/bin/env bash
# Tests for scripts/opencode-review.sh and scripts/opencode-review-log.sh.
# Run: bash plugins/second-look/tests/opencode-review.test.sh
# A stand-in opencode2 (tests/fixtures/bin) replays a recorded event stream; no model is called.
# pass and fail always succeed, so `cond && pass || fail` is a safe if-then-else here.
# shellcheck disable=SC2015,SC2016,SC2181
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
review="$here/../scripts/opencode-review.sh"
log="$here/../scripts/opencode-review-log.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
export PATH="$here/fixtures/bin:$PATH"
export FAKE_EVENTS="$here/fixtures/events.jsonl"
export FAKE_ARGS_FILE="$tmp/args"
export FAKE_ENV_FILE="$tmp/env"
# Hostile values from the caller's environment: the script must drop them and set its own.
export OPENCODE_DISABLE_PROJECT_CONFIG=0
export OPENCODE_CONFIG_PROJECT_DISABLE=0
export OPENCODE_DISABLE_CLAUDE_CODE=0
export OPENCODE_CONFIG_DIR="$tmp/wrong-config"
export OPENCODE_CONFIG="$tmp/hostile.json"
export OPENCODE_CONFIG_CONTENT='{"permission":{"bash":"allow"}}'
export OPENCODE_PERMISSION='{"bash":"allow"}'
state="$HOME/.local/state/opencode-review"
checkout="$tmp/checkout"
mkdir -p "$state" "$checkout"
git init -q "$checkout"
checkout_real=$(cd "$checkout" && pwd -P)

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; fails=$((fails + 1)); }

new_run() { rm -f "$FAKE_ARGS_FILE"; local d="$state/$1"; mkdir -p "$d"; echo "brief" >"$d/brief.md"; echo "$d"; }

# Each case: the review must refuse with status 2 before opencode2 runs.
refuses() {
  local name=$1 run=$2 model=$3 from=${4:-$checkout} status
  rm -f "$FAKE_ARGS_FILE"
  "$review" "$from" "$run" "$model" 2>/dev/null; status=$?
  if [ "$status" -ne 2 ]; then fail "$name" "status $status, expected 2"
  elif [ -e "$FAKE_ARGS_FILE" ]; then fail "$name" "opencode2 ran"
  else pass "$name"; fi
}

run=$(new_run r1)
refuses "accepts any opencode-go id" "$run" "opencode-go/glm-5.3"
refuses "accepts a free variant id" "$run" "opencode/glm-5.3-free"
refuses "matches the allowlist as a glob" "$run" "opencode/glm-*"
refuses "matches the allowlist by prefix" "$run" "opencode/glm-5.3x"
refuses "matches a substring of the joined list" "$run" "opencode/glm-5.3 opencode/deepseek-v4.1-flash"
refuses "accepts an unknown variant" "$run" "opencode/glm-5.3#xhigh"
refuses "accepts an empty variant" "$run" "opencode/glm-5.3#"
refuses "accepts a second variant" "$run" "opencode/glm-5.3#high#max"
mkdir -p "$tmp/outside-run"; echo brief >"$tmp/outside-run/brief.md"
refuses "accepts a run dir outside the state folder" "$tmp/outside-run" "opencode/glm-5.3"
mkdir -p "$state/r1/nested"; echo brief >"$state/r1/nested/brief.md"
refuses "accepts a run dir nested deeper than one level" "$state/r1/nested" "opencode/glm-5.3"
ln -s "$tmp" "$state/link"; echo brief >"$tmp/brief.md"
refuses "trusts a symlinked run dir by its name" "$state/link" "opencode/glm-5.3"
refuses "writes a run dir path that breaks the agent's YAML" "$(new_run 'bad"quote')" "opencode/glm-5.3"
mkdir -p "$state/nobrief"
refuses "starts without a brief" "$state/nobrief" "opencode/glm-5.3"
rm -f "$FAKE_ARGS_FILE"
"$review" "$tmp/missing" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "runs from a missing checkout" || fail "runs from a missing checkout" "not refused"
rm -f "$FAKE_ARGS_FILE"
"$review" "$checkout" "$run" "opencode/glm-5.3" "extra" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "ignores an extra argument" || fail "ignores an extra argument" "not refused"
rm -f "$FAKE_ARGS_FILE"
"$review" "$checkout" "$run" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "runs without a model argument" || fail "runs without a model argument" "not refused"
# A copied script tree without the agent file, so the real file is never moved.
mkdir -p "$tmp/copy/opencode/agents"
cp -R "$here/../scripts" "$tmp/copy/"
rm -f "$FAKE_ARGS_FILE"
"$tmp/copy/scripts/opencode-review.sh" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "runs without its pinned agent file" || fail "runs without its pinned agent file" "not refused"
# The agent file is a template whose run dir placeholder must appear exactly once.
grep -v '__RUN_DIR__' "$here/../opencode/agents/second-look-reviewer.md" >"$tmp/copy/opencode/agents/second-look-reviewer.md"
rm -f "$FAKE_ARGS_FILE"
"$tmp/copy/scripts/opencode-review.sh" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "runs with a template that lacks the run dir placeholder" ||
  fail "runs with a template that lacks the run dir placeholder" "not refused"
{ cat "$here/../opencode/agents/second-look-reviewer.md"; echo "# __RUN_DIR__"; } >"$tmp/copy/opencode/agents/second-look-reviewer.md"
rm -f "$FAKE_ARGS_FILE"
"$tmp/copy/scripts/opencode-review.sh" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "runs with a template that has the placeholder twice" ||
  fail "runs with a template that has the placeholder twice" "not refused"

# The checkout is untrusted: OpenCode does not resolve symlinks when it checks that a read stays
# in the project, so a link to a file outside would leak it. Only the repository's top level runs.
echo secret >"$tmp/outside-secret"
mkdir -p "$checkout/docs"
ln -s "$tmp/outside-secret" "$checkout/docs/x"
refuses "follows a symlink out of the checkout" "$run" "opencode/glm-5.3"
rm "$checkout/docs/x"
ln -s "$tmp" "$checkout/docs/up"
refuses "follows a symlinked folder out of the checkout" "$run" "opencode/glm-5.3"
rm "$checkout/docs/up"
mkdir -p "$tmp/checkout-sibling"; echo secret >"$tmp/checkout-sibling/key"
ln -s "$tmp/checkout-sibling/key" "$checkout/docs/sib"
refuses "matches the checkout path by prefix" "$run" "opencode/glm-5.3"
rm "$checkout/docs/sib"
ln -s "$checkout/missing-target" "$checkout/docs/dangling"
refuses "trusts a dangling symlink" "$run" "opencode/glm-5.3"
rm "$checkout/docs/dangling"
refuses "runs from a folder below the top level" "$run" "opencode/glm-5.3" "$checkout/docs"
mkdir -p "$tmp/not-a-repo"
refuses "runs from a folder that is not a repository" "$run" "opencode/glm-5.3" "$tmp/not-a-repo"
echo inside >"$checkout/docs/real.md"
ln -s ../docs/real.md "$checkout/docs/inside"
rm -f "$FAKE_ARGS_FILE"
"$review" "$checkout" "$run" "opencode/glm-5.3" >/dev/null 2>&1
[ $? -eq 0 ] && [ -e "$FAKE_ARGS_FILE" ] && pass "refuses a symlink that stays inside the checkout" ||
  fail "refuses a symlink that stays inside the checkout" "did not run"

# An allowed model runs, from the checkout, with the pinned agent and model, and writes its files.
run=$(new_run r2)
"$review" "$checkout" "$run" "opencode/deepseek-v4.1-flash#high" 2>/dev/null
status=$?
slug="opencode-deepseek-v4.1-flash-high"
[ "$status" -eq 0 ] && pass "allowed model with a variant runs" || fail "allowed model with a variant runs" "status $status"
args=$(cat "$FAKE_ARGS_FILE" 2>/dev/null)
[ "$(sed -n 1p <<<"$args")" = "$checkout_real" ] && pass "runs from the checkout" || fail "runs from the checkout" "cwd $(sed -n 1p <<<"$args")"
after() { awk -v flag="$1" 'found { print; exit } $0 == flag { found = 1 }' <<<"$args"; }
[ "$(after --agent)" = "second-look-reviewer" ] && pass "drops the pinned agent" || fail "drops the pinned agent" "$args"
[ "$(after -m)" = "opencode/deepseek-v4.1-flash#high" ] && pass "drops the model" || fail "drops the model" "$args"
[ "$(after --format)" = "json" ] && pass "drops the json format" || fail "drops the json format" "$args"
[ "$(after --title)" = "review r2" ] && pass "drops the title, so OpenCode asks a small model for one" ||
  fail "drops the title, so OpenCode asks a small model for one" "$args"
config_dir="$(cd "$run" && pwd -P)/opencode"
env_seen=$(cat "$FAKE_ENV_FILE" 2>/dev/null)
[ "$env_seen" = "$(printf 'OPENCODE_CONFIG_DIR=%s\nOPENCODE_CONFIG_PROJECT_DISABLE=1\nOPENCODE_DISABLE_CLAUDE_CODE=1\nOPENCODE_DISABLE_PROJECT_CONFIG=1' "$config_dir")" ] &&
  [ "$(sed -n 2,3p <<<"$args")" = "$(printf 'run\n--standalone')" ] &&
  pass "loads the checkout's own OpenCode config or the caller's OPENCODE_* variables" ||
  fail "loads the checkout's own OpenCode config or the caller's OPENCODE_* variables" "$env_seen / $(sed -n 2,3p <<<"$args")"
# The generated agent may read only this run dir outside the checkout, not earlier runs.
gen="$config_dir/agents/second-look-reviewer.md"
ext=$(awk '/^ *- action: external_directory/ { x = 1; next } x && /resource:/ { r = $2 } x && /effect: allow/ { print r } /^ *- action:/ { x = 0 }' "$gen" 2>/dev/null | tr -d '"')
[ "$ext" = "$(cd "$run" && pwd -P)/*" ] && ! grep -q '__RUN_DIR__' "$gen" &&
  sed '/__RUN_DIR__/d' "$here/../opencode/agents/second-look-reviewer.md" | diff -q - <(grep -v -F "$(cd "$run" && pwd -P)/*" "$gen") >/dev/null &&
  pass "agent may read every earlier run" || fail "agent may read every earlier run" "allows: $ext"
[ "$(stat -f %Lp "$run" 2>/dev/null || stat -c %a "$run")" = 700 ] &&
  pass "leaves the run dir open to other users" || fail "leaves the run dir open to other users" "$(stat -f %Lp "$run")"
[ "$(cat "$run/report-$slug.md")" = "$(printf '## Findings\n1. An example finding.')" ] &&
  pass "report keeps only the last message's text" || fail "report keeps only the last message's text" "$(cat "$run/report-$slug.md")"
m="$run/metrics-$slug.json"
[ "$(jq -c '[.steps, .tokens.input, .tokens.output, .tokens.cache_read, .tokens.cache_write, .cost_usd, .exit_status]' "$m")" = "[2,4000,600,3300,100,0.02,0]" ] &&
  pass "metrics sum every step and skip non-json lines" || fail "metrics sum every step and skip non-json lines" "$(cat "$m")"

# OpenCode's own failure status comes back, and the metrics still record it.
run=$(new_run r3)
FAKE_STATUS=7 "$review" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
status=$?
[ "$status" -eq 7 ] && [ "$(jq .exit_status "$run/metrics-opencode-glm-5.3.json")" = 7 ] &&
  pass "returns and records OpenCode's failure status" || fail "returns and records OpenCode's failure status" "status $status"

# The agent allows only read, glob and its run dir. grep's permission resource is the pattern,
# not a file, so a grep allow would read .env lines past the read denies.
agent_src="$here/../opencode/agents/second-look-reviewer.md"
allowed=$(awk '/^ *- action:/ { a = $3 } /^ *effect: allow/ { print a }' "$agent_src" | tr -d '"' | sort -u | tr '\n' ' ')
[ "$allowed" = "external_directory glob read " ] &&
  pass "agent allows grep, which reads past the read denies" || fail "agent allows grep, which reads past the read denies" "$allowed"

# The log: one row per graded review, refused when grades and metrics disagree or the run repeats.
run="$state/r2"
printf '%s\n' '{"repo":"example","diff_lines":120,"other_reviewers":["claude"],"models":{"opencode/glm-5.3":{"confirmed":1,"false":0,"duplicate":0,"missed":0}}}' >"$run/grades.json"
"$log" append "$run" >/dev/null 2>&1
[ $? -eq 2 ] && [ ! -e "$state/log.jsonl" ] && pass "logs a review whose graded models differ from the measured ones" || fail "logs a review whose graded models differ from the measured ones" "not refused"
printf '%s\n' '{"repo":"example","diff_lines":120,"other_reviewers":["claude"],"models":{"opencode/deepseek-v4.1-flash#high":{"confirmed":2,"false":1.5,"duplicate":0,"missed":1}}}' >"$run/grades.json"
"$log" append "$run" >/dev/null 2>&1
[ $? -eq 2 ] && [ ! -e "$state/log.jsonl" ] && pass "logs fractional counts" || fail "logs fractional counts" "not refused"
printf '%s\n' '{"repo":"example","diff_lines":120,"other_reviewers":["claude"],"models":{"opencode/deepseek-v4.1-flash#high":{"confirmed":2,"false":-1,"duplicate":0,"missed":1}}}' >"$run/grades.json"
"$log" append "$run" >/dev/null 2>&1
[ $? -eq 2 ] && [ ! -e "$state/log.jsonl" ] && pass "logs negative counts" || fail "logs negative counts" "not refused"
printf '%s\n' '{"repo":"example","diff_lines":120,"other_reviewers":["claude"],"models":{"opencode/deepseek-v4.1-flash#high":{"confirmed":2,"false":1,"duplicate":0}}}' >"$run/grades.json"
"$log" append "$run" >/dev/null 2>&1
[ $? -eq 2 ] && [ ! -e "$state/log.jsonl" ] && pass "logs grades without a missed count" || fail "logs grades without a missed count" "not refused"
printf '%s\n' '{"repo":"example","diff_lines":120,"other_reviewers":["claude"],"models":{"opencode/deepseek-v4.1-flash#high":{"confirmed":2,"false":1,"duplicate":0,"missed":1}}}' >"$run/grades.json"
"$log" append "$run" >/dev/null 2>&1
[ $? -eq 0 ] && [ "$(jq -c '[.run_id, .models[0].model, .models[0].confirmed, .models[0].cost_usd]' "$state/log.jsonl")" = '["r2","opencode/deepseek-v4.1-flash#high",2,0.02]' ] &&
  pass "appends one row with metrics and grades" || fail "appends one row with metrics and grades" "$(cat "$state/log.jsonl" 2>/dev/null)"
"$log" append "$run" >/dev/null 2>&1
[ $? -eq 2 ] && [ "$(wc -l <"$state/log.jsonl" | tr -d ' ')" = 1 ] && pass "appends the same run twice" || fail "appends the same run twice" "not refused"
# A second review of the same model with another variant, and counts where precision (6/7) and
# recall (6/10) differ.
run4=$(new_run r4)
"$review" "$checkout" "$run4" "opencode/deepseek-v4.1-flash#max" >/dev/null 2>&1
printf '%s\n' '{"repo":"example","diff_lines":80,"other_reviewers":["claude","codex"],"models":{"opencode/deepseek-v4.1-flash#max":{"confirmed":4,"false":0,"duplicate":1,"missed":3}}}' >"$run4/grades.json"
"$log" append "$run4" >/dev/null 2>&1
wall=$(jq -s 'map(.wall_s) | min' "$run/metrics-$slug.json" "$run4/metrics-opencode-deepseek-v4.1-flash-max.json")
summary=$("$log" summary)
[ "$(wc -l <<<"$summary" | tr -d ' ')" = 3 ] && [ "$(sed -n 3p <<<"$summary")" = '| `opencode/deepseek-v4.1-flash` | 2 | 6 | 1 | 1 | 4 | 86% | 60% | $0.02 | '"$wall"' s | 2 |' ] &&
  pass "summary lists each variant as its own model, or swaps precision and recall" ||
  fail "summary lists each variant as its own model, or swaps precision and recall" "$summary"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }

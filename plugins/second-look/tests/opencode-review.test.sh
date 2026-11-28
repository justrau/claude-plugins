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
# Wrong values from the caller's environment: the script must set its own.
export OPENCODE_DISABLE_PROJECT_CONFIG=0
export OPENCODE_CONFIG_DIR="$tmp/wrong-config"
state="$HOME/.local/state/opencode-review"
checkout="$tmp/checkout"
mkdir -p "$state" "$checkout"

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; fails=$((fails + 1)); }

new_run() { rm -f "$FAKE_ARGS_FILE"; local d="$state/$1"; mkdir -p "$d"; echo "brief" >"$d/brief.md"; echo "$d"; }

# Each case: the review must refuse with status 2 before opencode2 runs.
refuses() {
  local name=$1 run=$2 model=$3 status
  rm -f "$tmp/args"
  "$review" "$checkout" "$run" "$model" 2>/dev/null; status=$?
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
refuses "accepts a run dir outside the state folder" "$tmp" "opencode/glm-5.3"
mkdir -p "$state/r1/nested"; echo brief >"$state/r1/nested/brief.md"
refuses "accepts a run dir nested deeper than one level" "$state/r1/nested" "opencode/glm-5.3"
ln -s "$tmp" "$state/link"; echo brief >"$tmp/brief.md"
refuses "trusts a symlinked run dir by its name" "$state/link" "opencode/glm-5.3"
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

# An allowed model runs, from the checkout, with the pinned agent and model, and writes its files.
run=$(new_run r2)
"$review" "$checkout" "$run" "opencode/deepseek-v4.1-flash#high" 2>/dev/null
status=$?
slug="opencode-deepseek-v4.1-flash-high"
[ "$status" -eq 0 ] && pass "allowed model with a variant runs" || fail "allowed model with a variant runs" "status $status"
args=$(cat "$FAKE_ARGS_FILE" 2>/dev/null)
[ "$(sed -n 1p <<<"$args")" = "$checkout" ] && pass "runs from the checkout" || fail "runs from the checkout" "cwd $(sed -n 1p <<<"$args")"
grep -qx -- "--agent" <<<"$args" && grep -qx "second-look-reviewer" <<<"$args" && grep -qx -- "opencode/deepseek-v4.1-flash#high" <<<"$args" &&
  grep -qx -- "--format" <<<"$args" && pass "passes the pinned agent, model and json format" || fail "passes the pinned agent, model and json format" "$args"
config_dir=$(cd "$here/../opencode" && pwd -P)
env_seen=$(cat "$FAKE_ENV_FILE" 2>/dev/null)
[ "$env_seen" = "$(printf 'OPENCODE_DISABLE_PROJECT_CONFIG=1\nOPENCODE_CONFIG_DIR=%s' "$config_dir")" ] &&
  [ "$(sed -n 2,3p <<<"$args")" = "$(printf 'run\n--standalone')" ] &&
  pass "loads the checkout's own OpenCode config" || fail "loads the checkout's own OpenCode config" "$env_seen / $(sed -n 2,3p <<<"$args")"
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
row=$("$log" summary | sed -n 3p)
[ "$row" = '| `opencode/deepseek-v4.1-flash` | 1 | 2 | 1 | 0 | 1 | 67% | 67% | $0.02 | '"$(jq .wall_s "$run/metrics-$slug.json")"' s | 2 |' ] &&
  pass "summary groups variants under the model" || fail "summary groups variants under the model" "$row"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }

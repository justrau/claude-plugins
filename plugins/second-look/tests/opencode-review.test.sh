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
# The run dir path becomes a permission pattern, where * and ? are wildcards.
refuses "accepts a star in the run dir name" "$(new_run 'all*runs')" "opencode/glm-5.3"
refuses "accepts a question mark in the run dir name" "$(new_run 'run?')" "opencode/glm-5.3"
refuses "accepts a quote in the run dir name" "$(new_run 'bad"quote')" "opencode/glm-5.3"
refuses "accepts a space in the run dir name" "$(new_run 'a run')" "opencode/glm-5.3"
refuses "leaves a placeholder that the run dir name brought in" "$(new_run 'x__BRIEF_DIR__y')" "opencode/glm-5.3"
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
grep -v '__BRIEF_DIR__' "$here/../opencode/agents/second-look-reviewer.md" >"$tmp/copy/opencode/agents/second-look-reviewer.md"
rm -f "$FAKE_ARGS_FILE"
"$tmp/copy/scripts/opencode-review.sh" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "runs with a template that lacks the run dir placeholder" ||
  fail "runs with a template that lacks the run dir placeholder" "not refused"
{ cat "$here/../opencode/agents/second-look-reviewer.md"; echo "# __BRIEF_DIR__"; } >"$tmp/copy/opencode/agents/second-look-reviewer.md"
rm -f "$FAKE_ARGS_FILE"
"$tmp/copy/scripts/opencode-review.sh" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "runs with a template that has the placeholder twice" ||
  fail "runs with a template that has the placeholder twice" "not refused"
{ sed 's|"__BRIEF_DIR__/\*"|"*"|' "$here/../opencode/agents/second-look-reviewer.md"; echo "# __BRIEF_DIR__"; } >"$tmp/copy/opencode/agents/second-look-reviewer.md"
rm -f "$FAKE_ARGS_FILE"
"$tmp/copy/scripts/opencode-review.sh" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "runs with an agent that does not allow its run dir" ||
  fail "runs with an agent that does not allow its run dir" "not refused"
# OpenCode asks external_directory per folder, so a rule that names a file never matches.
sed 's|"__BRIEF_DIR__/\*"|"__BRIEF_DIR__/brief.md"|' "$here/../opencode/agents/second-look-reviewer.md" >"$tmp/copy/opencode/agents/second-look-reviewer.md"
rm -f "$FAKE_ARGS_FILE"
"$tmp/copy/scripts/opencode-review.sh" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "runs with an allow that names the brief file, which never matches" ||
  fail "runs with an allow that names the brief file, which never matches" "not refused"
sed 's|"__BRIEF_DIR__/\*"|"__BRIEF_DIR__/../*"|' "$here/../opencode/agents/second-look-reviewer.md" >"$tmp/copy/opencode/agents/second-look-reviewer.md"
rm -f "$FAKE_ARGS_FILE"
"$tmp/copy/scripts/opencode-review.sh" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "runs with an agent that may read the whole run dir" ||
  fail "runs with an agent that may read the whole run dir" "not refused"
# Only read, glob and external_directory may be allowed in the file OpenCode gets.
awk 'n == 1 && /^---$/ { print "  - action: bash"; print "    resource: \"*\""; print "    effect: allow" } /^---$/ { n++ } 1' \
  "$here/../opencode/agents/second-look-reviewer.md" >"$tmp/copy/opencode/agents/second-look-reviewer.md"
rm -f "$FAKE_ARGS_FILE"
"$tmp/copy/scripts/opencode-review.sh" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "runs with an agent that gains a shell allow" ||
  fail "runs with an agent that gains a shell allow" "not refused"
awk 'n == 1 && /^---$/ { print "  - effect: allow"; print "    resource: \"*\""; print "    action: edit" } /^---$/ { n++ } 1' \
  "$here/../opencode/agents/second-look-reviewer.md" >"$tmp/copy/opencode/agents/second-look-reviewer.md"
rm -f "$FAKE_ARGS_FILE"
"$tmp/copy/scripts/opencode-review.sh" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "misses an edit allow written with its keys reordered" ||
  fail "misses an edit allow written with its keys reordered" "not refused"
awk 'n == 1 && /^---$/ { print "  - effect: allow"; print "    resource: \"/*\""; print "    action: external_directory" } /^---$/ { n++ } 1' \
  "$here/../opencode/agents/second-look-reviewer.md" >"$tmp/copy/opencode/agents/second-look-reviewer.md"
rm -f "$FAKE_ARGS_FILE"
"$tmp/copy/scripts/opencode-review.sh" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "misses a second outside folder allow written with its keys reordered" ||
  fail "misses a second outside folder allow written with its keys reordered" "not refused"
awk '!d && /effect: deny/ { sub(/deny/, "allow"); d = 1 } 1' "$here/../opencode/agents/second-look-reviewer.md" >"$tmp/copy/opencode/agents/second-look-reviewer.md"
rm -f "$FAKE_ARGS_FILE"
"$tmp/copy/scripts/opencode-review.sh" "$checkout" "$run" "opencode/glm-5.3" 2>/dev/null
[ $? -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && pass "runs with an agent whose first rule is not deny-all" ||
  fail "runs with an agent whose first rule is not deny-all" "not refused"

# Preflight: a missing tool stops the review before the paid run, not halfway through it.
bin_without() {
  local d="$tmp/bin-without-$1" t p
  mkdir -p "$d"
  for t in bash env git find realpath grep wc tr date dirname basename chmod mkdir mktemp cp mv cat sort sed head tail awk rm stat ls jq timeout; do
    [ "$t" = "$1" ] && continue
    p=$(command -v "$t") && ln -sf "$p" "$d/$t"
  done
  [ "$1" = opencode2 ] || ln -sf "$here/fixtures/bin/opencode2" "$d/opencode2"
  echo "$d"
}
for tool in opencode2 timeout jq git realpath; do
  rm -f "$FAKE_ARGS_FILE"
  err=$(PATH=$(bin_without "$tool") "$review" "$checkout" "$run" "opencode/glm-5.3" 2>&1 >/dev/null); status=$?
  [ "$status" -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && grep -q "$tool is not on PATH" <<<"$err" &&
    pass "starts the run without $tool" || fail "starts the run without $tool" "status $status: $err"
done

# An old bash (macOS ships 3.2) writes stray quotes in the agent file and fails on empty arrays.
old_bash=/bin/bash
if [ -x "$old_bash" ] && [ "$("$old_bash" -c 'echo $(( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] ))')" -lt 404 ]; then
  rm -f "$FAKE_ARGS_FILE"
  err=$("$old_bash" "$review" "$checkout" "$run" "opencode/glm-5.3" 2>&1 >/dev/null); status=$?
  [ "$status" -eq 2 ] && [ ! -e "$FAKE_ARGS_FILE" ] && grep -q "bash 4.4" <<<"$err" &&
    pass "runs on a bash older than 4.4" || fail "runs on a bash older than 4.4" "status $status: $err"
else
  echo "skip runs on a bash older than 4.4 (no old bash at $old_bash)"
fi

# The checkout is untrusted: OpenCode does not resolve symlinks when it checks that a read stays
# in the project, so a tracked link to a file outside would leak it. Only tracked links count:
# untracked ones (node_modules, .venv) come from local tools, not from the change.
track_link() { ln -s "$1" "$checkout/$2" && git -C "$checkout" add -- "$2"; }
untrack_link() { git -C "$checkout" rm -q --cached -- "$1"; rm "$checkout/$1"; }
echo secret >"$tmp/outside-secret"
mkdir -p "$checkout/docs" "$checkout/config"
track_link "$tmp/outside-secret" docs/x
refuses "follows a tracked symlink out of the checkout" "$run" "opencode/glm-5.3"
untrack_link docs/x
track_link "$tmp" docs/up
refuses "follows a tracked symlinked folder out of the checkout" "$run" "opencode/glm-5.3"
untrack_link docs/up
mkdir -p "$tmp/checkout-sibling"; echo secret >"$tmp/checkout-sibling/key"
track_link "$tmp/checkout-sibling/key" docs/sib
refuses "matches the checkout path by prefix" "$run" "opencode/glm-5.3"
untrack_link docs/sib
track_link "$checkout/missing-target" docs/dangling
refuses "trusts a dangling tracked symlink" "$run" "opencode/glm-5.3"
untrack_link docs/dangling
# A link inside the checkout to a file the read rules deny gets past them under another name.
echo SECRET=1 >"$checkout/.env"; echo SECRET=1 >"$checkout/config/.ENV.Production"; echo k=1 >"$checkout/config/app.secrets.env"
track_link ../.env docs/notes.txt
refuses "lets a tracked link reach .env under another name" "$run" "opencode/glm-5.3"
untrack_link docs/notes.txt
track_link ../config/.ENV.Production docs/prod.txt
refuses "matches the denied names case-sensitively" "$run" "opencode/glm-5.3"
untrack_link docs/prod.txt
track_link ../config/app.secrets.env docs/app.txt
refuses "lets a tracked link reach a .secrets.env file" "$run" "opencode/glm-5.3"
untrack_link docs/app.txt
# A tracked outside link inside a submodule.
sub_src="$tmp/sub-src"
git init -q "$sub_src"
ln -s "$tmp/outside-secret" "$sub_src/leak"
git -C "$sub_src" add leak
git -C "$sub_src" -c user.name=test -c user.email=test@example.invalid commit -q -m "add a link"
git -C "$checkout" -c protocol.file.allow=always submodule --quiet add "$sub_src" sub 2>/dev/null
refuses "skips the links of submodules" "$run" "opencode/glm-5.3"
git -C "$checkout" rm -q -r --cached sub .gitmodules
rm -rf "$checkout/sub" "$checkout/.gitmodules" "$checkout/.git/modules"
git init -q "$tmp/bad-index"; echo "not an index" >"$tmp/bad-index/.git/index"
refuses "trusts the link list when git ls-files fails" "$run" "opencode/glm-5.3" "$tmp/bad-index"
refuses "runs from a folder below the top level" "$run" "opencode/glm-5.3" "$checkout/docs"
mkdir -p "$tmp/not-a-repo"
refuses "runs from a folder that is not a repository" "$run" "opencode/glm-5.3" "$tmp/not-a-repo"
echo inside >"$checkout/docs/real.md"
track_link ../docs/real.md docs/inside
ln -s "$tmp/outside-secret" "$checkout/docs/untracked-out"
git -C "$checkout" add .env
rm -f "$FAKE_ARGS_FILE"
"$review" "$checkout" "$run" "opencode/glm-5.3" >/dev/null 2>&1
[ $? -eq 0 ] && [ -e "$FAKE_ARGS_FILE" ] &&
  pass "refuses a tracked symlink inside the checkout, an untracked one, or a tracked .env that is no link" ||
  fail "refuses a tracked symlink inside the checkout, an untracked one, or a tracked .env that is no link" "did not run"
rm "$checkout/docs/untracked-out"

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
env_seen=$(cat "$FAKE_ENV_FILE" 2>/dev/null)
config_dir=$(sed -n 's/^OPENCODE_CONFIG_DIR=//p' <<<"$env_seen")
case $config_dir in "$(cd "$run" && pwd -P)"/opencode.??????) ;; *) config_dir="<not in the run dir: $config_dir>" ;; esac
[ "$env_seen" = "$(printf 'OPENCODE_CONFIG_DIR=%s\nOPENCODE_CONFIG_PROJECT_DISABLE=1\nOPENCODE_DISABLE_CLAUDE_CODE=1\nOPENCODE_DISABLE_PROJECT_CONFIG=1' "$config_dir")" ] &&
  [ "$(sed -n 2,3p <<<"$args")" = "$(printf 'run\n--standalone')" ] &&
  pass "loads the checkout's own OpenCode config or the caller's OPENCODE_* variables" ||
  fail "loads the checkout's own OpenCode config or the caller's OPENCODE_* variables" "$env_seen / $(sed -n 2,3p <<<"$args")"
# Outside the checkout, the generated agent may read only this invocation's brief folder: not
# earlier runs, nor the other model's report and events, nor its own config dir.
gen="$config_dir/agents/second-look-reviewer.md"
ext=$(awk '/^ *- action: external_directory/ { x = 1; next } x && /resource:/ { r = $0; sub(/^ *resource: */, "", r) } x && /effect: allow/ { print r } /^ *- action:/ { x = 0 }' "$gen" 2>/dev/null | tr -d '"')
brief_dir=${ext%/\*}
prompt_seen=$(tail -n 1 <<<"$args")
case $brief_dir in "$(cd "$run" && pwd -P)"/brief.??????) ;; *) brief_dir="<not a brief folder: $ext>" ;; esac
[ "$ext" = "$brief_dir/*" ] && cmp -s "$brief_dir/brief.md" "$run/brief.md" && [ "$(ls -A "$brief_dir")" = "brief.md" ] &&
  [ "$prompt_seen" = "Read $brief_dir/brief.md and follow it. Your final message is the report." ] &&
  ! grep -q '__BRIEF_DIR__' "$gen" &&
  sed '/__BRIEF_DIR__/d' "$here/../opencode/agents/second-look-reviewer.md" | diff -q - <(grep -v -F "$brief_dir/*" "$gen") >/dev/null &&
  pass "agent may read more than this invocation's brief folder" ||
  fail "agent may read more than this invocation's brief folder" "allows: $ext; prompt: $prompt_seen"
[ "$(stat -f %Lp "$run" 2>/dev/null || stat -c %a "$run")" = 700 ] &&
  pass "leaves the run dir open to other users" || fail "leaves the run dir open to other users" "$(stat -f %Lp "$run")"
[ "$(cat "$run/report-$slug.md")" = "$(printf '## Findings\n1. An example finding.')" ] &&
  pass "report keeps only the last message's text" || fail "report keeps only the last message's text" "$(cat "$run/report-$slug.md")"
m="$run/metrics-$slug.json"
[ "$(jq -r .opencode_version "$m")" = "2.4.2-stand-in" ] && pass "metrics omit the OpenCode version" || fail "metrics omit the OpenCode version" "$(cat "$m")"
[ "$(jq -c '[.steps, .tokens.input, .tokens.output, .tokens.cache_read, .tokens.cache_write, .cost_usd, .exit_status]' "$m")" = "[2,4000,600,3300,100,0.02,0]" ] &&
  pass "metrics sum every step and skip non-json lines" || fail "metrics sum every step and skip non-json lines" "$(cat "$m")"

# Two models start at once on one run dir: each gets its own config dir, and each OpenCode sees a
# complete agent file in it.
runp=$(new_run rp)
runp_real=$(cd "$runp" && pwd -P)
FAKE_ARGS_FILE="$tmp/args-a" FAKE_ENV_FILE="$tmp/env-a" "$review" "$checkout" "$runp" "opencode/glm-5.3#high" >/dev/null 2>&1 &
pid_a=$!
FAKE_ARGS_FILE="$tmp/args-b" FAKE_ENV_FILE="$tmp/env-b" "$review" "$checkout" "$runp" "opencode/deepseek-v4.1-flash#high" >/dev/null 2>&1 &
pid_b=$!
wait "$pid_a"; st_a=$?
wait "$pid_b"; st_b=$?
dir_a=$(sed -n 's/^OPENCODE_CONFIG_DIR=//p' "$tmp/env-a" 2>/dev/null)
dir_b=$(sed -n 's/^OPENCODE_CONFIG_DIR=//p' "$tmp/env-b" 2>/dev/null)
[ "$st_a" -eq 0 ] && [ "$st_b" -eq 0 ] && [ -n "$dir_a" ] && [ "$dir_a" != "$dir_b" ] &&
  [ "$(dirname "$dir_a")" = "$runp_real" ] && [ "$(dirname "$dir_b")" = "$runp_real" ] &&
  [ "$(ls "$dir_a/agents")" = "second-look-reviewer.md" ] && [ "$(ls "$dir_b/agents")" = "second-look-reviewer.md" ] &&
  [ "$(ls -A "$dir_a")" = "agents" ] &&
  sed -n 6,8p "$tmp/env-a.agent" | tr -d ' ' | paste -sd' ' - | grep -qx -- '-action:"\*" resource:"\*" effect:deny' &&
  sed -n 6,8p "$tmp/env-b.agent" | tr -d ' ' | paste -sd' ' - | grep -qx -- '-action:"\*" resource:"\*" effect:deny' &&
  pass "parallel runs share one agent file" || fail "parallel runs share one agent file" "$st_a $st_b: $dir_a / $dir_b"
prompt_a=$(tail -n 1 "$tmp/args-a" 2>/dev/null)
prompt_b=$(tail -n 1 "$tmp/args-b" 2>/dev/null)
[ -n "$prompt_a" ] && [ "$prompt_a" != "$prompt_b" ] && [ "$(find "$runp_real" -maxdepth 1 -type d -name 'brief.*' | wc -l | tr -d ' ')" = 2 ] &&
  pass "parallel runs share one brief folder" || fail "parallel runs share one brief folder" "$prompt_a / $prompt_b"

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
printf '%s\n' '{"repo":"example","diff_lines":120,"other_reviewers":["claude",{"text":"a finding"}],"models":{"opencode/deepseek-v4.1-flash#high":{"confirmed":2,"false":1,"duplicate":0,"missed":1}}}' >"$run/grades.json"
"$log" append "$run" >/dev/null 2>&1
[ $? -eq 2 ] && [ ! -e "$state/log.jsonl" ] && pass "logs other reviewers that are not names" || fail "logs other reviewers that are not names" "not refused"
# A field the metrics file should not hold (here, report text) stays out of the row.
jq '. + {report_text: "a finding"}' "$run/metrics-$slug.json" >"$tmp/metrics.json" && mv "$tmp/metrics.json" "$run/metrics-$slug.json"
printf '%s\n' '{"repo":"example","diff_lines":120,"other_reviewers":["claude"],"models":{"opencode/deepseek-v4.1-flash#high":{"confirmed":2,"false":1,"duplicate":0,"missed":1}}}' >"$run/grades.json"
"$log" append "$run" >/dev/null 2>&1
[ $? -eq 0 ] && [ "$(jq -c '.models[0] | keys' "$state/log.jsonl")" = '["confirmed","cost_usd","duplicate","exit_status","false","missed","model","opencode_version","report_chars","steps","tokens","wall_s"]' ] &&
  pass "copies every metrics field into the row" || fail "copies every metrics field into the row" "$(cat "$state/log.jsonl" 2>/dev/null)"
[ "$(jq -c '[.run_id, .models[0].model, .models[0].confirmed, .models[0].cost_usd]' "$state/log.jsonl")" = '["r2","opencode/deepseek-v4.1-flash#high",2,0.02]' ] &&
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

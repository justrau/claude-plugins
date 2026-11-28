#!/usr/bin/env bash
# The evaluation log of OpenCode reviews: one row per review, counts and measurements only.
#
# Usage:
#   opencode-review-log.sh append <run-dir>   add the row for one graded review
#   opencode-review-log.sh summary            print the summary table per model (Markdown)
#
# append reads <run-dir>/grades.json, written by the lead after verifying the findings:
#   { "repo": "<folder name>", "diff_lines": 420, "other_reviewers": ["claude", "codex"],
#     "models": { "<model id as run>": { "confirmed": 3, "false": 1, "duplicate": 0, "missed": 2 } } }
# The counts per model:
#   confirmed  findings of this model that the lead confirmed
#   false      findings of this model that are wrong
#   duplicate  repeats of a finding inside this model's own report
#   missed     real findings from the other reviewers, or from the other OpenCode model, that this
#              model did not report. Nits do not count, and neither do findings that need a sibling
#              repository or a dependency source: this reviewer cannot read outside the checkout and
#              its run dir.
# and metrics-<slug>.json of each model, written by opencode-review.sh. The row holds no finding
# text, no code and no paths inside the repository.
set -euo pipefail

STATE_ROOT="$HOME/.local/state/opencode-review"
LOG="$STATE_ROOT/log.jsonl"

die() { printf 'opencode-review-log: %s\n' "$*" >&2; exit 2; }

append() {
  local run_dir=$1
  [ -f "$run_dir/grades.json" ] || die "no grades.json in $run_dir"
  local run_id; run_id=$(basename "$(cd "$run_dir" && pwd -P)")
  if [ -f "$LOG" ] && jq -e --arg id "$run_id" 'select(.run_id == $id)' "$LOG" >/dev/null; then
    die "run $run_id is already in $LOG"
  fi
  jq -e '(.repo | type == "string") and (.diff_lines | type == "number")
    and (.other_reviewers | type == "array" and all(type == "string")) and (.models | type == "object" and length > 0)
    and ([.models[] | (.confirmed, .false, .duplicate, .missed)
          | type == "number" and . >= 0 and . == floor] | all)' "$run_dir/grades.json" >/dev/null ||
    die "grades.json lacks repo, diff_lines, other_reviewers (names only), or whole counts per model"

  local graded measured
  graded=$(jq -r '.models | keys[] | gsub("[/#]"; "-")' "$run_dir/grades.json" | sort)
  measured=$(find "$run_dir" -maxdepth 1 -name 'metrics-*.json' -exec basename {} .json \; | sed 's/^metrics-//' | sort)
  [ "$graded" = "$measured" ] ||
    die "graded models (${graded//$'\n'/ }) differ from measured models (${measured//$'\n'/ })"

  local metrics; metrics=$(jq -s '.' "$run_dir"/metrics-*.json)
  mkdir -p "$STATE_ROOT"
  jq -c --arg id "$run_id" --arg date "$(date +%F)" --argjson metrics "$metrics" '
    { date: $date, run_id: $id, repo, diff_lines, other_reviewers,
      models: [ $metrics[] as $m
        | ($m | { model, opencode_version, exit_status, wall_s, steps,
                  tokens: (.tokens | {input, output, reasoning, cache_read, cache_write}),
                  cost_usd, report_chars })
          + (.models[$m.model] | {confirmed, false, duplicate, missed}) ] }' \
    "$run_dir/grades.json" >>"$LOG"
  echo "added $run_id to $LOG"
}

summary() {
  [ -f "$LOG" ] || die "no log at $LOG"
  jq -rs '
    def median: sort | if length == 0 then null else .[(length - 1) / 2 | floor] end;
    def pct(a; b): if b == 0 then "–" else "\(a * 100 / b | round)%" end;
    [.[] | .models[] | .base = (.model | split("#")[0])] | group_by(.base)[]
    | { m: .[0].base, n: length, c: (map(.confirmed) | add), f: (map(.false) | add),
        d: (map(.duplicate) | add), x: (map(.missed) | add),
        cost: (map(.cost_usd) | median), wall: (map(.wall_s) | median), steps: (map(.steps) | median) }
    | "| `\(.m)` | \(.n) | \(.c) | \(.f) | \(.d) | \(.x) | \(pct(.c; .c + .f)) | \(pct(.c; .c + .x)) | $\(.cost * 1000 | round / 1000) | \(.wall) s | \(.steps) |"' "$LOG" |
    { echo "| Model | Reviews | Confirmed | False | Dup | Missed | Precision | Recall | Median cost | Median wall | Median steps |"
      echo "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
      cat; }
}

case "${1:-}" in
  append) [ $# -eq 2 ] || die "usage: opencode-review-log.sh append <run-dir>"; append "$2" ;;
  summary) [ $# -eq 1 ] || die "usage: opencode-review-log.sh summary"; summary ;;
  *) die "usage: opencode-review-log.sh append <run-dir> | summary" ;;
esac

#!/usr/bin/env bash
#
# report.sh — render results/history.jsonl as a markdown trend table.
#
# Usage: report.sh   (rows = runs, oldest first; ▲/▼ vs the previous row)

set -euo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTORY="$EVALS_DIR/results/history.jsonl"
[ -s "$HISTORY" ] || { echo "no runs recorded yet (results/history.jsonl is empty)"; exit 0; }

echo "| run | model | gates | shots | runs | \$/run | cost |"
echo "|---|---|---|---|---|---|---|"

PREV_GATES=""
while IFS= read -r line; do
  run=$(jq -r '.label // .run_id' <<<"$line")
  model=$(jq -r '.model // "?"' <<<"$line" | sed 's/^claude-//')
  reps=$(jq -r '.reps // "?"' <<<"$line")
  gates=$(jq -r '.gate_pass_rate' <<<"$line")
  shots=$(jq -r 'if .shot_accuracy == null then "-" else (.shot_accuracy * 100 | round | tostring) + "%" end' <<<"$line")
  cost=$(jq -r '.cost_usd // 0' <<<"$line")

  trend=""
  if [ -n "$PREV_GATES" ]; then
    trend=$(awk -v a="$PREV_GATES" -v b="$gates" 'BEGIN {
      if (b > a + 0.0001) print " ▲"; else if (b < a - 0.0001) print " ▼"; else print " ="
    }')
  fi
  PREV_GATES="$gates"

  per_run="?"
  [ "$reps" != "?" ] && [ "$reps" -gt 0 ] && per_run=$(awk -v c="$cost" -v r="$reps" 'BEGIN {printf "$%.2f", c/r}')
  printf '| %s | %s | %.2f%s | %s | %s | %s | $%.2f |\n' \
    "$run" "$model" "$gates" "$trend" "$shots" "$reps" "$per_run" "$cost"
done < "$HISTORY"

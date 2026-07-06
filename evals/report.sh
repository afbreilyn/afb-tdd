#!/usr/bin/env bash
#
# report.sh — render results/history.jsonl as a markdown trend table.
#
# Usage: report.sh   (rows = runs, oldest first; ▲/▼ vs the previous row)

set -euo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTORY="$EVALS_DIR/results/history.jsonl"
[ -s "$HISTORY" ] || { echo "no runs recorded yet (results/history.jsonl is empty)"; exit 0; }

echo "| run | date | skill | model | gates | judge | mutation | cost |"
echo "|---|---|---|---|---|---|---|---|"

PREV_GATES=""
while IFS= read -r line; do
  run=$(jq -r '.label // .run_id' <<<"$line")
  date=$(jq -r .date <<<"$line")
  sha=$(jq -r .skill_sha <<<"$line")
  model=$(jq -r '.model // "?"' <<<"$line" | sed 's/^claude-//')
  gates=$(jq -r '.gate_pass_rate' <<<"$line")
  judge=$(jq -r '.judge_mean // "-"' <<<"$line")
  mutation=$(jq -r '.mutation_mean // "-"' <<<"$line")
  cost=$(jq -r '.cost_usd // 0' <<<"$line")

  trend=""
  if [ -n "$PREV_GATES" ]; then
    trend=$(awk -v a="$PREV_GATES" -v b="$gates" 'BEGIN {
      if (b > a + 0.0001) print " ▲"; else if (b < a - 0.0001) print " ▼"; else print " ="
    }')
  fi
  PREV_GATES="$gates"

  printf '| %s | %s | %s | %s | %.2f%s | %s | %s | $%.2f |\n' \
    "$run" "$date" "$sha" "$model" "$gates" "$trend" "$judge" "$mutation" "$cost"
done < "$HISTORY"

#!/usr/bin/env bash
#
# compare.sh — per-metric delta between two eval runs.
#
# Usage: compare.sh <candidate-summary.json> [<reference-summary.json>]
#   reference defaults to results/baseline.json

set -euo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAND="${1:?usage: compare.sh <candidate-summary.json> [<reference-summary.json>]}"
REF="${2:-$EVALS_DIR/results/baseline.json}"
[ -f "$REF" ] || { echo "no reference summary at $REF" >&2; exit 1; }

arrow() { # arrow <ref> <cand>
  awk -v a="$1" -v b="$2" 'BEGIN {
    if (a == "null" || b == "null") { print " "; exit }
    if (b > a + 0.0001) print "▲"; else if (b < a - 0.0001) print "▼"; else print "="
  }'
}

fmt() { [ "$1" = null ] && echo "  -  " || printf '%.2f' "$1"; }

echo "reference: $(jq -r .run_id "$REF") [$(jq -r '.candidate // "afb-tdd"' "$REF")]   candidate: $(jq -r .run_id "$CAND") [$(jq -r '.candidate // "afb-tdd"' "$CAND")]"
echo
printf '%-28s %8s %10s %3s\n' "metric" "ref" "candidate" ""
printf '%-28s %8s %10s %3s\n' "----------------------------" "--------" "----------" "---"

for metric in gate_pass_rate judge_mean mutation_mean shot_accuracy_mean; do
  r=$(jq -r ".totals.$metric" "$REF"); c=$(jq -r ".totals.$metric" "$CAND")
  printf '%-28s %8s %10s  %s\n' "$metric" "$(fmt "$r")" "$(fmt "$c")" "$(arrow "$r" "$c")"
done

echo
printf '%-28s %8s %10s %3s\n' "per-gate pass rate" "ref" "candidate" ""
printf '%-28s %8s %10s %3s\n' "----------------------------" "--------" "----------" "---"
for gate in suite_green revert_check process_red_first static_checks; do
  r=$(jq -r "[.tasks[].reps[].gates.$gate] | if length > 0 then (map(if . then 1 else 0 end) | add / length) else \"null\" end" "$REF")
  c=$(jq -r "[.tasks[].reps[].gates.$gate] | if length > 0 then (map(if . then 1 else 0 end) | add / length) else \"null\" end" "$CAND")
  printf '%-28s %8s %10s  %s\n' "$gate" "$(fmt "$r")" "$(fmt "$c")" "$(arrow "$r" "$c")"
done

echo
printf '%-28s %8s %10s %3s\n' "per-task gate pass rate" "ref" "candidate" ""
printf '%-28s %8s %10s %3s\n' "----------------------------" "--------" "----------" "---"
for task in $(jq -r '(.tasks | keys[])' "$REF" "$CAND" | sort -u); do
  r=$(jq -r ".tasks[\"$task\"].rollup.gate_pass_rate // \"null\"" "$REF")
  c=$(jq -r ".tasks[\"$task\"].rollup.gate_pass_rate // \"null\"" "$CAND")
  printf '%-28s %8s %10s  %s\n' "$task" "$(fmt "$r")" "$(fmt "$c")" "$(arrow "$r" "$c")"
done

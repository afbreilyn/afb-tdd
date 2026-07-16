#!/usr/bin/env bash
#
# judge.sh — LLM judge (opt-in via run.sh --with-judge).
#
# Scores the diff 1–5 per dimension against the sceptic rubric. The rubric is
# read from references/sceptic.md at runtime and MUST exist — no embedded
# fallback, so the sceptic and the judge can never diverge. The judge sees the
# artifact only (diff), never the transcript: process is graded
# deterministically by grade-process.sh.
#
# Three single-turn calls per rep; the median per dimension is recorded.
# Model: sonnet by default; override with AFB_JUDGE_MODEL.
#
# Emits: {"judge": {"scores": {...}, "calls": n}}

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKDIR="$1"; FIXTURE="$2"; TASK="$3"; TRANSCRIPT="$4"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUBRIC="$SKILL_DIR/references/sceptic.md"
[ -f "$RUBRIC" ] || { echo "judge.sh: rubric not found at $RUBRIC — refusing to run with a divergent copy" >&2; exit 1; }

MODEL="${AFB_JUDGE_MODEL:-sonnet}"
DIMENSIONS=(assertion_strength one_behaviour_per_test fakes_vs_mocks error_path_coverage naming minimality)

DIFF=$(git -C "$WORKDIR" diff baseline final)
[ -n "$DIFF" ] || { jq -n '{judge: {scores: null, reason: "empty_diff"}}'; exit 0; }

# Part B only — the judgment criteria, not the invocation plumbing.
RUBRIC_TEXT=$(sed -n '/^## Part B/,/^## Part C/p' "$RUBRIC")

PROMPT="You are grading a test-driven change against this rubric:

$RUBRIC_TEXT

Here is the full diff of the change:

$DIFF

Score each dimension from 1 (bad) to 5 (excellent):
- assertion_strength: are assertions exact and meaningful (R1, R2)?
- one_behaviour_per_test: does each test cover exactly one behaviour (R5, R8)?
- fakes_vs_mocks: are doubles used correctly — fakes over mocks, no mock-testing (R3)?
- error_path_coverage: are failure modes enumerated and tested (G5)?
- naming: do test names state the behaviour precisely (R5)?
- minimality: is the implementation the minimum the tests force (G1, G3)?

Return ONLY this JSON, nothing else:
{\"assertion_strength\": n, \"one_behaviour_per_test\": n, \"fakes_vs_mocks\": n, \"error_path_coverage\": n, \"naming\": n, \"minimality\": n, \"notes\": \"one sentence\"}"

collect() { # one judge call; prints the scores JSON or nothing
  local out scores
  out=$(claude -p "$PROMPT" --output-format json --model "$MODEL" 2>/dev/null) || return 1
  scores=$(jq -r '.result' <<<"$out" | sed -e 's/^```json//' -e 's/^```//' -e 's/```$//' | jq -c 'select(.assertion_strength != null)' 2>/dev/null) || return 1
  [ -n "$scores" ] && printf '%s\n' "$scores"
}

CALLS=()
for _ in 1 2 3; do
  if s=$(collect) || s=$(collect); then   # one retry per call
    [ -n "$s" ] && CALLS+=("$s")
  fi
done

[ ${#CALLS[@]} -gt 0 ] || { jq -n '{judge: {scores: null, reason: "all_calls_failed"}}'; exit 0; }

MEDIANS='{}'
for dim in "${DIMENSIONS[@]}"; do
  m=$(printf '%s\n' "${CALLS[@]}" | jq -r ".$dim" | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')
  MEDIANS=$(jq -c --arg d "$dim" --argjson v "$m" '. + {($d): $v}' <<<"$MEDIANS")
done
NOTES=$(jq -r '.notes // ""' <<<"${CALLS[0]}")

jq -n --argjson scores "$MEDIANS" --arg notes "$NOTES" --argjson calls ${#CALLS[@]} \
  '{judge: {scores: ($scores + {notes: $notes}), calls: $calls}}'

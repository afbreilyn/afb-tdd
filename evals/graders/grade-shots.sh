#!/usr/bin/env bash
#
# grade-shots.sh — called-shot accuracy: was the predicted failure what happened?
#
# The skill's Red step demands a called shot ("Expected failure: ...") before
# every test run. This grader pairs each declaration in the transcript with the
# next test-run result (deterministic), then — only when AFB_SHOT_JUDGE=1, set
# by run.sh --with-judge — asks an LLM to classify each pair:
#   match    — run failed and the prediction describes the actual failure
#              (same missing symbol / assertion / error; wording may differ)
#   mismatch — failed for a different reason, or predicted-fail but passed
#   hedge    — the "prediction" itself says the test will pass (no shot called)
# accuracy = match / (match + mismatch); hedges are surfaced, not scored.
# Predictions can't be string-matched: "X is not defined" vs "X is not a
# function" is a correct call — hence model opinion, metric, never a gate.
#
# Three judge calls, per-pair majority (ties resolve conservatively toward
# mismatch). Full pairs incl. output excerpts land in the artifacts dir.
#
# Emits: {"shots": {"transcript_found": bool, "called": n, "paired": n,
#                   "matches": n|null, "mismatches": n|null, "hedges": n|null,
#                   "accuracy": x|null, "judge_calls": n, "pairs": [...]}}

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKDIR="$1"; FIXTURE="$2"; TASK="$3"; TRANSCRIPT="$4"

if [ ! -s "${TRANSCRIPT:-}" ]; then
  jq -n '{shots: {transcript_found: false, called: 0, paired: 0,
                  matches: null, mismatches: null, hedges: null,
                  accuracy: null, judge_calls: 0, pairs: []}}'
  exit 0
fi

TEST_RUN_RE="$(fixture_val "$FIXTURE" test_run_cmd_regex)"
FAIL_RE="$(fixture_val "$FIXTURE" single_fail_pattern)"

# Flatten the main chain into TSV: <id> <shot|use|result> <name|status> <detail>.
# A "shot" row is one "Expected failure:" line from an assistant text block
# (formats vary: "**Expected failure:**", "**Expected failure**:", plain).
EVENTS=$(mktemp); PAIRS=$(mktemp); trap 'rm -f "$EVENTS" "$PAIRS"' EXIT
jq -r '
  select(.isSidechain != true) |
  if .type == "assistant" then
    .message.content[]? |
    if .type == "tool_use" then
      [.id, "use", .name, ((.input.command // "") | gsub("[\t\n]"; " ") | .[0:500])] | @tsv
    elif .type == "text" then
      (.text | match("(?i)expected failure[:*]*[ \\t]*(?<p>[^\\n]+)"; "g") |
       ["-", "shot", "-", (.captures[0].string | gsub("\t"; " ") | .[0:300])]) | @tsv
    else empty end
  elif .type == "user" then
    .message.content[]? | select(.type == "tool_result") |
    [.tool_use_id, "result", (if .is_error == true then "error" else "ok" end),
     ((if (.content | type) == "array" then ([.content[]? | select(.type == "text") | .text] | join(" "))
       elif (.content | type) == "string" then .content else "" end)
      | gsub("[\t\n]"; " ") | .[0:3000])] | @tsv
  else empty end
' "$TRANSCRIPT" > "$EVENTS" 2>/dev/null || true

CALLED=0
PAIRED=0
PENDING_SHOT=""
PENDING_TEST_RUN_ID=""

while IFS=$'\t' read -r id kind name detail; do
  case "$kind" in
    shot)
      CALLED=$((CALLED + 1))
      PENDING_SHOT="$detail"   # a re-called shot before any run replaces the old one
      ;;
    use)
      if [ "$name" = Bash ] && printf '%s' "$detail" | grep -qE "$TEST_RUN_RE"; then
        PENDING_TEST_RUN_ID="$id"
      fi
      ;;
    result)
      [ "$id" = "$PENDING_TEST_RUN_ID" ] || continue
      PENDING_TEST_RUN_ID=""
      outcome=pass
      if [ "$name" = error ] || printf '%s' "$detail" | grep -qE "$FAIL_RE"; then outcome=fail; fi
      if [ -n "$PENDING_SHOT" ]; then   # only the first run after a shot consumes it
        PAIRED=$((PAIRED + 1))
        jq -n --arg p "$PENDING_SHOT" --arg o "$outcome" \
              --arg x "$(printf '%s' "$detail" | tail -c 1500)" \
          '{prediction: $p, outcome: $o, excerpt: $x}' >> "$PAIRS"
        PENDING_SHOT=""
      fi
      ;;
  esac
done < "$EVENTS"

# --- judge (opt-in) ----------------------------------------------------------
VERDICTS=null
JUDGE_CALLS=0
if [ "${AFB_SHOT_JUDGE:-0}" = 1 ] && [ "$PAIRED" -gt 0 ]; then
  MODEL="${AFB_JUDGE_MODEL:-sonnet}"
  PAIRS_TEXT=$(jq -s -r 'to_entries[] |
    "PAIR \(.key + 1)\npredicted failure: \(.value.prediction)\nrun outcome: \(.value.outcome)\nrun output (tail): \(.value.excerpt)\n"' "$PAIRS")

  PROMPT="During a TDD session the author called a shot before each test run: a prediction of how the test would fail. Classify each pair below:
- \"match\": the run failed and the prediction describes the actual failure — same missing symbol, assertion, or error; wording may differ
- \"mismatch\": the run failed for a different reason than predicted, or the prediction expected a failure but the run passed
- \"hedge\": the prediction itself says the test will (probably) pass — no failure was actually predicted

$PAIRS_TEXT

Return ONLY this JSON, nothing else:
{\"verdicts\": [$PAIRED strings, one per pair in order, each \"match\", \"mismatch\" or \"hedge\"], \"notes\": \"one sentence\"}"

  collect() { # one judge call; prints the verdicts JSON or nothing
    local out v
    out=$(claude -p "$PROMPT" --output-format json --model "$MODEL" 2>/dev/null) || return 1
    v=$(jq -r '.result' <<<"$out" | sed -e 's/^```json//' -e 's/^```//' -e 's/```$//' \
        | jq -c --argjson n "$PAIRED" \
            'select((.verdicts | length) == $n and ([.verdicts[] | IN("match","mismatch","hedge")] | all)) | .verdicts' \
            2>/dev/null) || return 1
    [ -n "$v" ] && printf '%s\n' "$v"
  }

  CALLS=()
  for _ in 1 2 3; do
    if s=$(collect) || s=$(collect); then   # one retry per call
      [ -n "$s" ] && CALLS+=("$s")
    fi
  done
  JUDGE_CALLS=${#CALLS[@]}
  if [ "$JUDGE_CALLS" -gt 0 ]; then
    # Per-pair majority. group_by sorts keys, max_by keeps the last maximal
    # group on ties — so hedge < match < mismatch, i.e. ties go conservative.
    VERDICTS=$(printf '%s\n' "${CALLS[@]}" \
      | jq -s -c '[.[]] | transpose | map(group_by(.) | max_by(length) | .[0])')
  fi
fi

# --- emit ---------------------------------------------------------------------
# Full pairs (with excerpts) go to the artifacts dir for drill-down;
# grades.json carries truncated predictions + verdicts only.
ART_DIR="$(dirname "$TRANSCRIPT")"
jq -s --argjson v "$VERDICTS" \
  'to_entries | map(.value + {verdict: (if $v == null then null else $v[.key] end)})' \
  "$PAIRS" > "$ART_DIR/shot-pairs.json" 2>/dev/null || true

jq -s \
  --argjson called "$CALLED" --argjson paired "$PAIRED" \
  --argjson v "$VERDICTS" --argjson calls "$JUDGE_CALLS" '
  ($v // []) as $verdicts |
  ([$verdicts[] | select(. == "match")] | length) as $m |
  ([$verdicts[] | select(. == "mismatch")] | length) as $mm |
  ([$verdicts[] | select(. == "hedge")] | length) as $h |
  {shots: {
    transcript_found: true, called: $called, paired: $paired,
    matches:    (if $v == null then null else $m end),
    mismatches: (if $v == null then null else $mm end),
    hedges:     (if $v == null then null else $h end),
    accuracy:   (if $v == null or ($m + $mm) == 0 then null else ($m / ($m + $mm)) end),
    judge_calls: $calls,
    pairs: (to_entries | map({prediction: (.value.prediction | .[0:160]),
                              outcome: .value.outcome,
                              verdict: (if $v == null then null else $verdicts[.key] end)}))
  }}' "$PAIRS"

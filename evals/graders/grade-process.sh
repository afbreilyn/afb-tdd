#!/usr/bin/env bash
#
# grade-process.sh — gate 3: TDD actually happened, per the transcript.
#
# Parses the session .jsonl into an ordered tool-event stream and checks the
# red-green choreography chronologically. `prod_edits_without_red` is a trend
# metric, not a gate (refactor-phase edits are legitimate).
#
# Emits: {"process": {"transcript_found": bool, "red_before_first_prod_edit": bool,
#                     "cycles": n, "cycle_commits": n, "prod_edits_without_red": n,
#                     "test_runs": n}}

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKDIR="$1"; FIXTURE="$2"; TASK="$3"; TRANSCRIPT="$4"

CYCLE_COMMITS=$(git -C "$WORKDIR" log --oneline baseline..final 2>/dev/null | grep -c 'tdd(cycle' || true)

if [ ! -s "${TRANSCRIPT:-}" ]; then
  jq -n --argjson commits "$CYCLE_COMMITS" \
    '{process: {transcript_found: false, red_before_first_prod_edit: false,
                cycles: 0, cycle_commits: $commits, prod_edits_without_red: 0, test_runs: 0}}'
  exit 0
fi

TEST_RUN_RE="$(fixture_val "$FIXTURE" test_run_cmd_regex)"
FAIL_RE="$(fixture_val "$FIXTURE" single_fail_pattern)"

# Flatten the main-chain transcript into TSV: <id> <use|result> <name|status> <detail>
EVENTS=$(mktemp); trap 'rm -f "$EVENTS"' EXIT
jq -r '
  select(.isSidechain != true) |
  if .type == "assistant" then
    .message.content[]? | select(.type == "tool_use") |
    [.id, "use", .name, ((.input.command // .input.file_path // "") | gsub("[\t\n]"; " ") | .[0:500])] | @tsv
  elif .type == "user" then
    .message.content[]? | select(.type == "tool_result") |
    [.tool_use_id, "result", (if .is_error == true then "error" else "ok" end),
     ((if (.content | type) == "array" then ([.content[]? | select(.type == "text") | .text] | join(" "))
       elif (.content | type) == "string" then .content else "" end)
      | gsub("[\t\n]"; " ") | .[0:3000])] | @tsv
  else empty end
' "$TRANSCRIPT" > "$EVENTS" 2>/dev/null || true

RED_BEFORE_FIRST_PROD=false
FIRST_PROD_SEEN=false
TEST_EDIT_SEEN=false
FAILING_RUN_AFTER_TEST_EDIT=false
LAST_RUN=none        # none | pass | fail
PENDING_RED=false    # inside a red->green arc
HAD_PROD_EDIT=false
CYCLES=0
PROD_NO_RED=0
TEST_RUNS=0
PENDING_TEST_RUN_ID=""

while IFS=$'\t' read -r id kind name detail; do
  if [ "$kind" = use ]; then
    case "$name" in
      Bash)
        if printf '%s' "$detail" | grep -qE "$TEST_RUN_RE"; then PENDING_TEST_RUN_ID="$id"; fi
        ;;
      Edit|Write|MultiEdit|NotebookEdit)
        # Transcript paths vary by model/session: absolute with a /private
        # prefix the workdir path lacks (macOS), or relative with a leading ./ —
        # normalise all of them to workdir-relative.
        rel="${detail#"$WORKDIR"/}"
        case "$rel" in /*) rel="${rel#*/"$(basename "$WORKDIR")"/}" ;; esac
        rel="${rel#./}"
        case "$(classify_file "$rel" "$FIXTURE")" in
          test) TEST_EDIT_SEEN=true ;;
          prod)
            if [ "$FIRST_PROD_SEEN" = false ]; then
              FIRST_PROD_SEEN=true
              [ "$FAILING_RUN_AFTER_TEST_EDIT" = true ] && RED_BEFORE_FIRST_PROD=true
            fi
            [ "$LAST_RUN" != fail ] && PROD_NO_RED=$((PROD_NO_RED + 1))
            [ "$PENDING_RED" = true ] && HAD_PROD_EDIT=true
            ;;
        esac
        ;;
    esac
  elif [ "$kind" = result ] && [ "$id" = "$PENDING_TEST_RUN_ID" ]; then
    PENDING_TEST_RUN_ID=""
    TEST_RUNS=$((TEST_RUNS + 1))
    if [ "$name" = error ] || printf '%s' "$detail" | grep -qE "$FAIL_RE"; then
      LAST_RUN=fail
      [ "$TEST_EDIT_SEEN" = true ] && FAILING_RUN_AFTER_TEST_EDIT=true
      PENDING_RED=true; HAD_PROD_EDIT=false
    else
      LAST_RUN=pass
      if [ "$PENDING_RED" = true ] && [ "$HAD_PROD_EDIT" = true ]; then
        CYCLES=$((CYCLES + 1))
      fi
      PENDING_RED=false; HAD_PROD_EDIT=false
    fi
  fi
done < "$EVENTS"

jq -n --argjson red_first "$RED_BEFORE_FIRST_PROD" --argjson cycles "$CYCLES" \
  --argjson commits "$CYCLE_COMMITS" --argjson no_red "$PROD_NO_RED" --argjson runs "$TEST_RUNS" \
  '{process: {transcript_found: true, red_before_first_prod_edit: $red_first,
              cycles: $cycles, cycle_commits: $commits,
              prod_edits_without_red: $no_red, test_runs: $runs}}'

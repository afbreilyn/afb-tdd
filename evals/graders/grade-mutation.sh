#!/usr/bin/env bash
#
# grade-mutation.sh — mutation score on the changed prod files (opt-in via
# run.sh --with-mutation). Stryker for TS/Vitest, go-mutesting (avito-tech
# fork) for Go. Adds 1–5 min per rep.
#
# Emits: {"mutation": {"score": 0.86, "tool": "..."}} or {"mutation": {"skipped": "..."}}

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKDIR="$1"; FIXTURE="$2"; TASK="$3"; TRANSCRIPT="$4"

PROD_FILES=()
while IFS= read -r f; do [ -n "$f" ] && PROD_FILES+=("$f"); done \
  < <(changed_files "$WORKDIR" prod "$FIXTURE")

if [ ${#PROD_FILES[@]} -eq 0 ]; then
  jq -n '{mutation: {skipped: "no_prod_changes"}}'
  exit 0
fi

if [ -f "$WORKDIR/go.mod" ]; then
  # go install drops binaries in GOPATH/bin, which is often not on PATH
  have go && PATH="$PATH:$(go env GOPATH)/bin"
  have go-mutesting || { jq -n '{mutation: {skipped: "go-mutesting not installed"}}'; exit 0; }
  OUT=$(cd "$WORKDIR" && go-mutesting "${PROD_FILES[@]}" 2>&1 || true)
  SCORE=$(printf '%s' "$OUT" | sed -nE 's/.*The mutation score is ([0-9.]+).*/\1/p' | tail -1)
  [ -n "$SCORE" ] || { jq -n '{mutation: {skipped: "score not found in go-mutesting output"}}'; exit 0; }
  jq -n --argjson score "$SCORE" '{mutation: {score: $score, tool: "go-mutesting"}}'
else
  MUTATE=$(IFS=,; echo "${PROD_FILES[*]}")
  (cd "$WORKDIR" && npx stryker run --mutate "$MUTATE" --reporters json >/dev/null 2>&1) || true
  REPORT="$WORKDIR/reports/mutation/mutation.json"
  [ -f "$REPORT" ] || { jq -n '{mutation: {skipped: "stryker produced no report"}}'; exit 0; }
  SCORE=$(jq '[.files[].mutants[]] | (map(select(.status == "Killed" or .status == "Timeout")) | length) as $detected
              | (map(select(.status == "Survived" or .status == "NoCoverage")) | length) as $missed
              | if ($detected + $missed) == 0 then null else ($detected / ($detected + $missed)) end' "$REPORT")
  jq -n --argjson score "$SCORE" '{mutation: {score: $score, tool: "stryker"}}'
fi

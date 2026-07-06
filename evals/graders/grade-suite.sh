#!/usr/bin/env bash
#
# grade-suite.sh — gate 1: the suite is green and the output is pristine.
#
# Emits: {"suite": {"green": bool, "pristine": bool, "new_test_count": n}}

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKDIR="$1"; FIXTURE="$2"; TASK="$3"; TRANSCRIPT="$4"

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

GREEN=false
if run_suite "$WORKDIR" "$FIXTURE" "$OUT"; then GREEN=true; fi

PRISTINE=true
if grep -viE '^npm (warn|notice)' "$OUT" | grep -qiE 'warn|deprecat|console\.error'; then PRISTINE=false; fi

# Count test cases added between baseline and final (added diff lines only).
NEW_TESTS=$(git -C "$WORKDIR" diff baseline final -- '*_test.go' '*.test.ts' '*.test.tsx' \
  | grep -cE '^\+\s*(it\(|test\(|it\.each|test\.each|func\s+\(?[a-zA-Z_]*\s*\*?[a-zA-Z_]*\)?\s*Test|s\.Run\(|t\.Run\(|func Test)' || true)

jq -n --argjson green "$GREEN" --argjson pristine "$PRISTINE" --argjson n "$NEW_TESTS" \
  '{suite: {green: $green, pristine: $pristine, new_test_count: $n}}'

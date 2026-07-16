#!/usr/bin/env bash
#
# grade-revert.sh — gate 2: the new tests actually constrain the implementation.
#
# Reverts the production-file changes (keeping test changes), reruns the suite,
# and passes only if the suite now fails — ideally naming a newly added test.
# The gate is deliberately "suite fails", not "a new test is named": reverting
# prod files usually breaks imports/compilation, which fails the whole file
# without naming any test. new_test_named_in_failures is kept as a soft signal.
# Restores the workdir to `final` afterwards.
#
# Emits: {"revert": {"pass": bool, "suite_failed_after_revert": bool,
#                    "new_test_named_in_failures": bool, "prod_files_reverted": n}}

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKDIR="$1"; FIXTURE="$2"; TASK="$3"; TRANSCRIPT="$4"

PROD_FILES=()
while IFS= read -r f; do [ -n "$f" ] && PROD_FILES+=("$f"); done \
  < <(changed_files "$WORKDIR" prod "$FIXTURE")

if [ ${#PROD_FILES[@]} -eq 0 ]; then
  jq -n '{revert: {pass: false, reason: "no_prod_changes", prod_files_reverted: 0}}'
  exit 0
fi

# Revert prod changes: restore files that existed at baseline, delete new ones.
for f in "${PROD_FILES[@]}"; do
  if git -C "$WORKDIR" cat-file -e "baseline:$f" 2>/dev/null; then
    git -C "$WORKDIR" checkout -q baseline -- "$f"
  else
    git -C "$WORKDIR" rm -qf "$f" >/dev/null
  fi
done

OUT=$(mktemp)
SUITE_FAILED=false
if ! run_suite "$WORKDIR" "$FIXTURE" "$OUT"; then SUITE_FAILED=true; fi

# Does the failure output name a newly added test?
NAMED=false
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if grep -qF "$name" "$OUT"; then NAMED=true; break; fi
done < <(git -C "$WORKDIR" diff baseline final -- '*_test.go' '*.test.ts' '*.test.tsx' \
  | sed -nE 's/^\+\s*(it|test)\((["'"'"'])([^"'"'"']+)\2.*/\3/p; s/^\+func (\(?[^)]*\)? )?(Test[A-Za-z0-9_]+).*/\2/p')

git -C "$WORKDIR" reset -q --hard final
rm -f "$OUT"

PASS=$SUITE_FAILED
jq -n --argjson pass "$PASS" --argjson failed "$SUITE_FAILED" --argjson named "$NAMED" \
  --argjson n ${#PROD_FILES[@]} \
  '{revert: {pass: $pass, suite_failed_after_revert: $failed,
             new_test_named_in_failures: $named, prod_files_reverted: $n}}'

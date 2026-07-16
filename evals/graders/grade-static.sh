#!/usr/bin/env bash
#
# grade-static.sh — gate 4: cheap greps over the change.
#
# Built-in convention checks run over the ADDED diff lines (split by prod/test
# file); the task's extra_checks add rule-specific greps. Built-in counts are
# trend metrics; the gate is: every extra_check passes and jest usage is zero.
# ("and" in a test name is a count only — camel-case names like SortsAndJoins
# describe one behaviour and made it a false-positive gate.)
#
# Emits: {"static": {"pass": bool, "counts": {...}, "extra_checks": [...]}}

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKDIR="$1"; FIXTURE="$2"; TASK="$3"; TRANSCRIPT="$4"

TEST_ADDED=$(mktemp); PROD_ADDED=$(mktemp)
trap 'rm -f "$TEST_ADDED" "$PROD_ADDED"' EXIT

while IFS= read -r f; do
  [ -n "$f" ] || continue
  kind="$(classify_file "$f" "$FIXTURE")"
  [ "$kind" = other ] && continue
  dest="$PROD_ADDED"; [ "$kind" = test ] && dest="$TEST_ADDED"
  git -C "$WORKDIR" diff baseline final -- "$f" | grep -E '^\+[^+]' | cut -c2- >> "$dest" || true
done < <(git -C "$WORKDIR" diff --name-only baseline final)

count() { grep -cE "$1" "$2" 2>/dev/null || true; }

AS_CASTS=$(count '\bas [A-Z][A-Za-z]*' "$TEST_ADDED")
TESTID=$(count 'ByTestId|data-testid' "$TEST_ADDED")
AND_NAMES=$(count '(it|test)\(["'"'"'][^"'"'"']* and |func [^(]*Test[A-Za-z0-9_]*And[A-Z]' "$TEST_ADDED")
VITEST_IMPORTS=$(count 'from ["'"'"']vitest["'"'"']' "$TEST_ADDED")
JEST_USAGE=$(count '\bjest\.' "$TEST_ADDED")
FOREACH=$(count '\.forEach\(' "$TEST_ADDED")
WALL_CLOCK_PROD=$(count 'time\.Now\(\)|new Date\(\)|Date\.now\(\)' "$PROD_ADDED")
RAW_STRUCTS=$(count '&domain\.[A-Z][A-Za-z]*\{' "$TEST_ADDED")

# Test-only exported prod functions (best effort, count only): a newly added
# exported Go func in prod that no prod file references.
TEST_ONLY_FUNCS=0
while IFS= read -r fn; do
  [ -n "$fn" ] || continue
  refs=0
  while IFS= read -r f; do
    [ "$(classify_file "$f" "$FIXTURE")" = prod ] || continue
    n=$(git -C "$WORKDIR" show "final:$f" | grep -cE "[^a-zA-Z_]$fn\(" || true)
    refs=$((refs + n))
  done < <(git -C "$WORKDIR" ls-tree -r --name-only final | grep '\.go$' || true)
  # one hit is the definition itself
  [ "$refs" -le 1 ] && TEST_ONLY_FUNCS=$((TEST_ONLY_FUNCS + 1))
done < <(sed -nE 's/^func (\([^)]*\) )?([A-Z][A-Za-z0-9_]*)\(.*/\2/p' "$PROD_ADDED" | sort -u)

# --- task-specific extra checks ----------------------------------------------
EXTRA_RESULTS='[]'
EXTRA_PASS=true
while IFS= read -r check; do
  [ -n "$check" ] || continue
  name=$(jq -r .name <<<"$check")
  glob=$(jq -r .glob <<<"$check")
  forbid=$(jq -r '.forbid_regex // empty' <<<"$check")
  require=$(jq -r '.require_regex // empty' <<<"$check")
  min=$(jq -r '.min_count // 1' <<<"$check")

  matched=0
  if [ -n "$forbid" ]; then
    # forbid: grep the FINAL content of every matching file
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if matches_globs "$f" "$(jq -nc --arg g "$glob" '[$g]')"; then
        n=$(git -C "$WORKDIR" show "final:$f" | grep -coE "$forbid" || true)
        matched=$((matched + n))
      fi
    done < <(git -C "$WORKDIR" ls-tree -r --name-only final)
    ok=$([ "$matched" -eq 0 ] && echo true || echo false)
  else
    # require: grep the added diff lines of matching files
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if matches_globs "$f" "$(jq -nc --arg g "$glob" '[$g]')"; then
        n=$(git -C "$WORKDIR" diff baseline final -- "$f" | grep -E '^\+[^+]' | grep -oE "$require" | wc -l | tr -d ' ')
        matched=$((matched + n))
      fi
    done < <(git -C "$WORKDIR" diff --name-only baseline final)
    ok=$([ "$matched" -ge "$min" ] && echo true || echo false)
  fi

  [ "$ok" = true ] || EXTRA_PASS=false
  EXTRA_RESULTS=$(jq -c --arg name "$name" --argjson ok "$ok" --argjson n "$matched" \
    '. + [{name: $name, pass: $ok, count: $n}]' <<<"$EXTRA_RESULTS")
done < <(jq -c '.extra_checks[]?' "$TASK")

PASS=true
{ [ "$EXTRA_PASS" = true ] && [ "$JEST_USAGE" -eq 0 ]; } || PASS=false

jq -n --argjson pass "$PASS" --argjson extra "$EXTRA_RESULTS" \
  --argjson as_casts "$AS_CASTS" --argjson testid "$TESTID" --argjson and_names "$AND_NAMES" \
  --argjson vitest_imports "$VITEST_IMPORTS" --argjson jest "$JEST_USAGE" \
  --argjson foreach "$FOREACH" --argjson wall_clock "$WALL_CLOCK_PROD" \
  --argjson raw_structs "$RAW_STRUCTS" --argjson test_only_funcs "$TEST_ONLY_FUNCS" \
  '{static: {pass: $pass,
             counts: {as_casts_in_tests: $as_casts, testid_selectors: $testid,
                      and_in_test_name: $and_names, vitest_imports: $vitest_imports,
                      jest_usage: $jest, foreach_in_tests: $foreach,
                      wall_clock_in_prod: $wall_clock,
                      raw_domain_structs_in_tests: $raw_structs,
                      test_only_exported_funcs: $test_only_funcs},
             extra_checks: $extra}}'

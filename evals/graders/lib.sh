#!/usr/bin/env bash
#
# lib.sh — shared helpers for the eval graders.
#
# Every grader has the same interface:
#   grade-<name>.sh <workdir> <fixture.json> <task.json> <transcript.jsonl>
# and prints a single JSON object to stdout. run.sh merges the objects.
#
# File classification: test_globs are evaluated BEFORE prod_globs, so test
# helpers (fakes, builders, contract suites) classify as test-side even though
# they also match the prod globs.

have() { command -v "$1" >/dev/null 2>&1; }

fixture_val() { # fixture_val <fixture.json> <key>
  jq -r ".$2" "$1"
}

# Convert a glob like "src/**/*.test.ts" into an anchored ERE.
# Wildcards are first swapped for control-char placeholders so later
# substitutions can't mangle the replacement text of earlier ones.
glob_to_regex() {
  local glob="$1" re
  re=$(printf '%s' "$glob" | sed -E \
    -e 's/[.]/\\./g' \
    -e $'s|\\*\\*/|\001|g' \
    -e $'s|\\*\\*|\002|g' \
    -e 's|\*|[^/]*|g' \
    -e $'s|\001|(.*/)?|g' \
    -e $'s|\002|.*|g')
  printf '^%s$' "$re"
}

# matches_globs <file> <json-array-of-globs>
# NB: don't name any local "path" — zsh ties $path to $PATH.
matches_globs() {
  local file="$1" globs_json="$2" glob
  while IFS= read -r glob; do
    [ -n "$glob" ] || continue
    if printf '%s' "$file" | grep -qE "$(glob_to_regex "$glob")"; then
      return 0
    fi
  done < <(printf '%s' "$globs_json" | jq -r '.[]')
  return 1
}

# classify_file <file> <fixture.json>  ->  "test" | "prod" | "other"
classify_file() {
  local file="$1" fixture="$2"
  if matches_globs "$file" "$(jq -c '.test_globs' "$fixture")"; then
    echo test
  elif matches_globs "$file" "$(jq -c '.prod_globs' "$fixture")"; then
    echo prod
  else
    echo other
  fi
}

# changed_files <workdir> [kind fixture.json]
# Lists files changed between the `baseline` and `final` tags; optionally
# filtered to kind (test|prod|other).
changed_files() {
  local workdir="$1" kind="${2:-}" fixture="${3:-}" f
  git -C "$workdir" diff --name-only baseline final | while IFS= read -r f; do
    if [ -z "$kind" ] || [ "$(classify_file "$f" "$fixture")" = "$kind" ]; then
      printf '%s\n' "$f"
    fi
  done
}

# run_suite <workdir> <fixture.json> <output-file>  ->  exit code of the suite
run_suite() {
  local workdir="$1" fixture="$2" out="$3" cmd
  cmd=$(fixture_val "$fixture" test_cmd)
  (cd "$workdir" && eval "$cmd") >"$out" 2>&1
}

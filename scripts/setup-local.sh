#!/usr/bin/env bash
#
# setup-local.sh — scaffold a project-local afb-tdd skill, pre-filled with sane
# defaults inferred from the current repository.
#
# All detection here is deterministic shell (zero LLM tokens). It writes two files
# into <repo>/.claude/skills/afb-tdd/:
#   - DIGEST.txt     a compact summary of what was detected + the human-only
#                    questions that still need answering
#   - SKILL.md.draft a pre-filled local skill; the calling skill confirms the
#                    open questions and promotes it to SKILL.md
#
# The generated local skill links ONLY the conventions matching the detected
# stack — that is what keeps each TDD cycle's context small.
#
# Usage: setup-local.sh [--force]
#   --force   regenerate even if a local SKILL.md already exists

set -euo pipefail

GLOBAL_CONV="~/.claude/skills/afb-tdd/references/conventions"

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# --- locate the repo -------------------------------------------------------
if ! REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "Not inside a git repository. Run this from your project root." >&2
  exit 1
fi
cd "$REPO_ROOT"

TARGET_DIR="$REPO_ROOT/.claude/skills/afb-tdd"
SKILL_FILE="$TARGET_DIR/SKILL.md"
DIGEST_FILE="$TARGET_DIR/DIGEST.txt"
DRAFT_FILE="$TARGET_DIR/SKILL.md.draft"

# --- idempotency guard -----------------------------------------------------
if [ -f "$SKILL_FILE" ] && [ "$FORCE" -ne 1 ]; then
  echo "A local skill already exists at $SKILL_FILE"
  echo "Nothing to do. Re-run with --force to regenerate from scratch."
  exit 0
fi

mkdir -p "$TARGET_DIR"

# --- helpers ---------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# Read a script entry from package.json (jq if available, crude grep otherwise).
pkg_script() {
  local key="$1"
  [ -f package.json ] || return 0
  if have jq; then
    jq -r --arg k "$key" '.scripts[$k] // empty' package.json 2>/dev/null
  else
    grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" package.json | head -1 \
      | sed -E "s/.*:[[:space:]]*\"([^\"]*)\"/\1/"
  fi
}

# Is a (dev)dependency present in package.json?
has_dep() {
  local name="$1"
  [ -f package.json ] || return 1
  if have jq; then
    jq -e --arg n "$name" \
      '((.dependencies // {}) + (.devDependencies // {})) | has($n)' \
      package.json >/dev/null 2>&1
  else
    grep -qE "\"$name\"[[:space:]]*:" package.json
  fi
}

# First glob among tracked files matching a pattern; prints up to 2 example dirs.
# `|| true` keeps an empty match from tripping set -e / pipefail.
example_dirs_for() {
  local pattern="$1"
  { git ls-files 2>/dev/null | grep -E "$pattern" || true; } | sed -E 's#/[^/]+$##' \
    | sort -u | head -2 | paste -sd', ' -
}

# --- detection -------------------------------------------------------------
LANGS=()
CONV=()              # convention basenames to link (relevant stack only)
TEST_CMD=""
SINGLE_CMD=""
E2E_FW=""
E2E_CMD=""
GATES=()
TEST_NAMING=""
NOTES=()

# Languages / runners
if [ -f go.mod ]; then
  LANGS+=("Go")
  CONV+=("go.md")
  TEST_NAMING="${TEST_NAMING}Go: *_test.go (e.g. $(example_dirs_for '_test\.go$'))\n"
fi

if [ -f package.json ]; then
  if has_dep vitest; then
    LANGS+=("JS/TS (vitest)"); CONV+=("vitest.md")
  elif has_dep jest; then
    LANGS+=("JS/TS (jest)")
  fi
  # Frontend conventions apply when a UI framework / testing-library is present.
  if has_dep @testing-library/react || has_dep @testing-library/vue \
     || has_dep react || has_dep vue || has_dep svelte; then
    CONV+=("frontend.md")
  fi
  TEST_NAMING="${TEST_NAMING}JS/TS: *.test.ts(x) / *.spec.ts (e.g. $(example_dirs_for '\.(test|spec)\.(t|j)sx?$'))\n"
fi

if [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  LANGS+=("Java (JUnit)")
  CONV+=("java.md")
  TEST_NAMING="${TEST_NAMING}Java: src/test/java (e.g. $(example_dirs_for 'src/test/java'))\n"
fi

if [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then
  LANGS+=("Python (pytest)")
  NOTES+=("No Python conventions file exists yet — none linked.")
  TEST_NAMING="${TEST_NAMING}Python: test_*.py / *_test.py (e.g. $(example_dirs_for '(test_|_test)\.py$'))\n"
fi

# Test command — Makefile target wins, then package.json, then language default.
if [ -f Makefile ] && grep -qE '^test:' Makefile; then
  TEST_CMD="make test"
elif [ -f package.json ] && [ -n "$(pkg_script test)" ]; then
  TEST_CMD="npm test"
  SINGLE_CMD="npm test -- <file>   # NEEDS CONFIRMATION"
elif [ -f go.mod ]; then
  TEST_CMD="go test ./..."
  SINGLE_CMD="go test ./path -run TestName"
elif [ -f pom.xml ]; then
  TEST_CMD="mvn test"
  SINGLE_CMD="mvn test -Dtest=ClassName#method"
elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  TEST_CMD="./gradlew test"
  SINGLE_CMD="./gradlew test --tests ClassName.method"
elif [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then
  TEST_CMD="pytest"
  SINGLE_CMD="pytest path::TestName"
else
  TEST_CMD="# TODO: no test command detected — fill this in"
fi

# E2E framework
if has_dep @playwright/test; then
  E2E_FW="Playwright"
elif has_dep cypress; then
  E2E_FW="Cypress"
fi
if [ -n "$E2E_FW" ]; then
  E2E_CMD="$(pkg_script test:e2e)"
  [ -z "$E2E_CMD" ] && E2E_CMD="$(pkg_script e2e)"
  if [ -z "$E2E_CMD" ]; then
    [ "$E2E_FW" = "Playwright" ] && E2E_CMD="npx playwright test" || E2E_CMD="npx cypress run"
  fi
fi

# Green gates: lint / typecheck / format
if [ -f package.json ]; then
  [ -n "$(pkg_script lint)" ] && GATES+=("npm run lint")
  [ -n "$(pkg_script typecheck)" ] && GATES+=("npm run typecheck")
  { [ -z "$(pkg_script typecheck)" ] && [ -f tsconfig.json ]; } && GATES+=("npx tsc --noEmit   # NEEDS CONFIRMATION")
  [ -n "$(pkg_script format)" ] && GATES+=("npm run format")
fi
if ls .golangci.* >/dev/null 2>&1; then GATES+=("golangci-lint run"); fi
[ -f go.mod ] && GATES+=("go vet ./...")

# Candidate test-infrastructure directories
HELPERS=$({ git ls-files 2>/dev/null \
  | grep -oE '(^|/)(testutils?|__mocks__|mocks|fixtures|factories|testdata|test/support|spec/support|test-utils)(/|$)' \
  || true; } | sed -E 's#^/##; s#/$##' | sort -u | head -8 | paste -sd', ' -)
[ -z "$HELPERS" ] && HELPERS="(none auto-detected — ask the human)"

# Conventions: de-duplicate
CONV_UNIQUE=$({ printf '%s\n' "${CONV[@]:-}" | grep -v '^$' || true; } | sort -u)

# --- emit DIGEST.txt -------------------------------------------------------
{
  echo "afb-tdd setup digest — generated for: $REPO_ROOT"
  echo
  echo "DETECTED (auto-answered, confirm only):"
  echo "  Languages/runners : ${LANGS[*]:-none}"
  echo "  Full test command : $TEST_CMD"
  [ -n "$SINGLE_CMD" ] && echo "  Single test       : $SINGLE_CMD"
  echo "  Green gates       : ${GATES[*]:-none detected}"
  echo "  Conventions to link:"
  if [ -n "$CONV_UNIQUE" ]; then
    while IFS= read -r c; do echo "      - $c"; done <<< "$CONV_UNIQUE"
  else
    echo "      (none — stack unrecognized)"
  fi
  echo "  Test naming/locations:"
  printf "      %b" "${TEST_NAMING:-      (none detected)\n}"
  echo "  E2E framework     : ${E2E_FW:-none detected}"
  [ -n "$E2E_CMD" ] && echo "  E2E command       : $E2E_CMD"
  echo "  Candidate helpers : $HELPERS"
  if [ ${#NOTES[@]} -gt 0 ]; then
    echo
    echo "NOTES:"
    for n in "${NOTES[@]}"; do echo "  - $n"; done
  fi
  echo
  echo "ASK THE HUMAN (cannot be auto-detected reliably):"
  echo "  Q5 E2E default    : Should TDD here START at the E2E layer"
  echo "                      (proposed: ${E2E_FW:-no — no E2E framework found})?"
  echo "  Q6 Canonical infra: Of the candidate helper dirs above, which are the"
  echo "                      real builders/fakes/fixtures Claude should reuse?"
  echo "  Q7 Domain gotchas : DB setup/teardown & seeding, auth/multi-tenancy,"
  echo "                      clock/time control, external-service stubbing,"
  echo "                      test isolation/parallelism — which apply?"
  echo "  Q8 Commits        : Any project commit-message format or pre-commit"
  echo "                      hooks beyond the global 'no co-author' rule?"
} > "$DIGEST_FILE"

# --- emit SKILL.md.draft ---------------------------------------------------
{
  cat <<'EOF'
---
name: afb-tdd
description: Interactive red-green-refactor TDD workflow.
user-invocable: true
allowed-tools: Bash
---

Follow the TDD workflow defined in [~/.claude/skills/afb-tdd/SKILL.md](~/.claude/skills/afb-tdd/SKILL.md).

## Project-specific

### Commands
EOF
  echo "- Full suite: \`$TEST_CMD\`"
  [ -n "$SINGLE_CMD" ] && echo "- Single test: \`$SINGLE_CMD\`"
  if [ ${#GATES[@]} -gt 0 ]; then
    echo "- Before declaring green, also run:"
    for g in "${GATES[@]}"; do echo "  - \`$g\`"; done
  fi
  if [ -n "$E2E_CMD" ]; then
    echo "- E2E ($E2E_FW): \`$E2E_CMD\`"
  fi

  echo
  echo "### Conventions"
  if [ -n "$CONV_UNIQUE" ]; then
    while IFS= read -r c; do
      echo "- See [$c]($GLOBAL_CONV/$c)"
    done <<< "$CONV_UNIQUE"
  else
    echo "- # TODO: no stack-specific conventions detected"
  fi
  echo "- Tests live where shown in the digest; match the existing naming convention."

  cat <<'EOF'

### Test infrastructure to reuse
EOF
  echo "<!-- NEEDS CONFIRMATION: pick the canonical ones from these candidates -->"
  echo "- Candidates detected: $HELPERS"

  cat <<'EOF'

### Domain gotchas
<!-- NEEDS CONFIRMATION: filled from the human's answers (Q7) -->
- # TODO: DB setup/teardown, auth/tenancy, time control, external stubs, isolation

### Commits
- Do not attribute commits to Claude or list it as a co-author.
<!-- NEEDS CONFIRMATION: add any project-specific message format / hooks (Q8) -->
EOF
} > "$DRAFT_FILE"

echo "Wrote:"
echo "  $DIGEST_FILE"
echo "  $DRAFT_FILE"
echo
echo "Next: the skill will confirm the open questions and promote the draft to SKILL.md."

#!/usr/bin/env bash
#
# setup-local.sh — scaffold a project-local afb-tdd skill, pre-filled with sane
# defaults inferred from the current repository.
#
# All detection here is deterministic shell (zero LLM tokens). It writes two files
# into <repo>/.claude/skills/afb-tdd/:
#   - DIGEST.txt     a compact summary of what was detected, the project files worth
#                    reading in Setup Mode, and the human-only questions
#   - SKILL.md.draft a pre-filled local skill; Setup Mode reads the located project
#                    files, fills the prose, confirms the questions, and promotes it
#
# The generated skill links the project's OWN rules/docs (or the stack-relevant
# global conventions if it has none) rather than inlining them — rich but link-based,
# so each TDD cycle loads a small, relevant context.
#
# Usage: setup-local.sh [--force] [--simple] [--polyrepo|--no-polyrepo]
#   --force        regenerate even if a local SKILL.md already exists
#   --simple       skip the test-suite audit inventory (by DEFAULT it's included, so
#                  Setup Mode runs the gold-standard / known-deviations audit). Aliases:
#                  --shallow
#   --polyrepo     force polyrepo mode (delegate to setup-polyrepo.sh)
#   --no-polyrepo  force single-repo mode even if child git repos are present

set -euo pipefail

GLOBAL_CONV="~/.claude/skills/afb-tdd/references/conventions"
R="../../.."   # path from .claude/skills/afb-tdd/SKILL.md back to the repo root

FORCE=0
DEEP=1   # the deep audit is the default; --simple opts out
POLY=auto   # auto | force | off
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --deep)  DEEP=1 ;;             # explicit; also the default
    --simple|--shallow) DEEP=0 ;;  # opt out of the test audit
    --polyrepo) POLY=force ;;
    --no-polyrepo) POLY=off ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# --- polyrepo detection (first, off CWD; ignores this dir's own git state) --
# A polyrepo is a container holding >=2 independent git repos as immediate
# children. We detect that before the single-repo git guard so it works even
# when the container itself has no .git. Submodules (in .gitmodules) don't count.
if [ "$POLY" != off ]; then
  POLY_MEMBERS=0
  SUBMODULES=""
  [ -f .gitmodules ] && SUBMODULES=$(grep -oE 'path[[:space:]]*=[[:space:]]*.*' .gitmodules 2>/dev/null | sed -E 's/.*=[[:space:]]*//' || true)
  for d in */; do
    d="${d%/}"
    [ -e "$d/.git" ] || continue
    if [ -n "$SUBMODULES" ] && printf '%s\n' "$SUBMODULES" | grep -qx "$d"; then continue; fi
    POLY_MEMBERS=$((POLY_MEMBERS + 1))
  done
  if [ "$POLY" = force ] || [ "$POLY_MEMBERS" -ge 2 ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    exec bash "$SCRIPT_DIR/setup-polyrepo.sh" "$@"
  fi
fi

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

# Read a script entry from the primary package.json (jq if available, else grep).
pkg_script() {
  local key="$1"
  [ -n "$PKG_JSON" ] || return 0
  if have jq; then
    jq -r --arg k "$key" '.scripts[$k] // empty' "$PKG_JSON" 2>/dev/null
  else
    grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$PKG_JSON" | head -1 \
      | sed -E "s/.*:[[:space:]]*\"([^\"]*)\"/\1/"
  fi
}

# Is a (dev)dependency present in the primary package.json?
has_dep() {
  local name="$1"
  [ -n "$PKG_JSON" ] || return 1
  if have jq; then
    jq -e --arg n "$name" \
      '((.dependencies // {}) + (.devDependencies // {})) | has($n)' \
      "$PKG_JSON" >/dev/null 2>&1
  else
    grep -qE "\"$name\"[[:space:]]*:" "$PKG_JSON"
  fi
}

# Up to N example dirs among tracked files matching a pattern.
example_dirs_for() {
  local pattern="$1"
  { git ls-files 2>/dev/null | grep -E "$pattern" || true; } | sed -E 's#/[^/]+$##' \
    | sort -u | head -2 | paste -sd',' - | sed 's/,/, /g'
}

# Count tracked test files under a path prefix (Go + TS/JS).
count_tests_under() {
  local prefix="$1"
  { git ls-files "$prefix" 2>/dev/null \
    | grep -cE '(_test\.go|\.(test|spec)\.(t|j)sx?)$' || true; }
}

# --- locate the primary package.json (root, or a frontend subdir in a monorepo) ---
PKG_JSON=""; PKG_DIR=""; NPM_PFX=""
for cand in package.json frontend/package.json web/package.json ui/package.json client/package.json app/package.json; do
  [ -f "$cand" ] && { PKG_JSON="$cand"; break; }
done
[ -z "$PKG_JSON" ] && PKG_JSON=$(git ls-files '*package.json' 2>/dev/null | grep -v node_modules | head -1 || true)
if [ -n "$PKG_JSON" ]; then
  PKG_DIR=$(dirname "$PKG_JSON")
  [ "$PKG_DIR" != "." ] && NPM_PFX="cd $PKG_DIR && "
fi

# --- detection: languages / runners ----------------------------------------
LANGS=()
CONV=()              # stack-relevant global conventions (fallback only)
TEST_NAMING=""
NOTES=()

if [ -f go.mod ] || [ -f go.work ]; then
  LANGS+=("Go"); CONV+=("go.md")
  TEST_NAMING="${TEST_NAMING}Go: *_test.go (e.g. $(example_dirs_for '_test\.go$'))\n"
fi
if [ -n "$PKG_JSON" ]; then
  if has_dep vitest; then LANGS+=("JS/TS (vitest)"); CONV+=("vitest.md")
  elif has_dep jest; then LANGS+=("JS/TS (jest)"); fi
  if has_dep @testing-library/react || has_dep @testing-library/vue \
     || has_dep react || has_dep vue || has_dep svelte; then CONV+=("frontend.md"); fi
  TEST_NAMING="${TEST_NAMING}JS/TS: *.test.ts(x) / *.spec.ts (e.g. $(example_dirs_for '\.(test|spec)\.(t|j)sx?$'))\n"
fi
if [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  LANGS+=("Java (JUnit)"); CONV+=("java.md")
  TEST_NAMING="${TEST_NAMING}Java: src/test/java (e.g. $(example_dirs_for 'src/test/java'))\n"
fi
if [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then
  LANGS+=("Python (pytest)")
  NOTES+=("No Python conventions file exists yet — none linked.")
  TEST_NAMING="${TEST_NAMING}Python: test_*.py / *_test.py (e.g. $(example_dirs_for '(test_|_test)\.py$'))\n"
fi
CONV_UNIQUE=$({ printf '%s\n' "${CONV[@]:-}" | grep -v '^$' || true; } | sort -u)

# --- detection: project's own rules / instruction files --------------------
# These supersede the global conventions when present.
RULESET=()        # path-scoped style rules (.claude/rules, .cursor/rules)
INSTRUCTIONS=()   # general instruction files (CLAUDE.md, AGENTS.md, ...)

if [ -d .claude/rules ]; then
  while IFS= read -r f; do RULESET+=("$f"); done \
    < <(git ls-files '.claude/rules/*.md' 2>/dev/null | sort; \
        { [ -z "$(git ls-files '.claude/rules/*.md' 2>/dev/null)" ] && \
          find .claude/rules -maxdepth 1 -name '*.md' 2>/dev/null | sed 's#^\./##' | sort; } || true)
fi
if [ -d .cursor/rules ]; then
  while IFS= read -r f; do RULESET+=("$f"); done \
    < <(find .cursor/rules -maxdepth 2 -type f \( -name '*.mdc' -o -name '*.md' \) 2>/dev/null | sed 's#^\./##' | sort)
fi
for f in CLAUDE.md .claude/CLAUDE.md AGENTS.md .cursorrules .windsurfrules; do
  [ -f "$f" ] && INSTRUCTIONS+=("$f")
done
HAS_RULESET=0; [ ${#RULESET[@]} -gt 0 ] && HAS_RULESET=1

# --- detection: command set ------------------------------------------------
# Makefile targets, bucketed; falls back to package.json / language defaults.
MK_TEST=(); MK_GATE=(); MK_FIX=(); MK_GEN=(); MK_DB=()
TEST_CMD=""; SINGLE_CMD=""
if [ -f Makefile ]; then
  while IFS= read -r t; do
    case "$t" in
      test|test-*)              MK_TEST+=("$t") ;;
      check|check-all|check-*)  MK_GATE+=("$t") ;;
      *fix|lint-fix|format)     MK_FIX+=("$t") ;;
      generate|gen|codegen)     MK_GEN+=("$t") ;;
      setup-db|migrate|seed|seed-*) MK_DB+=("$t") ;;
    esac
  done < <(grep -E '^[A-Za-z0-9_-]+:' Makefile | sed -E 's/:.*//' | sort -u)
fi
# Curate to umbrella targets so the skill isn't a wall of per-module variants.
pick_preferred() { # pick_preferred "<preferred space list>" "<all values...>"
  local pref="$1"; shift; local out="" p
  for p in $pref; do printf '%s\n' "$@" | grep -qx "$p" && out="$out $p"; done
  [ -n "$out" ] && echo "${out# }" || printf '%s ' "$@"
}
GATE_SHOW=$(pick_preferred "check check-all" "${MK_GATE[@]:-}")
FIX_SHOW=$(pick_preferred "lint-fix format" "${MK_FIX[@]:-}")
DB_SHOW=$(pick_preferred "setup-db migrate" "${MK_DB[@]:-}")
TEST_MODS=$({ printf '%s\n' "${MK_TEST[@]:-}" | grep -vx test || true; } | paste -sd',' - | sed 's/,/,/g')

if [ ${#MK_TEST[@]} -gt 0 ]; then
  if printf '%s\n' "${MK_TEST[@]}" | grep -qx test; then TEST_CMD="make test"; else TEST_CMD="make ${MK_TEST[0]}"; fi
elif [ -n "$PKG_JSON" ] && [ -n "$(pkg_script test)" ]; then
  TEST_CMD="${NPM_PFX}npm test"; SINGLE_CMD="${NPM_PFX}npm test -- <file>   # NEEDS CONFIRMATION"
elif [ -f go.mod ] || [ -f go.work ]; then
  TEST_CMD="go test ./..."; SINGLE_CMD="go test ./path -run TestName"
elif [ -f pom.xml ]; then TEST_CMD="mvn test"; SINGLE_CMD="mvn test -Dtest=ClassName#method"
elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then TEST_CMD="./gradlew test"; SINGLE_CMD="./gradlew test --tests ClassName.method"
elif [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then TEST_CMD="pytest"; SINGLE_CMD="pytest path::TestName"
else TEST_CMD="# TODO: no test command detected — fill this in"; fi
# Go single-test command when the runner is make-driven and none set above.
if [ -z "$SINGLE_CMD" ] && { [ -f go.mod ] || [ -f go.work ]; }; then SINGLE_CMD="go test ./path -run TestName"; fi

# Green gates (npm scripts / go) when there's no Makefile gate target.
GATES=()
if [ -n "$PKG_JSON" ]; then
  [ -n "$(pkg_script lint)" ] && GATES+=("${NPM_PFX}npm run lint")
  [ -n "$(pkg_script typecheck)" ] && GATES+=("${NPM_PFX}npm run typecheck")
  { [ -z "$(pkg_script typecheck)" ] && [ -f "$PKG_DIR/tsconfig.json" ]; } && GATES+=("${NPM_PFX}npx tsc --noEmit   # NEEDS CONFIRMATION")
  [ -n "$(pkg_script format)" ] && GATES+=("${NPM_PFX}npm run format")
fi
ls .golangci.* >/dev/null 2>&1 && GATES+=("golangci-lint run")
{ [ -f go.mod ] || [ -f go.work ]; } && GATES+=("go vet ./...")

# E2E framework
E2E_FW=""; E2E_CMD=""
if has_dep @playwright/test; then E2E_FW="Playwright"
elif has_dep cypress; then E2E_FW="Cypress"; fi
if [ -n "$E2E_FW" ]; then
  E2E_CMD="$(pkg_script test:e2e)"; [ -z "$E2E_CMD" ] && E2E_CMD="$(pkg_script e2e)"
  if printf '%s\n' "${MK_TEST[@]:-}" | grep -qx test-e2e; then E2E_CMD="make test-e2e"; fi
  if [ -z "$E2E_CMD" ]; then [ "$E2E_FW" = "Playwright" ] && E2E_CMD="npx playwright test" || E2E_CMD="npx cypress run"; fi
fi

# --- detection: service prerequisites (docker compose) ---------------------
COMPOSE_FILE=""
for c in docker-compose.yml docker-compose.yaml compose.yml compose.yaml docker/docker-compose.yml; do
  [ -f "$c" ] && { COMPOSE_FILE="$c"; break; }
done
SERVICES=""; DB_SERVICES=""
if [ -n "$COMPOSE_FILE" ]; then
  SERVICES=$(awk '
    /^services:/ {f=1; next}
    f && /^[^[:space:]]/ {f=0}
    f && /^[[:space:]][[:space:]][A-Za-z0-9_.-]+:/ {s=$1; sub(/:.*/,"",s); gsub(/[[:space:]]/,"",s); print s}
  ' "$COMPOSE_FILE" 2>/dev/null | sort -u | paste -sd' ' - || true)
  DB_SERVICES=$(printf '%s\n' $SERVICES | grep -iE 'postgres|redis|mysql|mariadb|mongo|elastic|opensearch' || true)
fi

# --- detection: module / architecture skeleton -----------------------------
# Union of: go.work modules, dirs holding a package.json, and db (if it has SQL).
GOWORK_MODS=""; [ -f go.work ] && GOWORK_MODS=$(grep -oE '\./[A-Za-z0-9_./-]+' go.work | sed 's#^\./##' || true)
PKG_DIRS=$({ git ls-files '*package.json' 2>/dev/null | grep -v node_modules | xargs -n1 dirname 2>/dev/null || true; } | grep -v '^\.$' || true)
DB_MOD=""; { [ -d db ] && [ -n "$(find db -maxdepth 2 -name '*.sql' 2>/dev/null | head -1)" ]; } && DB_MOD="db"
MODULES=$(printf '%s\n%s\n%s\n' "$GOWORK_MODS" "$PKG_DIRS" "$DB_MOD" | grep -v '^$' | sort -u | paste -sd' ' - || true)
if [ -z "$MODULES" ]; then
  MODULES=$(find . -maxdepth 1 -type d 2>/dev/null \
    | sed 's#^\./##' \
    | grep -vE '^(\.|\.git|\.github|\.idea|\.vscode|\.claude|node_modules|vendor|tmp|dist|build|logs)$' \
    | grep -v '^\.$' | sort | paste -sd' ' - || true)
fi

# --- detection: docs + README architecture headings ------------------------
# Prefer top-level docs + one README per subdir (skip deep per-topic file sprawl).
# (git pathspec '*' spans '/', so filter explicitly to one level.)
DOCS=$({ git ls-files 'docs/*' 2>/dev/null | grep -E '^docs/[^/]+\.md$'; \
         git ls-files 'docs/*' 2>/dev/null | grep -E '^docs/[^/]+/README\.md$'; } \
  | sort -u | head -20 | paste -sd' ' - || true)
README_SECTIONS=""
[ -f README.md ] && README_SECTIONS=$(grep -nE '^#{1,3} .*(Structure|Architecture|Technology Stack)\b' README.md 2>/dev/null | sed -E 's/^[0-9]+:#+ //' | paste -sd'|' - | sed 's/|/ | /g' || true)

# --- candidate test-infrastructure directories -----------------------------
HELPERS=$({ git ls-files 2>/dev/null \
  | grep -oE '(^|/)(testutils?|__mocks__|mocks|fixtures|factories|testdata|test/support|spec/support|test-utils|domain/test|repository/test)(/|$)' \
  || true; } | sed -E 's#^/##; s#/$##' | sort -u | head -10 | paste -sd',' - | sed 's/,/, /g')
[ -z "$HELPERS" ] && HELPERS="(none auto-detected — ask the human)"

# ===========================================================================
#  emit DIGEST.txt
# ===========================================================================
emit_list() { # prefix, space-separated items
  local pre="$1"; shift
  if [ -z "${1:-}" ]; then echo "${pre}(none)"; return; fi
  echo "${pre}$*"
}
{
  echo "afb-tdd setup digest — generated for: $REPO_ROOT"
  [ "$DEEP" -eq 1 ] && echo "DEEP_AUDIT=requested"
  echo
  echo "DETECTED (auto-answered, confirm only):"
  echo "  Languages/runners : ${LANGS[*]:-none}"
  echo "  Full test command : $TEST_CMD"
  [ -n "$SINGLE_CMD" ] && echo "  Single test       : $SINGLE_CMD"
  [ ${#MK_TEST[@]} -gt 0 ] && echo "  Make test targets : ${MK_TEST[*]}"
  [ ${#MK_GATE[@]} -gt 0 ] && echo "  Make gates        : ${MK_GATE[*]}"
  [ ${#MK_FIX[@]} -gt 0 ]  && echo "  Make fixups       : ${MK_FIX[*]}"
  [ ${#MK_GEN[@]} -gt 0 ]  && echo "  Make codegen      : ${MK_GEN[*]}"
  [ ${#MK_DB[@]} -gt 0 ]   && echo "  Make db/seed      : ${MK_DB[*]}"
  [ ${#GATES[@]} -gt 0 ]   && echo "  Other gates       : ${GATES[*]}"
  echo "  E2E framework     : ${E2E_FW:-none detected}"
  [ -n "$E2E_CMD" ] && echo "  E2E command       : $E2E_CMD"
  [ -n "$COMPOSE_FILE" ] && echo "  Compose services  : ${SERVICES:-none} (file: $COMPOSE_FILE)"
  [ -n "$DB_SERVICES" ] && echo "  Likely test prereqs: $(echo $DB_SERVICES | paste -sd' ' -)"
  echo "  Test naming       :"
  printf "      %b" "${TEST_NAMING:-      (none detected)\n}"
  echo "  Candidate helpers : $HELPERS"
  if [ "$HAS_RULESET" -eq 1 ]; then
    echo "  Conventions       : project ruleset found — global conventions dropped"
  else
    echo "  Conventions to link (global fallback):"
    if [ -n "$CONV_UNIQUE" ]; then while IFS= read -r c; do echo "      - $c"; done <<< "$CONV_UNIQUE"
    else echo "      (none — stack unrecognized)"; fi
  fi
  if [ ${#NOTES[@]} -gt 0 ]; then echo; echo "NOTES:"; for n in "${NOTES[@]}"; do echo "  - $n"; done; fi

  echo
  echo "PROJECT KNOWLEDGE FOUND (Setup Mode: read ONLY these — do not explore further):"
  if [ ${#RULESET[@]} -gt 0 ]; then echo "  Style rules    : ${RULESET[*]}"; else echo "  Style rules    : (none)"; fi
  if [ ${#INSTRUCTIONS[@]} -gt 0 ]; then echo "  Instructions   : ${INSTRUCTIONS[*]}"; else echo "  Instructions   : (none)"; fi
  emit_list "  Modules        : " "$MODULES"
  emit_list "  Docs           : " "$DOCS"
  [ -n "$README_SECTIONS" ] && echo "  README sections: $README_SECTIONS"

  if [ "$DEEP" -eq 1 ]; then
    echo
    echo "LOCATED FOR DEEP AUDIT (per-module test-file counts; fan out one agent per module):"
    if [ -n "$MODULES" ]; then
      for m in $MODULES; do echo "  $m : $(count_tests_under "$m") test files"; done
    else
      echo "  (repo root) : $(count_tests_under .) test files"
    fi
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
  echo "  Q9 External docs  : Any docs outside this repo I should know about —"
  echo "                      Notion, Google Docs, ADRs / decision records, design"
  echo "                      docs, runbooks? Paste links; note which are authoritative."
} > "$DIGEST_FILE"

# ===========================================================================
#  emit SKILL.md.draft
# ===========================================================================
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

<!-- STACK: Setup Mode fills this one-liner from README / CLAUDE.md -->
# TODO(stack): one-line summary — languages, frameworks, datastores, transport
EOF

  # ---- Path-scoped rules (project's own) OR global-conventions fallback ----
  if [ "$HAS_RULESET" -eq 1 ]; then
    echo
    echo "### Path-scoped rules"
    echo
    echo "The project's own conventions — the source of truth for style. They supersede the global afb-tdd references. Skim the relevant one before writing; don't restate it here."
    for f in "${RULESET[@]}"; do
      echo "- [$(basename "$f")]($R/$f) — <!-- TODO(rule): one-line summary from doc-read -->"
    done
    for f in "${INSTRUCTIONS[@]:-}"; do
      [ -n "$f" ] && echo "- [$(basename "$f")]($R/$f) — project instructions"
    done
  else
    echo
    echo "### Conventions"
    if [ -n "$CONV_UNIQUE" ]; then
      while IFS= read -r c; do echo "- See [$c]($GLOBAL_CONV/$c)"; done <<< "$CONV_UNIQUE"
    else
      echo "- # TODO: no stack-specific conventions detected"
    fi
    for f in "${INSTRUCTIONS[@]:-}"; do
      [ -n "$f" ] && echo "- Also see [$(basename "$f")]($R/$f) — project instructions"
    done
  fi

  # ---- Architecture skeleton ----
  echo
  echo "### Architecture — where a feature lives"
  echo
  if [ -f README.md ]; then
    echo "Background in [README.md]($R/README.md)${README_SECTIONS:+ (sections: $README_SECTIONS)}."
    echo
  fi
  if [ -n "$MODULES" ]; then
    for m in $MODULES; do echo "- \`$m/\` — <!-- TODO(arch): what lives here + key entry-point files -->"; done
  else
    echo "- # TODO(arch): describe the module layout"
  fi
  if [ -n "$DOCS" ]; then
    echo
    printf 'Topic docs:'
    for d in $DOCS; do
      lbl=$(basename "$d" .md); [ "$lbl" = "README" ] && lbl=$(basename "$(dirname "$d")")
      printf ' [%s](%s)' "$lbl" "$R/$d"
    done
    echo
  fi
  echo
  echo "External / linked docs: <!-- NEEDS CONFIRMATION (Q9): Notion / Google Docs / ADRs / decision records — paste links; may need an MCP connector or pasted content to read -->"

  # ---- Outside-in slice order scaffold ----
  echo
  echo "### Outside-in slice order for a user-facing feature"
  echo
  echo "Each step is its own red-green-refactor cycle:"
  echo "<!-- TODO(slice): Setup Mode refines these to name real dirs/files per the architecture above -->"
  n=1
  [ -n "$E2E_FW" ] && { echo "$n. $E2E_FW e2e spec (the user story)."; n=$((n+1)); }
  if printf '%s\n' "${CONV[@]:-}" | grep -q frontend.md; then echo "$n. Frontend component/page test."; n=$((n+1)); fi
  echo "$n. Backend/handler test."; n=$((n+1))
  echo "$n. Service / business-logic test."; n=$((n+1))
  echo "$n. Repository/persistence test; keep its in-memory fake in sync."; n=$((n+1))
  echo "$n. SQL/migration, then run codegen."

  # ---- Commands ----
  echo
  echo "### Commands"
  echo
  echo "Use the narrowest target for the layer under test; run the full gate before calling a cycle done."
  echo
  echo "- Full suite: \`$TEST_CMD\`"
  [ -n "$SINGLE_CMD" ] && echo "- Single test: \`$SINGLE_CMD\`"
  [ -n "$TEST_MODS" ] && echo "- Per module: \`make {$TEST_MODS}\`"
  [ -n "$GATE_SHOW" ] && echo "- Gate (run before green): $(for g in $GATE_SHOW; do printf '`make %s` ' "$g"; done)"
  if [ ${#GATES[@]} -gt 0 ] && [ ${#MK_GATE[@]} -eq 0 ]; then
    echo "- Before green, also run: $(for g in "${GATES[@]}"; do printf '`%s` ' "$g"; done)"
  fi
  [ -n "$E2E_CMD" ] && echo "- E2E ($E2E_FW): \`$E2E_CMD\`"
  [ -n "$FIX_SHOW" ] && echo "- Fixups: $(for g in $FIX_SHOW; do printf '`make %s` ' "$g"; done)"
  [ ${#MK_GEN[@]} -gt 0 ] && echo "- After SQL/schema changes: $(for g in "${MK_GEN[@]}"; do printf '`make %s` ' "$g"; done)"
  if [ -n "$DB_SERVICES" ]; then
    echo "- Integration tests need: \`docker compose up -d $(echo $DB_SERVICES | paste -sd' ' -)\`$([ -n "$DB_SHOW" ] && echo ", then $(for g in $DB_SHOW; do printf '`make %s` ' "$g"; done)")"
  elif [ -n "$DB_SHOW" ]; then
    echo "- DB setup: $(for g in $DB_SHOW; do printf '`make %s` ' "$g"; done)"
  fi

  # ---- Test infrastructure ----
  cat <<'EOF'

### Test infrastructure to reuse
EOF
  echo "<!-- NEEDS CONFIRMATION (Q6): keep only the canonical ones -->"
  echo "- Candidates detected: $HELPERS"

  # ---- Domain gotchas + Commits ----
  cat <<'EOF'

### Domain gotchas
<!-- NEEDS CONFIRMATION (Q7): DB setup/teardown, auth/tenancy, time control, external stubs, isolation -->
- # TODO

### Commits
- Do not attribute commits to Claude or list it as a co-author.
<!-- NEEDS CONFIRMATION (Q8): project-specific message format / hooks -->
EOF

  if [ "$DEEP" -eq 1 ]; then
    cat <<'EOF'

<!-- DEEP AUDIT: Setup Mode appends these from the per-module test audit -->
### Test helpers & gold-standard files
<!-- TODO(deep): canonical helper APIs + exemplar test files with file:line -->

### Known deviations
<!-- TODO(deep): shipped violations, grouped by area; not precedent -->

### Don't imitate this file
<!-- TODO(deep): the single worst reference, with the model to copy instead -->
EOF
  fi
} > "$DRAFT_FILE"

echo "Wrote:"
echo "  $DIGEST_FILE"
echo "  $DRAFT_FILE"
[ "$DEEP" -eq 1 ] && echo "  (deep audit requested — Setup Mode will fan out per-module test audits)"
echo
echo "Next: Setup Mode reads the located project files, fills the prose, confirms Q5–Q8, and promotes the draft to SKILL.md."

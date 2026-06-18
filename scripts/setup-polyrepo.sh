#!/usr/bin/env bash
#
# setup-polyrepo.sh — scaffold a TOP-LEVEL afb-tdd skill for a polyrepo: a
# container directory holding two or more independent git repositories as
# immediate children (each with its own .git and remote).
#
# Like setup-local.sh, all detection here is deterministic shell (zero LLM
# tokens). It does NOT recurse into the members — it only writes the top-level
# artifacts and a member list. Polyrepo Setup Mode confirms scope with the human
# and fans the existing per-repo setup into each member.
#
# Writes two files into <container>/.claude/skills/afb-tdd/:
#   - DIGEST.txt     starts with the POLYREPO=true marker; lists members + a
#                    shallow stack sniff, cross-repo CANDIDATES, the project
#                    knowledge worth reading, the fan-out list, and the
#                    polyrepo-level human questions (P1-P6)
#   - SKILL.md.draft a pre-filled cross-repo index (domain, member table,
#                    dependency graph, contract-testing guidance) for Setup Mode
#                    to fill and promote
#
# Usage: setup-polyrepo.sh [--force] [--simple] [--polyrepo]
#   --force        regenerate even if a top-level SKILL.md already exists
#   --simple       per-member deep audits are skipped downstream (passed through
#                  to each setup-local.sh run by Setup Mode). Aliases: --shallow
#   --polyrepo     accepted as a no-op (setup-local.sh passes it through)

set -euo pipefail

RM="../../.."   # path from .claude/skills/afb-tdd/SKILL.md back to the container root

FORCE=0
DEEP=1
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --deep)  DEEP=1 ;;
    --simple|--shallow) DEEP=0 ;;
    --polyrepo) : ;;                # no-op; setup-local.sh forwards it
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

CONTAINER="$(pwd)"
TARGET_DIR="$CONTAINER/.claude/skills/afb-tdd"
SKILL_FILE="$TARGET_DIR/SKILL.md"
DIGEST_FILE="$TARGET_DIR/DIGEST.txt"
DRAFT_FILE="$TARGET_DIR/SKILL.md.draft"

# --- helpers ---------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# Members = immediate child dirs that are their own git work-tree, minus any
# registered as submodules of a container repo (if one exists).
list_members() {
  local submodules=""
  [ -f .gitmodules ] && submodules=$(grep -oE 'path[[:space:]]*=[[:space:]]*.*' .gitmodules 2>/dev/null | sed -E 's/.*=[[:space:]]*//' || true)
  local d
  for d in */; do
    d="${d%/}"
    [ -e "$d/.git" ] || continue
    if [ -n "$submodules" ] && printf '%s\n' "$submodules" | grep -qx "$d"; then continue; fi
    echo "$d"
  done
}

MEMBERS=()
while IFS= read -r m; do [ -n "$m" ] && MEMBERS+=("$m"); done < <(list_members)

if [ "${#MEMBERS[@]}" -lt 2 ]; then
  echo "setup-polyrepo.sh: fewer than two member repos found under $CONTAINER." >&2
  echo "This does not look like a polyrepo. Run setup-local.sh instead." >&2
  exit 1
fi

# --- idempotency guard -----------------------------------------------------
if [ -f "$SKILL_FILE" ] && [ "$FORCE" -ne 1 ]; then
  echo "A top-level skill already exists at $SKILL_FILE"
  echo "Nothing to do. Re-run with --force to regenerate from scratch."
  exit 0
fi
mkdir -p "$TARGET_DIR"

# The member's primary package.json (root, else the first tracked one).
member_pkg() {
  local d="$1"
  [ -f "$d/package.json" ] && { echo "$d/package.json"; return; }
  { git -C "$d" ls-files '*package.json' 2>/dev/null | grep -v node_modules | head -1 | sed "s#^#$d/#" || true; }
}

# Is a (dev)dependency present in a given package.json?
pkg_dep() {
  local pj="$1" n="$2"
  [ -f "$pj" ] || return 1
  if have jq; then
    jq -e --arg n "$n" '((.dependencies // {}) + (.devDependencies // {})) | has($n)' "$pj" >/dev/null 2>&1
  else
    grep -qE "\"$n\"[[:space:]]*:" "$pj"
  fi
}

# One-line stack summary for a member.
sniff_stack() {
  local d="$1"; local parts=() pj rt fw
  { [ -f "$d/go.mod" ] || [ -f "$d/go.work" ]; } && parts+=("Go")
  pj=$(member_pkg "$d")
  if [ -n "$pj" ]; then
    rt=""; pkg_dep "$pj" vitest && rt="vitest"; [ -z "$rt" ] && { pkg_dep "$pj" jest && rt="jest"; }
    fw=""
    if pkg_dep "$pj" react-native || pkg_dep "$pj" expo; then fw="React Native"
    elif pkg_dep "$pj" react; then fw="React"
    elif pkg_dep "$pj" vue; then fw="Vue"
    elif pkg_dep "$pj" svelte; then fw="Svelte"; fi
    parts+=("JS/TS${fw:+ $fw}${rt:+ [$rt]}")
  fi
  { [ -f "$d/pom.xml" ] || [ -f "$d/build.gradle" ] || [ -f "$d/build.gradle.kts" ]; } && parts+=("Java")
  { [ -f "$d/pyproject.toml" ] || [ -f "$d/pytest.ini" ] || [ -f "$d/setup.cfg" ]; } && parts+=("Python")
  [ "${#parts[@]}" -eq 0 ] && parts+=("unknown")
  local out; out=$(printf '%s, ' "${parts[@]}"); echo "${out%, }"
}

# E2E framework declared in a member (if any).
sniff_e2e() {
  local pj; pj=$(member_pkg "$1"); [ -n "$pj" ] || { echo "none"; return; }
  pkg_dep "$pj" @playwright/test && { echo "Playwright"; return; }
  pkg_dep "$pj" cypress && { echo "Cypress"; return; }
  pkg_dep "$pj" detox && { echo "Detox"; return; }
  echo "none"
}

# Does a member declare a compose file?
sniff_compose() {
  local c
  for c in docker-compose.yml docker-compose.yaml compose.yml compose.yaml docker/docker-compose.yml; do
    [ -f "$1/$c" ] && { echo "$1/$c"; return; }
  done
  echo ""
}

# Tracked test-file count for a member (Go + TS/JS + Python).
count_tests() {
  { git -C "$1" ls-files 2>/dev/null \
    | grep -cE '(_test\.go|\.(test|spec)\.(t|j)sx?|(^|/)test_[^/]*\.py|_test\.py)$' || true; }
}

# Service names declared in a compose file.
compose_services() {
  awk '
    /^services:/ {f=1; next}
    f && /^[^[:space:]]/ {f=0}
    f && /^[[:space:]][[:space:]][A-Za-z0-9_.-]+:/ {s=$1; sub(/:.*/,"",s); gsub(/[[:space:]]/,"",s); print s}
  ' "$1" 2>/dev/null
}

# --- cross-repo candidate detection ----------------------------------------
ALL_SERVICES=""
for m in "${MEMBERS[@]}"; do
  cf=$(sniff_compose "$m")
  [ -n "$cf" ] && ALL_SERVICES="${ALL_SERVICES}$(compose_services "$cf")
"
done
SHARED_INFRA=$(printf '%s\n' "$ALL_SERVICES" | grep -iE 'postgres|redis|mysql|mariadb|mongo|elastic|opensearch|rabbit|kafka' \
  | sort | uniq -c | awk '$1>=2{print "  - "$2" (declared in "$1" repos)"}' || true)

# Sibling host/port references in tracked env + compose files.
HOST_REFS=""
for m in "${MEMBERS[@]}"; do
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    hits=$(grep -hoE '([A-Za-z_]+_(HOST|URL|URI|ENDPOINT|BASE_URL))=[^[:space:]"'"'"']*|localhost:[0-9]+|127\.0\.0\.1:[0-9]+' "$m/$f" 2>/dev/null || true)
    [ -n "$hits" ] && HOST_REFS="${HOST_REFS}$(printf '%s\n' "$hits" | sed "s#^#  $m: #")
"
  done < <(git -C "$m" ls-files 2>/dev/null | grep -iE '(^|/)(\.env(\..+)?|.*\.env|env\.example)$|docker-compose|compose\.ya?ml' | head -8)
done
HOST_REFS=$(printf '%s\n' "$HOST_REFS" | grep -v '^$' | sort -u | head -20 || true)

# Local path dependencies / cross-module wiring.
PATH_DEPS=""
for m in "${MEMBERS[@]}"; do
  pj=$(member_pkg "$m")
  if [ -n "$pj" ]; then
    d=$(grep -oE '"[^"]+"[[:space:]]*:[[:space:]]*"(file:|link:|workspace:)[^"]*"' "$pj" 2>/dev/null | head -5 || true)
    [ -n "$d" ] && PATH_DEPS="${PATH_DEPS}  $m/package.json: $(printf '%s ' $d)
"
  fi
  [ -f "$m/go.work" ] && PATH_DEPS="${PATH_DEPS}  $m/go.work present (multi-module Go)
"
done
PATH_DEPS=$(printf '%s' "$PATH_DEPS" | grep -v '^$' || true)

# Orchestrator signals: scripts that reference sibling dirs.
ORCH=""
for m in "${MEMBERS[@]}"; do
  pj=$(member_pkg "$m")
  [ -n "$pj" ] || continue
  if grep -qE '(--prefix=|concurrently|"workspaces"|run-p|run-s)' "$pj" 2>/dev/null; then
    ORCH="${ORCH} $m"
  fi
done
ORCH=$(echo "$ORCH" | sed 's/^ //')

# Existing contract / schema artifacts across members.
CONTRACTS=""
for m in "${MEMBERS[@]}"; do
  hits=$(git -C "$m" ls-files 2>/dev/null \
    | grep -iE '(openapi|swagger)[^/]*\.(ya?ml|json)$|\.pact$|(^|/)pacts?/|schema\.(graphql|json)$|\.proto$' \
    | grep -v node_modules | head -8 || true)
  [ -n "$hits" ] && CONTRACTS="${CONTRACTS}$(printf '%s\n' "$hits" | sed "s#^#  $m/#")
"
done
CONTRACTS=$(printf '%s' "$CONTRACTS" | grep -v '^$' | head -20 || true)

# --- project knowledge (read ONLY these in Setup Mode) ---------------------
TOP_DOCS=""
for f in README.md ARCHITECTURE.md docs/README.md docs/ARCHITECTURE.md; do
  [ -f "$f" ] && TOP_DOCS="$TOP_DOCS $f"
done
TOP_DOCS=$(echo "$TOP_DOCS" | sed 's/^ //')
MEMBER_READMES=""
for m in "${MEMBERS[@]}"; do
  [ -f "$m/README.md" ] && MEMBER_READMES="$MEMBER_READMES $m/README.md"
done
MEMBER_READMES=$(echo "$MEMBER_READMES" | sed 's/^ //')

# ===========================================================================
#  emit DIGEST.txt
# ===========================================================================
{
  echo "POLYREPO=true"
  echo "afb-tdd polyrepo setup digest — container: $CONTAINER"
  [ "$DEEP" -eq 1 ] && echo "DEEP_AUDIT=requested (passed to each member's setup-local.sh)"
  echo
  echo "MEMBERS (each an independent git repo; one local skill per member):"
  for m in "${MEMBERS[@]}"; do
    e2e=$(sniff_e2e "$m"); cf=$(sniff_compose "$m")
    echo "  $m"
    echo "      stack   : $(sniff_stack "$m")"
    echo "      e2e     : $e2e"
    echo "      compose : ${cf:-none}"
    echo "      tests   : $(count_tests "$m") test files"
  done

  echo
  echo "CROSS-REPO CANDIDATES (signals only — confirm with the human, do not assume):"
  echo "  Shared infra (compose services in >=2 repos):"
  if [ -n "$SHARED_INFRA" ]; then echo "$SHARED_INFRA"; else echo "    (none detected)"; fi
  echo "  Sibling host/port references (env + compose):"
  if [ -n "$HOST_REFS" ]; then echo "$HOST_REFS"; else echo "    (none detected)"; fi
  echo "  Local path / workspace dependencies:"
  if [ -n "$PATH_DEPS" ]; then echo "$PATH_DEPS"; else echo "    (none detected)"; fi
  echo "  Orchestrator repo(s) (scripts referencing siblings): ${ORCH:-none detected}"
  echo "  Contract / schema artifacts:"
  if [ -n "$CONTRACTS" ]; then echo "$CONTRACTS";
  else echo "    (NONE found — no consumer-driven contracts, OpenAPI specs, or shared schemas."; \
       echo "     The contract section should propose where to add them at the seams.)"; fi

  echo
  echo "PROJECT KNOWLEDGE FOUND (Setup Mode: read ONLY these for the domain — do not explore):"
  echo "  Top-level docs : ${TOP_DOCS:-(none)}"
  echo "  Member READMEs : ${MEMBER_READMES:-(none)}"

  echo
  echo "MEMBER LIST FOR FAN-OUT (run setup-local.sh inside each; it sees no child repos there):"
  for m in "${MEMBERS[@]}"; do echo "  $m"; done

  echo
  echo "ASK THE HUMAN (polyrepo-level — cannot be auto-detected reliably):"
  echo "  P1 Domain       : 2-3 sentences of domain truth for the whole system,"
  echo "                    or a link to the authoritative domain doc."
  echo "  P2 Dependencies : Confirm the cross-repo graph above — who calls whom,"
  echo "                    over what transport (HTTP/queue/shared DB)?"
  echo "  P3 Contracts    : Where are the seams, and how should they be tested"
  echo "                    (consumer-driven contract / shared OpenAPI / generated"
  echo "                    client / schema snapshot)? Which repo OWNS each contract?"
  echo "  P4 Lockstep     : Which changes must move across repos together (e.g. an"
  echo "                    API response-shape change + its web/mobile consumers)?"
  echo "  P5 External docs: Domain docs outside these repos — Notion, ADRs, design"
  echo "                    docs, runbooks? Paste links; note which are authoritative."
  echo "  P6 Scope        : Set up all members now? (default: yes — all listed above)"
} > "$DIGEST_FILE"

# ===========================================================================
#  emit SKILL.md.draft  (polyrepo cross-repo index)
# ===========================================================================
{
  cat <<'EOF'
---
name: afb-tdd
description: Interactive red-green-refactor TDD workflow (polyrepo cross-repo index).
user-invocable: true
allowed-tools: Bash
---

Follow the TDD workflow defined in [~/.claude/skills/afb-tdd/SKILL.md](~/.claude/skills/afb-tdd/SKILL.md).

## Polyrepo

This is a **polyrepo** — a container of independent git repositories. Each member repo has its own
afb-tdd skill with that repo's stack, commands, and conventions; **when you are working inside a
member, its local skill governs.** This top-level skill is the cross-repo index: the shared domain,
how the repos depend on each other, and how to test the seams between them.

## Domain
<!-- NEEDS CONFIRMATION (P1): 2-3 sentences of domain truth, or link the authoritative domain doc -->
# TODO(domain): what the whole system does, in the language of the business

## Member repos
EOF

  echo
  echo "| Repo | Stack | Role | Local skill |"
  echo "|------|-------|------|-------------|"
  for m in "${MEMBERS[@]}"; do
    echo "| \`$m/\` | $(sniff_stack "$m") | <!-- TODO(role): one line --> | [skill]($RM/$m/.claude/skills/afb-tdd/SKILL.md) |"
  done

  cat <<'EOF'

## Cross-repo dependencies (what's linked)
<!-- NEEDS CONFIRMATION (P2/P4): confirm the graph from the digest's CROSS-REPO CANDIDATES -->
EOF
  echo "<!-- TODO(deps): list each edge, e.g. \`web\` -> \`api\` over HTTP (API_HOST) -->"
  if [ -n "$SHARED_INFRA" ]; then
    echo "- Shared infra (confirm ownership):"
    echo "$SHARED_INFRA"
  fi
  if [ -n "$ORCH" ]; then echo "- Orchestrator repo(s): $ORCH"; fi
  echo "- Changes that must move in lockstep: <!-- TODO(P4): e.g. an \`api\` response-shape change requires updating its consumers in the same change set -->"

  cat <<'EOF'

## Contract testing between repos
<!-- NEEDS CONFIRMATION (P3): the seams, the chosen strategy, and the source of truth -->

The seams between these repos are where a single-repo suite is blind: a consumer's fake/MSW handler
of a provider can pass every local test while the provider's real shape has drifted. The
[Fake + Contract Testing](~/.claude/skills/afb-tdd/references/test-patterns.md) rule applies across
repo boundaries, not just within one:

- **Source of truth** for each contract: <!-- TODO(P3): OpenAPI spec / shared types package / Pact / .proto -->
- **Strategy** at each seam: <!-- TODO(P3): consumer-driven contract, shared schema, generated client, or schema snapshot -->
- A cross-repo feature **starts with the contract**: the provider side proves it serves the shape and
  the consumer side proves it consumes that shape, before the per-repo red-green cycles begin.
EOF
  if [ -n "$CONTRACTS" ]; then
    echo "- Existing contract artifacts detected:"
    echo "$CONTRACTS" | sed 's/^  /  - /'
  else
    echo "- **No contract artifacts detected.** Propose where to add them at the seams above and which"
    echo "  repo owns each — today the consumers' expectations are unverified against the providers."
  fi

  cat <<'EOF'

## Cross-repo outside-in order

A user-facing feature that spans repos runs outside-in across repo boundaries — each layer is its
own red-green-refactor cycle, in its own repo, using that repo's local skill:
<!-- TODO(slice): name the real repos, e.g. 1) E2E in `web`  2) `web` component/page  3) contract at the `web`<->`api` seam  4) `api` handler -> service -> repository -->

## Commits
- Do not attribute commits to Claude or list it as a co-author.
- Each member is its own git repo with its own remote — commit per repo. A cross-repo feature is
  several commits, one per affected repo.
EOF
} > "$DRAFT_FILE"

echo "Wrote (polyrepo):"
echo "  $DIGEST_FILE"
echo "  $DRAFT_FILE"
echo
echo "Members detected: ${MEMBERS[*]}"
echo "Next: Polyrepo Setup Mode fills the cross-repo index, fans setup into each member, batches the questions, and promotes the drafts."

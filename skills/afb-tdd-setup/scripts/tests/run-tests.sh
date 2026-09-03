#!/usr/bin/env bash
#
# Fixture tests for setup-local.sh. No network, no `claude`, no LLM: builds
# throwaway git repos in $TMPDIR, runs the detector, asserts on what it wrote.
#
# Run: setup-local.sh --self-test
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="$SCRIPT_DIR/setup-local.sh"
PASS=0; FAIL=0

pass() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '         %s\n' "$2"; }

# assert_in <label> <needle> <file>
assert_in() {
  if grep -qF -- "$2" "$3"; then pass "$1"; else fail "$1" "expected to find: $2"; fi
}
# assert_not_in <label> <needle> <file>
assert_not_in() {
  if grep -qF -- "$2" "$3"; then fail "$1" "should not contain: $2"; else pass "$1"; fi
}

# new_repo <name> -> echoes a fresh git repo path
new_repo() {
  local d; d="$(mktemp -d)/$1"; mkdir -p "$d"; cd "$d"
  git init -q .; git config user.email t@t; git config user.name t
  echo "$d"
}
commit_all() { git add -A >/dev/null 2>&1; git commit -qm fixture >/dev/null 2>&1; }

echo "setup-local.sh fixture tests"

# --- a bare Go repo -------------------------------------------------------
echo "go repo, no Makefile:"
D="$(new_repo go-plain)"; cd "$D"
printf 'module x\n\ngo 1.22\n' > go.mod
mkdir -p svc && printf 'package svc\n' > svc/svc.go && printf 'package svc\n' > svc/svc_test.go
commit_all
bash "$DETECT" --simple >/dev/null 2>&1
P="$D/.claude/afb-tdd/project.md"
if [ -f "$P" ]; then
  pass "writes project.md"
  assert_in  "detects the go test command"      'go test ./...'          "$P"
  assert_in  "names go.md to adapt"             '`go.md`'                "$P"
  # regression: pick_preferred emitted a bare space for empty arrays, so a repo
  # with no Makefile printed "Gate (run before green): " with nothing after it
  assert_not_in "no empty Gate line"            'Gate (run before green):' "$P"
  assert_not_in "no empty Fixups line"          '- Fixups:'                "$P"
  assert_not_in "no empty DB setup line"        '- DB setup:'              "$P"
  # the whole point of ADR 0001: nothing machine-specific in a committed file
  assert_not_in "no home-dir path"              '~/.claude'                "$P"
  assert_not_in "no absolute home path"         "$HOME"                    "$P"
  assert_not_in "emits no skill frontmatter"    'user-invocable'           "$P"
else
  fail "writes project.md" "not found at $P"
fi

M="$D/.claude/afb-tdd/manifest.json"
if [ -f "$M" ]; then
  pass "writes manifest.json"
  assert_in "records the stack"        '"Go"'              "$M"
  assert_in "records --simple"         '"deepAudit": false' "$M"
  assert_in "records audited commit"   '"auditedCommit"'    "$M"
else
  fail "writes manifest.json" "not found at $M"
fi

# --- a Makefile repo ------------------------------------------------------
echo "go repo with a Makefile:"
D="$(new_repo go-make)"; cd "$D"
printf 'module x\n\ngo 1.22\n' > go.mod
printf 'test:\n\tgo test ./...\ncheck:\n\tgolangci-lint run\nlint-fix:\n\tgofmt -w .\n' > Makefile
commit_all
bash "$DETECT" --simple >/dev/null 2>&1
P="$D/.claude/afb-tdd/project.md"
assert_in "prefers make test"          'Full suite: `make test`'          "$P"
assert_in "surfaces the make gate"     'Gate (run before green): `make check`' "$P"
assert_in "surfaces make fixups"       'Fixups: `make lint-fix`'          "$P"

# --- ownership: the guard and --refresh -----------------------------------
echo "ownership:"
D="$(new_repo guard)"; cd "$D"
printf 'module x\n\ngo 1.22\n' > go.mod; commit_all
bash "$DETECT" --simple >/dev/null 2>&1
echo 'HAND EDIT' >> .claude/afb-tdd/project.md
OUT="$(bash "$DETECT" --simple 2>&1)"
case "$OUT" in
  *"already exist"*) pass "second run refuses to clobber" ;;
  *) fail "second run refuses to clobber" "got: $OUT" ;;
esac
assert_in "hand edit survives a second run" 'HAND EDIT' "$D/.claude/afb-tdd/project.md"
bash "$DETECT" --simple --refresh >/dev/null 2>&1
if [ -f "$D/.claude/afb-tdd/project.md.new" ]; then pass "--refresh writes .new"; else fail "--refresh writes .new"; fi
assert_in "--refresh leaves the original alone" 'HAND EDIT' "$D/.claude/afb-tdd/project.md"

# --- polyrepo delegation --------------------------------------------------
echo "polyrepo:"
C="$(mktemp -d)/container"; mkdir -p "$C"; cd "$C"
for m in api web; do
  mkdir -p "$m" && cd "$m" && git init -q . && git config user.email t@t && git config user.name t
  printf 'module %s\n\ngo 1.22\n' "$m" > go.mod && commit_all && cd "$C"
done
bash "$DETECT" --simple >/dev/null 2>&1
if [ -f "$C/.claude/afb-tdd/DIGEST.txt" ] && head -1 "$C/.claude/afb-tdd/DIGEST.txt" | grep -q POLYREPO; then
  pass "delegates to setup-polyrepo.sh"
else
  fail "delegates to setup-polyrepo.sh"
fi

# --- not a repo -----------------------------------------------------------
echo "guards:"
D="$(mktemp -d)"; cd "$D"
if bash "$DETECT" --simple >/dev/null 2>&1; then fail "refuses outside a git repo"; else pass "refuses outside a git repo"; fi
if bash "$DETECT" --bogus >/dev/null 2>&1; then fail "rejects unknown flags"; else pass "rejects unknown flags"; fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

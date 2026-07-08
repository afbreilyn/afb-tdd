#!/usr/bin/env bash
#
# setup.sh — one-shot setup for the eval runner.
#
# Installs the small tools it safely can (jq, coreutils timeout, go-mutesting),
# verifies the ones it shouldn't manage for you (node, go, claude — usually
# owned by nvm/asdf/your installer), and warms the fixture dependency caches
# so the first eval run doesn't pay for npm ci.
#
# Usage: setup.sh [--check]
#   --check   verify only; install nothing (useful for CI)

set -euo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
have() { command -v "$1" >/dev/null 2>&1; }

CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

FAILED=0
ok()   { printf '  ✓ %s\n' "$1"; }
miss() { printf '  ✗ %s\n' "$1"; FAILED=1; }

brew_install() { # brew_install <formula> <provides>
  if [ "$CHECK_ONLY" = 1 ]; then miss "$2 (would install: brew install $1)"; return; fi
  if ! have brew; then miss "$2 — no Homebrew to install it with (https://brew.sh)"; return; fi
  echo "  … installing $1"
  brew install --quiet "$1"
  ok "$2 (installed)"
}

echo "==> required tools"
have git    && ok "git"    || miss "git — install Xcode command line tools or brew install git"
have jq     && ok "jq"     || brew_install jq "jq"
{ have timeout || have gtimeout; } && ok "timeout" || brew_install coreutils "timeout (coreutils)"
have claude && ok "claude ($(claude --version 2>/dev/null | head -1))" \
            || miss "claude — install Claude Code: https://claude.com/claude-code"
have node   && ok "node ($(node --version))" || miss "node — needed by the ts-vitest fixture (nvm/asdf/brew)"
have npm    && ok "npm"                      || miss "npm — comes with node"
have go     && ok "go ($(go version | awk '{print $3}'))" || miss "go — needed by the go-svc fixture (asdf/brew)"

echo "==> optional: mutation testing (--with-mutation)"
if have go; then
  PATH="$PATH:$(go env GOPATH)/bin"
  if have go-mutesting; then
    ok "go-mutesting"
  elif [ "$CHECK_ONLY" = 1 ]; then
    miss "go-mutesting (would install: go install github.com/avito-tech/go-mutesting/cmd/go-mutesting@latest)"
  else
    echo "  … installing go-mutesting"
    go install github.com/avito-tech/go-mutesting/cmd/go-mutesting@latest
    ok "go-mutesting (installed to $(go env GOPATH)/bin — graders find it there automatically)"
  fi
fi
echo "  ✓ stryker — ships in the ts-vitest fixture's devDependencies, no global install"

if [ "$CHECK_ONLY" = 0 ] && [ "$FAILED" = 0 ]; then
  echo "==> warming fixture dependency caches"
  (cd "$EVALS_DIR/fixtures/ts-vitest" && { [ -d node_modules ] || npm ci --no-audit --no-fund; }) && ok "ts-vitest node_modules"
  (cd "$EVALS_DIR/fixtures/go-svc" && go mod download) && ok "go-svc module cache"

  echo "==> sanity: both fixture suites green"
  (cd "$EVALS_DIR/fixtures/ts-vitest" && npx vitest run >/dev/null 2>&1) && ok "ts-vitest suite" || miss "ts-vitest suite failed — run 'npx vitest run' there to see why"
  (cd "$EVALS_DIR/fixtures/go-svc" && go test ./... >/dev/null 2>&1) && ok "go-svc suite" || miss "go-svc suite failed — run 'go test ./...' there to see why"
fi

echo
if [ "$FAILED" = 1 ]; then
  echo "setup incomplete — fix the ✗ items above, then re-run evals/setup.sh"
  exit 1
fi
echo "ready — try: evals/run.sh --task ts-extract-component -n 1"

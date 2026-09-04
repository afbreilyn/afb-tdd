#!/usr/bin/env bash
set -euo pipefail

# Dev-only. Symlinks every skill in this repo into ~/.claude/skills, so a
# `git pull` keeps the installed skills current. Re-run after adding or
# renaming a skill.
#
# Adapted from mattpocock/skills (MIT), which links into ~/.agents/skills too
# for Codex; these skills are Claude Code only, so this links one destination.
#
# This is not the supported installer. See .agents/install-block.md for that.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/.claude/skills"

# If DEST resolved into this repo we'd write the per-skill symlinks back into
# the repo's own skills/ tree. Bail rather than pollute the working copy.
if [ -L "$DEST" ]; then
  resolved="$(cd "$DEST" && pwd -P)"
  case "$resolved" in
    "$REPO"|"$REPO"/*)
      echo "error: $DEST is a symlink into this repo ($resolved)." >&2
      echo "Remove it and re-run; the script will treat it as a real dir." >&2
      exit 1
      ;;
  esac
fi

mkdir -p "$DEST"

linked=0
while IFS= read -r -d '' skill_md; do
  src="$(dirname "$skill_md")"
  name="$(basename "$src")"
  target="$DEST/$name"

  # A real directory here is someone's own skill, not ours. Refuse rather than
  # delete it; a stale symlink of ours is fine to replace.
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "skipped $name: $target exists and is not a symlink" >&2
    continue
  fi

  ln -sfn "$src" "$target"
  echo "linked $name -> ${src/#$HOME/\~}"
  linked=$((linked + 1))
done < <(find "$REPO/skills" -name SKILL.md -not -path '*/node_modules/*' -print0)

echo "$linked skill(s) linked into ${DEST/#$HOME/\~}"

# Sketch: one repo, two sibling skills

Proposal, not yet executed. Folds `afb-tdd` and `afb-tdd-setup` back into a single
repo laid out as a Claude Code plugin, following `mattpocock/skills`.

## Target tree

```
afb-tdd/
├── .claude-plugin/
│   ├── plugin.json           # skills[] names the shipped set explicitly
│   └── marketplace.json      # repo is its own single-plugin marketplace
├── .agents/                  # repo-internal agent docs (not human-facing)
│   ├── adr/                  # decisions, numbered
│   ├── install-block.md      # install commands, copied verbatim everywhere
│   └── RESTRUCTURE.md        # this file
├── skills/
│   ├── afb-tdd/              # the loop
│   │   ├── SKILL.md
│   │   └── references/       # conventions, sceptic, test-patterns, anti-patterns
│   └── afb-tdd-setup/        # the scaffolder
│       ├── SKILL.md
│       ├── references/polyrepo-setup-mode.md
│       └── scripts/setup-{local,polyrepo}.sh
├── evals/                    # repo-level: exercises the loop, not a skill itself
├── scripts/link-skills.sh    # dev: symlink each skill into ~/.claude/skills
├── CHANGELOG.md
├── README.md
└── LICENSE
```

## The one real decision: directory names

Skill directory names drive **both** install paths, and they pull in opposite
directions:

| Directory | Personal install (symlink) | Plugin install |
|---|---|---|
| `skills/afb-tdd/` | `/afb-tdd` | `/afb-tdd:afb-tdd` |
| `skills/tdd/` | `/tdd` (collides with the existing `tdd` skill) | `/afb-tdd:tdd` |

Plugin skills take the last command segment from frontmatter `name` and keep the
plugin prefix. Personal skills take it from the directory name and ignore `name`.

Sketched with `afb-tdd/` + `afb-tdd-setup/`, because the symlink route is what's in
use today and `/tdd` is already taken locally. The `afb-` prefix then duplicates
what the plugin namespace would do for free, so revisit if publishing as a plugin
becomes the primary route.

## plugin.json

```json
{
  "name": "afb-tdd",
  "version": "1.1.0",
  "skills": ["./skills/afb-tdd", "./skills/afb-tdd-setup"]
}
```

Explicit array, so anything added under `skills/` later (an `in-progress/` bucket,
the shelved retro skill) stays unshipped until listed. Run
`claude plugin validate . --strict` after touching it. Its `version` must track
any package version: Claude uses it to decide when installed users see an update.

## Dev workflow

`scripts/link-skills.sh` symlinks every directory containing a `SKILL.md` into
`~/.claude/skills/`, so `git pull` keeps installed skills current and there is no
more moving clones around by hand. Re-run after adding or renaming a skill.

## What this fixes

- **One version, one changelog, one clone.** The two repos have changed together
  on every commit so far; independent release cadence buys nothing.
- **Shared references stop being a problem.** In two repos, setup can only reach
  the loop's `references/conventions/` by absolute path. As siblings in one plugin,
  `${CLAUDE_PLUGIN_ROOT}` reaches across skills (documented for exactly this), and
  under the symlink route they are siblings on disk anyway.
- **Room to grow.** Buckets and a promotion rule let the retro skill live in the
  open without shipping.

## What it does NOT fix

The generated project skill still links the loop by absolute path. The sibling
layout narrows the problem (a plugin install can use `${CLAUDE_PLUGIN_ROOT}`) but
does not remove it, because that variable is not substituted for personal-install
skills, and the generated file is read as a *third* skill where neither variable
means what setup meant.

That only goes away with the **data-directory** design: setup writes
`.claude/afb-tdd/` (practices + project profile) and the loop reads it, with the
pointer written into the repo's own `CLAUDE.md` rather than a bespoke probe. The
two changes are independent and can land in either order.

## Migration order

1. `git mv` the loop into `skills/afb-tdd/` (history preserved).
2. Copy `afb-tdd-setup`'s tree into `skills/afb-tdd-setup/`. Its three commits do
   not graft cleanly, so squash them into one "adds the setup skill" commit and
   keep the old repo as the archive of that history.
3. Add `.claude-plugin/`, `scripts/link-skills.sh`, `.agents/install-block.md`.
4. Repoint `evals/run.sh`: `SKILL_DIR` is currently `dirname $EVALS_DIR`, which
   stops being the skill directory once the skill moves down two levels.
5. Re-link and verify both skills resolve, then rewrite the README install block.

Step 4 is the only one with a real chance of breaking silently.

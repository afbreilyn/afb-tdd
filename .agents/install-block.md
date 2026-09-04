# Install block

Copy these verbatim wherever install instructions appear (top-level `README.md`,
skill docs). One source so they cannot drift.

## As a plugin (recommended)

```bash
claude plugin marketplace add afbreilyn/afb-tdd
claude plugin install afb-tdd@afbreilyn
```

Skills are then `/afb-tdd:afb-tdd` and `/afb-tdd:afb-tdd-setup`: plugin skills keep
the plugin name as a prefix.

Run `claude plugin validate . --strict` after touching either manifest in
`.claude-plugin/`. `plugin.json`'s `version` is what Claude uses to decide when
installed users see an update, so bump it on release.

## As personal skills (development)

```bash
git clone git@github.com:afbreilyn/afb-tdd.git ~/workspace/afb-tdd
~/workspace/afb-tdd/scripts/link-skills.sh
```

Symlinks each skill into `~/.claude/skills/`, giving unprefixed `/afb-tdd` and
`/afb-tdd-setup`. A `git pull` keeps them current. Re-run after adding or renaming
a skill.

The clone must live outside `~/.claude/skills/`, or the symlink target and the
clone collide on the same path.

# afb-tdd

An interactive Claude Code skill to do red-green-refactor style TDD. The robit writes one failing test at a time with explicit pauses for the human to review.

Two skills:

| Skill | What it does |
|---|---|
| [afb-tdd](skills/afb-tdd/SKILL.md) | The red-green-refactor loop, with an adversarial sceptic on every cycle. The one you use daily. |
| [afb-tdd-setup](skills/afb-tdd-setup/SKILL.md) | Run once per repo. Detects your stack and commands, audits your test suite, and tunes the loop to the project. |

The loop's `SKILL.md` does a pretty good job of explaining the logic.

## How to do the thing:

### Install

As a plugin:

```bash
claude plugin marketplace add afbreilyn/afb-tdd
claude plugin install afb-tdd@afbreilyn
```

Skills are then `/afb-tdd:afb-tdd` and `/afb-tdd:afb-tdd-setup` — plugin skills keep the
plugin name as a prefix.

For development, clone and symlink instead, which gives unprefixed `/afb-tdd` and
`/afb-tdd-setup`:

```bash
git clone git@github.com:afbreilyn/afb-tdd.git ~/workspace/afb-tdd
~/workspace/afb-tdd/scripts/link-skills.sh
```

The clone has to live outside `~/.claude/skills/`, or the symlink target and the clone
collide on the same path.

### Project-local — tune the loop to your conventions and domain logic

```
/afb-tdd-setup
```

It detects your stack, commands, conventions, architecture and docs, audits your existing
test suite, and writes `.claude/afb-tdd/` — committed resources the loop reads:

```
.claude/afb-tdd/
├── manifest.json   what was generated, when, against which commit
├── project.md      facts: stack, commands, layout, slice order
└── practices.md    taste: how this team tests, with gold-standard exemplars
```

Commit them. They mean the same thing on every teammate's machine, and `/afb-tdd` prefers
them over its built-in conventions. It is a **soft** dependency: the loop works fine in a
repo that never ran setup.

These files are yours once written. A second run refuses to clobber them; `--refresh`
regenerates alongside for you to diff and merge.

In a polyrepo, every member repo gets its own `.claude/afb-tdd/`; there is no top-level
index, since a container usually isn't a git repo and nothing there could be committed.
See [ADR 0001](.agents/adr/0001-checked-in-resources-instead-of-a-generated-skill.md).

`/afb-tdd` in that project then reads those files before its first cycle and prefers them
over its built-ins. Same command, same skill, tuned to the repo.

<details>
<summary>Writing them by hand</summary>

The files are plain markdown with no required schema; setup just saves you the detection
and the audit. A minimal `.claude/afb-tdd/project.md`:

```markdown
# afb-tdd: project profile

## Commands
- Full suite: `make test`   # or whatever you use

## Architecture: where a feature lives
- `svc/` — what lives here, and its entry points

## Domain gotchas
- DB setup/teardown, auth/tenancy, time control, external stubs, isolation
```

And `practices.md` for house style: how this team writes tests, gold-standard files to
copy with `file:line`, known deviations that are not precedent.

Keep every path repo-relative. These files are committed and read on other people's
machines, so a `~/.claude/...` path in one is a bug.
</details>

## The Sceptic (the gremlins!)

Every cycle gets adversarially reviewed twice — after Red (is the test tautological, weak, mock-testing, mispredicted?) and after Green (over-implementation, untested code, cheating vs declared Fake It, tests bent to fit) — by a read-only subagent applying the closed rubric in [sceptic.md](skills/afb-tdd/references/sceptic.md). Findings appear in the report at the existing pause points, each answered with `FIXED` / `REBUTTED` / `YOUR CALL`. On by default; `/afb-tdd --no-sceptic` turns it off for the session — skips are always visible in the report, never silent.

## Evals

`evals/` measures the quality of what the skill actually produces — fixture repos, headless runs, deterministic gates (suite green, revert check, red-before-code from the transcript, convention greps), plus optional mutation testing and an LLM judge that scores against the same sceptic rubric. See [evals/README.md](evals/README.md) for how to run them and track quality over time.

## Feedback

Like any TDD-er, I would love feedback! If you have examples / tweaks / conventions / patterns / anti-patterns / pirate jokes to share, please fork the repo and open up a PR!

## License
[![License: CC BY 4.0](https://img.shields.io/badge/License-CC%20BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)

## Acknowledgments

- [pdca-framework](https://github.com/kenjudy/pdca-framework) ([Ken Judy](https://github.com/kenjudy)) — a huge source of inspiration and guidance, even for the format of this acknowledgment section
- [obra/superpowers](https://github.com/obra/superpowers/tree/main/skills/test-driven-development) (Jesse Vincent) — anti-patterns reference, which i have adapted and extended for this skill
- Kent Beck && James Grenning — for many of the founding principles of TDD, examples, and techniques that i too often take for granted

obra/superpowers is MIT licensed and kenjudy/pdca-framework is CC BY 4.0; content adapted from them is used with attribution as required. Beck and Grenning are intellectual influences; no copyrighted text is reproduced from their published works.
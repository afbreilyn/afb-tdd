# afb-tdd

An interactive Claude Code skill to do red-green-refactor style TDD. The robit writes one failing test at a time with explicit pauses for the human to review.

The `SKILL.md` itself does a pretty good job of explaining the logic.

## How to do the thing:

### Global — use as-is

This skill lives in `~/.claude/skills/afb-tdd/` and is available in every Claude Code session. Invoke it with `/afb-tdd` from any project.

### Local — inherit and extend with your own testing conventions and domain logic

For a project with its own test conventions, create a local skill that delegates to this one and adds project-specific overrides. The fastest way is to let the setup script do it for you:

```
/afb-tdd setup
```

This runs a detector that inspects your repo — languages, test runner, the full command set (per-module test targets, gates, codegen, DB setup), E2E framework, service prerequisites (Postgres/Redis from your compose file), module layout, your docs, and your **own** rule files (`.claude/rules/*.md`, `CLAUDE.md`, …). It then reads the small set of project files it found to fill in the architecture and slice order, asks you a few things it can't detect (domain gotchas, which test helpers are canonical, whether (and how) to start at the E2E layer, commit conventions....), and writes a (local) `.claude/skills/afb-tdd/SKILL.md` pre-filled from your codebase.

If your repo has its own rule files, the generated skill links **those** as the source of truth (and drops the global conventions). Otherwise it links **only the conventions matching your stack** (a Go repo links `go.md` and nothing else). Either way it links rather than inlines, so every `/afb-tdd` cycle afterwards only loads a small, relevant context instead of re-discovering your repo.

The setup fans out a robit audit of your existing test suite and adds gold-standard exemplar files (with `file:line`), a "known deviations" list, and a "don't imitate this file" callout. It costs more up front tokens, but it's the default cause it's worth it to not propogate anti-patterns. In a hurry? `/afb-tdd setup --simple` skips the audit and just scaffolds. 

`/afb-tdd` in that project then runs the local version, which inherits the core workflow. Re-run with `--force` to regenerate (just like any claude skill). 

<details>
<summary>What it generates (and the manual fallback)</summary>

If you'd rather write it by hand, create `.claude/skills/afb-tdd/SKILL.md` with this shape and add only what differs:

```markdown
---
name: afb-tdd
description: Interactive red-green-refactor TDD workflow.
user-invocable: true
allowed-tools: Bash
---

Follow the TDD workflow defined in [~/.claude/skills/afb-tdd/SKILL.md](~/.claude/skills/afb-tdd/SKILL.md).

## Project-specific

### Commands
- Full suite: `make test`   # or whatever you use

### Conventions
- Link ONLY the conventions for your stack, e.g.
  [go.md](~/.claude/skills/afb-tdd/references/conventions/go.md)

### Test infrastructure to reuse
- Builders / fakes / fixtures and where they live

### Domain gotchas
- DB setup/teardown, auth/tenancy, time control, external stubs, isolation
```
</details>

## Feedback

Like any TDD-er, I would love feedback! If you have examples / tweaks / conventions / patterns / anti-patterns / pirate jokes to share, please fork the repo and open up a PR!

## License
[![License: CC BY 4.0](https://img.shields.io/badge/License-CC%20BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)

## Acknowledgments

- [pdca-framework](https://github.com/kenjudy/pdca-framework) ([Ken Judy](https://github.com/kenjudy)) — a huge source of inspiration and guidance, even for the format of this acknowledgment section
- [obra/superpowers](https://github.com/obra/superpowers/tree/main/skills/test-driven-development) (Jesse Vincent) — anti-patterns reference, which i have adapted and extended for this skill
- Kent Beck && James Grenning — for many of the founding principles of TDD, examples, and techniques that i too often take for granted

obra/superpowers is MIT licensed and kenjudy/pdca-framework is CC BY 4.0; content adapted from them is used with attribution as required. Beck and Grenning are intellectual influences; no copyrighted text is reproduced from their published works.
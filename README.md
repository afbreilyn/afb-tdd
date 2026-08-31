# afb-tdd

An interactive Claude Code skill to do red-green-refactor style TDD. The robit writes one failing test at a time with explicit pauses for the human to review.

The `SKILL.md` itself does a pretty good job of explaining the logic.

## How to do the thing:

### Install

The loop and the scaffolder are two skills in two repos. This repo is the loop.

```bash
git clone git@github.com:afbreilyn/afb-tdd.git ~/.claude/skills/afb-tdd
```

Invoke it with `/afb-tdd` from any project.

### Project-local — inherit and extend with your own conventions and domain logic

Scaffolding a project skill lives in the separate
[afb-tdd-setup](https://github.com/afbreilyn/afb-tdd-setup) skill:

```bash
git clone git@github.com:afbreilyn/afb-tdd-setup.git ~/.claude/skills/afb-tdd-setup
```

```
/afb-tdd-setup
```

It detects your stack, commands, conventions, architecture and docs, audits your existing
test suite, and writes a `.claude/skills/afb-tdd/SKILL.md` pre-filled from your codebase —
including polyrepos, where every member repo gets its own skill plus a cross-repo index.
See that repo's README for the detail.

`/afb-tdd` in that project then runs the local version, which inherits this workflow and
adds the project specifics on top. The local skill shadows this one, so `/afb-tdd` is
still the only command you type.

<details>
<summary>The manual fallback</summary>

If you'd rather write it by hand, create `.claude/skills/afb-tdd/SKILL.md` with this shape
and add only what differs:

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

The local skill is named `afb-tdd` too, so it shadows this one — which is why it links the
workflow by path rather than invoking it by name. A name reference would resolve to itself.
</details>

## The Sceptic (the gremlins!)

Every cycle gets adversarially reviewed twice — after Red (is the test tautological, weak, mock-testing, mispredicted?) and after Green (over-implementation, untested code, cheating vs declared Fake It, tests bent to fit) — by a read-only subagent applying the closed rubric in [references/sceptic.md](references/sceptic.md). Findings appear in the report at the existing pause points, each answered with `FIXED` / `REBUTTED` / `YOUR CALL`. On by default; `/afb-tdd --no-sceptic` turns it off for the session — skips are always visible in the report, never silent.

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
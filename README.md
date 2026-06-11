# afb-tdd

An interactive Claude Code skill to do red-green-refactor style TDD. The robit writes one failing test at a time with explicit pauses for the human to review.

The `SKILL.md` itself does a pretty good job of explaining the logic.

## How to do the thing:

### Global — use as-is

This skill lives in `~/.claude/skills/afb-tdd/` and is available in every Claude Code session. Invoke it with `/afb-tdd` from any project.

### Local — inherit and extend with your own testing conventions and domain logic

For a project with its own test conventions, create a local skill that delegates to this one and adds project-specific overrides, using the below text

```markdown
---
name: afb-tdd
description: Interactive red-green-refactor TDD workflow.
user-invocable: true
allowed-tools: Bash
---

Follow the TDD workflow defined in [~/.claude/skills/afb-tdd/SKILL.md](~/.claude/skills/afb-tdd/SKILL.md).

## Project-specific

- Run the full test suite with `make test` (or whatever command you use).
- See [conventions.md](references/conventions.md) for test helpers, fakes, builders, and integration test setup.
```

The local skill would then extend the global one — `/afb-tdd` in that project runs the local version, which inherits the core workflow. Add only what differs.

## Feedback

Like any TDD-er, I would love feedback! If you have examples / tweaks / conventions / patterns / anti-patterns / pirate jokes to share, please fork the repo and open up a PR!

## License
[![License: CC BY 4.0](https://img.shields.io/badge/License-CC%20BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)

## Acknowledgments

- [pdca-framework](https://github.com/kenjudy/pdca-framework) ([Ken Judy](https://github.com/kenjudy)) — a huge source of inspiration and guidance, even for the format of this acknowledgment section
- [obra/superpowers](https://github.com/obra/superpowers/tree/main/skills/test-driven-development) (Jesse Vincent) — anti-patterns reference, which i have adapted and extended for this skill
- Kent Beck && James Grenning — for many of the founding principles of TDD, examples, and techniques that i too often take for granted

obra/superpowers is MIT licensed and kenjudy/pdca-framework is CC BY 4.0; content adapted from them is used with attribution as required. Beck and Grenning are intellectual influences; no copyrighted text is reproduced from their published works.
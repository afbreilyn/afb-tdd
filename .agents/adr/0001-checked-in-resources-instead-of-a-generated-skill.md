# Checked-in resources instead of a generated project skill

`afb-tdd-setup` stops generating a project-local skill. It writes plain resources
into the repo, committed, and the single global `afb-tdd` loop reads them.

Settled by grilling 2026-09-01, implemented 2026-09-02.

## Why

The generated `.claude/skills/afb-tdd/SKILL.md` was named `afb-tdd`, which meant it
shadowed the global loop, which meant it had to reach back for the loop by absolute
path. Every recurring defect traced to that one link: the `~/.claude/...` hardcode,
the `find ~/.claude -path '*afb-tdd*'` fallbacks in two files, the name collision
that made machine-independent references impossible, and the `afb-tdd-core` + alias
detour that was built and reverted.

Make the artifact data instead of a skill and the whole class disappears. Nothing
generated points at another skill's install location, so `--core-skill-path` and its
predecessor `--core-skill-name` both become unnecessary.

## The shape

```
<repo>/.claude/afb-tdd/
├── manifest.json     # what was generated, when, from what
├── project.md        # detector output: facts about this repo
└── practices.md      # audit output: how this team tests
```

**`project.md`** is whatever the deterministic detector found: stack, test commands
(full, single, gates, e2e, DB prereqs), module map, outside-in slice order, links to
the repo's own rule files. Changes when the build changes, so rarely.

**`practices.md`** is whatever the model audit produced: conventions adapted to this
repo's real helpers and examples, gold-standard exemplars with `file:line`, known
deviations, don't-imitate-this-file. Churns as the codebase moves.

The rule: detector output goes in `project.md`, audit output goes in `practices.md`.
That is also why they are two files and not one, they refresh on different clocks.

## Decisions

**Discovery.** The loop's own `SKILL.md` carries the instruction: if
`.claude/afb-tdd/` exists, read it and prefer it. That is a standing instruction in
the skill already running, not a probe that can be skipped. `manifest.json` exists so
the loop can tell "setup never ran" from "setup ran and found nothing". Setup *offers*
to add a pointer block to the repo's `CLAUDE.md`, it does not do it unprompted: that
would tax every session in the repo, including the ones not doing TDD.

**Soft dependency.** The loop works without any of this and falls back to its built-in
`references/conventions/*.md`. It has to: a fresh clone, the eval fixtures, and anyone
trying the skill before running setup all hit that path. The built-in conventions are
also the corpus the audit adapts *from*, so they stay either way. "Uses the repo's
instead of its own" is therefore not literal; it is prefer-then-fall-back, and both
paths get spelled out in the loop.

**Ownership.** These files belong to the team once written. Setup writes only when
absent. `--refresh` writes `practices.md.new` beside the original and shows a diff for
a human to merge. Never a silent overwrite. The entire payoff of checking these in is
that a team corrects something and the correction sticks; a regeneration that clobbers
edits destroys that in one command. Section-level merge markers are where this lands
if it succeeds, but the markers cannot be designed well before seeing real edits.

**Staleness.** `manifest.json` records `generatedAt`, `auditedCommit` (the SHA the
audit ran against), `stack`, `deepAudit`, and a version stamp of the built-in
conventions adapted from. The loop does not police any of it on invocation, that is
noise on something that runs many times per session. It surfaces staleness lazily:
only when about to cite an exemplar whose file no longer exists. The manifest informs
a human `--refresh` decision.

**The sceptic.** `references/sceptic.md:20` currently hands the subagent the path to
the project-local `SKILL.md`, which stops existing. It gets `practices.md` instead:
house style and known deviations are what the rubric needs, commands and architecture
are not. The rubric must say plainly that absence is normal and not a finding, or the
sceptic starts flagging every repo that has not run setup.

**Polyrepo: the central index is dropped.** Each member repo is its own git repo and
gets its own committed `.claude/afb-tdd/`. The container usually is not a git repo, so
a top-level cross-repo index has nowhere to be checked in, which is the premise of this
whole change. Instead each member's `project.md` gains a short Cross-repo section
naming only its own edges: who it calls, who calls it, what governs that seam. The
shared domain doc gets linked, not owned.

This deletes the top-level index built in `a467dfc`, it does not relocate it. The
tradeoff accepted: every member works standalone, which is how people actually work,
at the cost of losing the dependency graph and contract-testing guidance as one
artifact.

**Legacy generated skills.** They keep working: a legacy `.claude/skills/afb-tdd/`
shadows the global loop and links it by a path that still resolves. Note the loop can
never detect one, because it never runs when one is present, so conversion logic could
only live in setup. A search of this machine found none, and the feature is about two
months old, so no converter gets built. The README says to delete the old directory and
re-run setup.

**Detection stays, emission is rewritten.** The detector half of `setup-local.sh` is
deterministic, zero-token and correct, which is a real advantage over a fully
prompt-driven setup and worth keeping. The emission half, roughly 150 lines of heredocs
producing `SKILL.md.draft` with frontmatter and `TODO(...)` markers, is now the wrong
shape and is replaced by writing `project.md` directly plus a digest for the model to
write `practices.md`.

## Implementation

In `afb-tdd`:

1. `SKILL.md` gains the prefer-then-fall-back instruction for `.claude/afb-tdd/`.
2. `references/sceptic.md`: line 20 points at `practices.md`; add the "absence is
   normal" note to the rubric.

In `afb-tdd-setup`:

3. `scripts/setup-local.sh`: keep detection, replace draft emission with `project.md`
   + `manifest.json`. Drop `--core-skill-path` and `GLOBAL_CONV`, nothing generated
   references the loop's location any more. Add `--refresh`.
4. Fix the empty `Gate (run before green):` / `Fixups:` / `DB setup:` lines emitted
   when a repo has no Makefile, and add fixture-based `--self-test`.
5. `SKILL.md`: steps 3 and 6 rewritten around the new output. Step 4's audit now
   produces `practices.md` as its primary artifact rather than an appendix.
6. `scripts/setup-polyrepo.sh` and `references/polyrepo-setup-mode.md` shrink: no
   central index, no per-member skill promotion, just per-member resources.
7. READMEs in both repos.

Evals:

8. Fixture `--self-test` for the detector.
9. One new eval task: an existing fixture plus a `.claude/afb-tdd/practices.md`
   mandating something distinctive and greppable (table-driven tests), with a static
   grader checking compliance. This is the only thing that would catch the soft
   dependency silently not working, which is the most likely way this design fails.

## Relationship to the repo restructure

Independent of [RESTRUCTURE.md](../RESTRUCTURE.md), the one-repo sibling-skills
layout. Either can land first. The restructure narrows the path-coupling problem; this
removes it.

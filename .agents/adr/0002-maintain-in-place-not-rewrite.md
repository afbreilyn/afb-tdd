# Maintain in place, not rewrite; keep the afb- names

Settled by grilling 2026-10-20, against Anthropic's `skill-creator` guidance.

## Why

The question was whether to start over with `skill-creator` and port this repo as
reference, or bring the existing skills up to its conventions. Nothing was broken:
the clean baseline passes every gate. What prompted it was prose style and a sense
of accumulated patches. Neither is a reason to rewrite: the first is a prose pass,
the second an audit. A rewrite would throw away the one thing a fresh start can't
give back, a baseline that says whether a change helped.

## Decisions

**Maintain in place.** Mechanical fixes, then one prose pass that rewrites bare
imperatives into rules carrying their reasons. Cuts are flagged for a human, not made
by the pass.

**The protocol is the skill.** Called shots, `--auto`, cycle commits and the sceptic
are what the harness grades (`grade-shots.sh`, `grade-process.sh`, the candidate
preamble). Any future candidate, including a from-scratch rewrite, has to keep them to
be compared at all. One without them is a different skill and is judged as one.

**Evals run once, at the end.** This is upkeep, not research. No re-baseline up front,
no per-section ablation. The final run is compared against the existing baseline and
the model change is accepted as a confound; it gets investigated only if a gate drops.

**Descriptions are hand-written, not optimised.** `skill-creator`'s optimiser is a few
hundred `claude -p` calls. A description that states what is distinctive and what is
out of scope gets most of the way there. Revisit if it misfires in real use.

**The loop stays model-invocable.** "Fix this test-first" in a repo that ran setup
should land here, which is what the description is for.

**No rename.** `skills/tdd/` would read better as a plugin (`/afb-tdd:tdd`) but makes
"use the afb-tdd skill" match only the plugin prefix, gives a bare `/tdd` under the
symlink route, and changes the eval preamble before the run that measures this work.
`afb-tdd:afb-tdd` is cosmetic; nobody types it. This supersedes the "revisit" note in
[RESTRUCTURE.md](../RESTRUCTURE.md).

**The plugin route gets a manual smoke test** before the final eval run. Every eval so
far ran through the symlinks, and the plugin install had never been exercised; the
first look found setup naming the loop's conventions by bare filename with no way to
locate them from a plugin cache.

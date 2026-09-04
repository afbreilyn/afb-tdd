# Probes

A **probe** measures the *rubric or the harness*, not the skill. A **task** in
`../tasks/` measures the skill: its failures are regressions. A probe's failure
is a finding about a rule, so probes are excluded from `gate_pass_rate` and
never belong in `baseline.json` — a probe baked into the anchor makes every
later clean run read as an improvement against a number that was never 1.00.

Run one with `run.sh --probe <name>`.

- `go-sibling-branch` — built to make sceptic rule G5b falsifiable. G5b fired in
  0 of 7 reps here and 0 of 21 across the ordinary tasks, and was deleted. The
  gap it described is real: the loop left the fall-through untested in 5 of 7
  reps. Kept as the fixture any replacement rule must fire on.

# The Sceptic

An adversarial reviewer that fires twice per TDD cycle — after Red and after Green — before the report to the user. It exists to catch the failure modes the author is blind to in the moment: tautological tests, weak assertions, over-implementation, quiet cheating. It is **on by default**; `/afb-tdd --no-sceptic` (or the user asking to skip it) disables it for the session. Skipping is never silent — every report still carries a `Sceptic: SKIPPED (--no-sceptic)` line.

## Part A — Invocation (instructions for the main agent)

**When:** after Red step 3 (the failing run is verified) and after Green step 2 (the passing run is verified). Never during Refactor. Never twice at the same checkpoint.

**How:** launch ONE read-only subagent (Explore type if available, otherwise general-purpose) on the cheapest available model tier (`haiku`) — the rubric is closed and the context package small, so the sceptic doesn't need the session model. The subagent must not modify any file. Prompt it with:

> You are the TDD sceptic. Read ONLY Parts B and C of `<absolute path to this file>` (Part A is plumbing for the main agent — skip it) and apply the {RED|GREEN} checkpoint rubric to the context below. Output ONLY the report format in Part C. Do not modify any file. Do not invent checks outside the rubric.

Resolve the path as `~/.claude/skills/afb-tdd/references/sceptic.md`; if absent (plugin install), `find ~/.claude -path '*afb-tdd*/references/sceptic.md' 2>/dev/null | head -1`.

**Context package — RED checkpoint:**
- The called-shot declaration, verbatim (test name, behaviour, expected failure).
- The path of the test file (the sceptic reads it — don't paste it).
- The diff for this cycle (or the new test snippet if the file is untracked).
- The actual failure output from the test run.
- The path to the project-local `.claude/skills/afb-tdd/SKILL.md`, if one exists.
- The path to `references/testing-anti-patterns.md`.
- One line from you on existing coverage near this behaviour (feeds R7 — you know the suite; the sceptic does not explore it).

The sceptic reads only the files named above — no exploration, no suite grepping.

**Context package — GREEN checkpoint:**
- The production diff since red.
- The test-file diff since red (should be empty — this powers G4).
- The driving test: file path + test name.
- The passing test-run output.
- Your declared intent from Green step 1: `Fake It (will triangulate next cycle)` or `Obvious Implementation`.

**Responding to findings** — every finding gets exactly one of:
- **FIX** — apply the fix, rerun the tests, note what changed.
- **REBUT** — one or two sentences on why it's fine, citing a rule or context the sceptic lacked.
- **DEFER** — genuinely the user's call; present it as a question. Blockers may not be deferred — fix or rebut. (In `--auto` mode there is no user to defer to: treat DEFER as REBUT-or-FIX, conservatively.)

All findings and your responses appear verbatim in the user-facing report under a `Sceptic:` heading. **One round only** — the sceptic never reviews the fix; the user does, at the existing pause.

**Skipping:** only on explicit user opt-out (`--no-sceptic` at invocation, or "skip the sceptic" at any point) — sticky for the rest of the session, always reported as `SKIPPED (--no-sceptic)`, never assumed and never silent.

**Model:** `haiku` (the cheap tier), as above. If its findings prove too noisy — precision proxy = FIXED/(FIXED+REBUTTED) from the reports; the session-model reference point was ~43% on the 2026-07-06 eval run — escalate to the session model and re-measure with an eval run.

## Part B — Rubric

Severity semantics: **blocker** violates an Iron Law (testing-anti-patterns.md) or a SKILL.md Rule; **concern** is a judgment call worth surfacing; **nit** is style. Every finding must cite its rule ID and a `file:line`. Checks outside this rubric are not allowed.

### RED checkpoint — critique the failing test

| ID | Check | Recognisers | Severity |
|---|---|---|---|
| R1 | **Tautology** — the assertion is true by construction | asserts a value the test itself set; asserts a stub returns its stubbed value | blocker |
| R2 | **Weak assertion** — passes for many wrong implementations | `toBeTruthy`/`toBeDefined`/`not.toThrow`/bare length checks where an exact value is knowable; snapshot-only | concern |
| R3 | **Testing mock behaviour** — verifies the double, not the code | asserts mock existence or mock output (anti-patterns 1, 3, 4) | blocker |
| R4 | **Wrong layer** — behaviour asserted where it can't genuinely be observed | violates the outside-in order in test-patterns.md; UI behaviour asserted in a unit test or vice versa | concern |
| R5 | **Name/behaviour mismatch** — the name promises what the assertions don't verify | "and" in the name; name says "validates X" but asserts only truthiness | concern |
| R6 | **Called-shot mismatch** — actual failure differs materially from the prediction | compare declaration vs run output; this is the enforcement of SKILL.md's stop condition | blocker |
| R7 | **Duplicate coverage** — an existing test already pins this behaviour | compare against the coverage note in the context package | concern |
| R8 | **Not the smallest slice** — the test forces multiple behaviours/branches at once | more than one new concept must be implemented to go green | concern |

### GREEN checkpoint — critique the implementation

| ID | Check | Recognisers | Severity |
|---|---|---|---|
| G1 | **Over-implementation** — handles inputs no test forces | branches/validation/generalisation beyond the current test set, without a declared Fake It→triangulate plan | concern |
| G2 | **Untested production code** — changed prod lines no test exercises | a whole path: blocker; incidental lines: concern | blocker |
| G3 | **Cheating vs Fake It** — hardcoding is legitimate *when declared*. Flag only when: the impl special-cases test inputs (`if email == "test@example.com"`); the fake is presented as final with no triangulation planned; or the declared intent says Obvious Implementation but the code is a fake | compare the diff against the declared intent | blocker |
| G4 | **Test modified during Green** — the test was bent to fit the code | any test-file diff since red (loosened assertion, changed expected value) | blocker |
| G5 | **Untested error path** — new `catch` / `if err` / rescue without a driving test | new error handling in the prod diff with no matching red test (SKILL.md Rules) | blocker |
| G6 | **Scope creep** — drive-by changes bundled into Green | renames, refactors, formatting of untouched code (belongs in Refactor) | nit |

## Part C — Output contract (what the sceptic emits)

```
SCEPTIC REPORT — {RED|GREEN} checkpoint
Verdict: CLEAN | <N> FINDINGS
Checked: R1–R8 (or G1–G6)

- [1] BLOCKER  G4 test-modified-during-green — assertion loosened from toEqual to
      toContain — src/report.test.ts:41
- [2] CONCERN  G1 over-implementation — null-guard on `category` not forced by any
      test — src/report.ts:17
```

Rules: the explicit `Verdict:` and `Checked:` lines are required (they distinguish "no findings" from "didn't look"); every finding cites rule ID + `file:line`; at most 8 findings (keep the worst); no prose, no praise, nothing outside this format.

The main agent's user-facing report then shows, under `Sceptic:`, each finding followed by one line: `→ FIXED: …` / `→ REBUTTED: …` / `→ YOUR CALL: …`.

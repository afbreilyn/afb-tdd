# Driving Tests (`/afb-tdd drive`) — Green → Red → Green

Use when production code **already exists** and is **untested**. Red-green doesn't apply: the code is there, so a new test is green on arrival and proves nothing — it may pass via a cache, a stub, a tautological assertion, or a path it never reaches.

You **manufacture the red**: write the test green, sabotage the production line that should make it fail, confirm it goes red for the predicted reason, restore. That earns the red-green guarantee — *seen to fail for the right reason* — that legacy code denies you.

**Mutate production, not the assertion.** Flipping the expected value only proves the test runs. Commenting out the production line proves the test is causally coupled to the behaviour — the only thing that makes it a net you can refactor under.

Pick the layer per [test-patterns.md](test-patterns.md) (outside-in, deepest user-facing first). One driven test per cycle, smallest slice. Never batch.

## Green
1. Write one test for the behaviour you believe the code has. Run it. It must pass.
   - Doesn't pass → STOP. Either you misread the behaviour or found a bug. Report; decide with the user: pin reality (characterize), or fix it (switch to red-green).
   - Don't know the expected value? Assert a wrong value, run, read the actual from the failure, paste it back to green. That gives the value; Red gives the teeth.

## Red
1. Declare the called shot:
   - **Test name** / **Behaviour under test**
   - **Sabotage point:** file:line — the smallest change that should flip *this* test
   - **Predicted failure:** exact assertion message
   - **Predicted blast radius:** other tests you expect to also red, or "none"
2. Apply the mutation, tagged temporary:
   ```
   // DRIVE:SABOTAGE (temp) — confirm <test> has teeth
   // total += lineItem.price;
   ```
3. Run broadly (affected module minimum; full suite when feasible — collateral failures are the point).
4. Evaluate vs. the called shot:
   - **This test reds for the predicted reason** → it has teeth. Go to Restore.
   - **Stays green** → it doesn't exercise that path. This is the *untestable* terminal state (below), not a pass.
   - **Reds for a different reason** → STOP, reconsider. Mismatch is a stop condition.
   - **Won't compile** → mutation too blunt; use a value-substitution mutation instead.
5. **Record blast radius.** Every *other* test that reds depends on the sabotaged line. Unpredicted reds = newly found couplings — log them (Findings). This causal coupling map is often the main prize: it surfaces "didn't know anything relied on this" before you refactor.

## Restore → Green
1. Revert the mutation by hand (keep the diff legible).
2. Re-run. All green, including blast-radius tests.
3. Gate: no `DRIVE:SABOTAGE` marker may remain — grep; if any survive, not done. No commented-out production logic ships.
4. Report the driven test, the forced-then-restored failure, and couplings found. Wait for the user before the next slice.

Test is now trusted. Refactor under it, or drive the next slice.

## Terminal states (both are progress)
1. **Trusted test** — sabotage forced the predicted red, then restored.
2. **Untestable finding** — sabotage couldn't force a red. Leave production **intact**, annotate durably, and **delete** the hollow test (it proved nothing). Log it — these are the riskiest spots to change.
   ```
   // DRIVE:UNTESTABLE — commenting `total += lineItem.price` failed no test;
   // suspected dead path / also computed in CartSummary. Uncovered — do not trust.
   ```

## Smallest-mutation rule
Target the specific behaviour the test pins — one statement/branch/return. Bar: *make exactly this test red, ideally only this test.* If killing a whole function reds 40 tests, you've proven nothing about specificity. Shrink it.

## Mutation taxonomy (most legible first)
- **Comment out a statement/call** — default.
- **Return constant/null/empty** — when commenting breaks compilation.
- **Negate a conditional / flip a boolean** — kill one branch.
- **Short-circuit** (`if (false)` / early return) — skip a block without deleting it.

## Markers
- `// DRIVE:SABOTAGE (temp) — <why>` — transient. Gone by cycle end (grep gate).
- `// DRIVE:UNTESTABLE — <reason>` — durable. Stays on code that resisted.

## Findings
Track (a) untestable spots and (b) couplings found via blast radius; report each cycle. If the user wants it persisted, write `DRIVING-FINDINGS.md` at repo root — empirical causal coupling, complementary to git-history coupling, feeds later modularization.

## Rules
- Code already exists → a fresh green is untrustworthy. Never trust a driven test you haven't watched red.
- Sabotage production, never the assertion.
- Smallest mutation; one driven test per cycle.
- Always restore. No `DRIVE:SABOTAGE` survives a finished cycle.
- Green-that-won't-red = finding, not pass: annotate `DRIVE:UNTESTABLE`, delete the hollow test.
- Predicted-vs-actual mismatch = stop condition.
- Characterizing pins current behaviour, bugs included — correct. Pin reality first; change it deliberately later under the net.

Net in place → hand to red-green-refactor for new behaviour, or to `afb-modularize` to carve boundaries. See [testing-anti-patterns.md](testing-anti-patterns.md), esp. Anti-Pattern 8.

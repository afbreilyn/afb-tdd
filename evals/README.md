# afb-tdd evals

measures the quality of tests the skill produces, so SKILL.md changes can be compared against a baseline instead of vibes.

we can't tell if the robit chose the *right* behaviours to test — that's the human's job (for now!). so we only grade what's mechanically checkable: every gate is a deterministic script. (a robit judge exists for version-to-version comparison — add `--with-judge`.)

| quality claim | implemented by | mechanical check | nature |
|---|---|---|---|
| "the code works, cleanly" | `grade-suite.sh` | run the fixture's `test_cmd`; exit 0 and no warning/deprecation lines in output | deterministic **gate** |
| "the tests aren't decorative" | `grade-revert.sh` | revert all prod-file changes, keep the tests, rerun — suite must **fail** | deterministic **gate** |
| "test-first actually happened" | `grade-process.sh` | jq the transcript into event order: test edit → *failing* run → only then the first prod edit; count red→green cycles | deterministic **gate** |
| "resisted the task's temptation, in the house style" | `grade-static.sh` + the task's `extra_checks` | greps over added diff lines — e.g. ≥2 map entries in the new test, zero `ByTestId` in the parent, zero `time.Now()` in prod | deterministic **gate** |
| "the tests catch small bugs, not just deletion" | `grade-mutation.sh` (`--with-mutation`) | inject hundreds of one-token mutants into changed prod files; score = killed ÷ (killed + survived) | deterministic **metric** (score, not pass/fail) |
| "the called shots were correct — the robit understands the code it hasn't written yet" | `grade-shots.sh` | pair each `Expected failure:` declaration with the next test run (deterministic); with `--with-judge`, an LLM classifies each pair match/mismatch/hedge; accuracy = match ÷ (match + mismatch) | pairing is deterministic; the verdict is **model opinion** — metric, never a gate |
| "the tests are well-written — assertions, naming, minimality" | `judge.sh` (`--with-judge`) | LLM scores the diff 1–5 per rubric dimension (sceptic rubric, Part B); median of 3 calls | **model opinion** — relative comparison only, never a gate |

## tldr
- 6 tasks (3 golang, 3 typescript) in `evals/tasks/` — each one tries to suss out instances of one specific mistake (code-before-tests, single-entry map tests, testid selectors, etc, as captured in the `extra_checks`)
- a headless robit does each task using the afb-tdd skill; the (deterministic) graders score the (nondeterministic) output
- the outputs are stored in `results/`: `history.jsonl` (the trend, one line per run), `runs/<run-id>/summary.json` (the details), and `baseline.json` (what `compare.sh` measures against). scores are committed; raw diffs/transcripts stay in `runs/<run-id>/artifacts/`, gitignored

## how a run works (for each task)
- makes a copy of a fixture (a tiny working project, `evals/fixtures/`) into a tmp git repo
- give the robit one prompt (`tasks/<name>/prompt.md`, with config — timeout, turn cap, extra checks — from its `task.json`), then invokes the skill in `--auto` mode (the normal loop, sceptic included, minus the human pauses)
- when it exits, keep three artifacts: the diff, the transcript, and the git log; the graders score from those; the tmp repo is deleted

```
                         evals/run.sh  [--task X] [-n N] [--candidate C]
                                        │
        ┌───────────────────────────────┼───────────────────────────────┐
        │ inputs                        │                               │
        │  candidates/C/preamble.md     │  tasks/T/prompt.md            │
        │  (how to invoke; agents/)     │  tasks/T/task.json (config)   │
        └───────────────────────────────┼───────────────────────────────┘
                                        ▼
                          ┌─────────────────────────────┐
                          │  SANDBOX (tmp git repo)     │
                          │  copy of fixtures/F         │
                          │  commit + tag: baseline ────┼── sanity: suite green?
                          └──────────────┬──────────────┘
                                         ▼
                          ┌─────────────────────────────┐
                          │  claude -p  (headless)      │
                          │  prompt = preamble + task   │
                          │  skill --auto loop:         │
                          │   red → sceptic → green →   │
                          │   sceptic → refactor →      │
                          │   commit tdd(cycle N)  ⟳    │
                          └──────────────┬──────────────┘
                                         ▼  exit → tag: final
              ┌──────────────────────────┼──────────────────────────┐
              │ artifacts                │                          │
              │   diff.patch        transcript.jsonl          git-log.txt
              │   (WHAT changed)    (HOW, in order)          (cycle commits)
              └──────────┬───────────────┬──────────────────────┬───┘
                         ▼               ▼                      ▼
        ┌────────────────────────────────────────────────────────────┐
        │ GRADERS                                                    │
        │  gates:   grade-suite  grade-revert  grade-process         │
        │           grade-static (+ task extra_checks)               │
        │  opt-in:  grade-mutation (--with-mutation)                 │
        │           judge (--with-judge, reads sceptic.md rubric)    │
        └───────────────────────────┬────────────────────────────────┘
                                    ▼           (sandbox deleted 🔥)
                          grades.json (per rep)
                                    │   × N reps × each task
                                    ▼
        ┌────────────────────────────────────────────────────────────┐
        │ RESULTS (results/)                                         │
        │  runs/<run-id>/summary.json   ← full drill-down            │
        │  history.jsonl                ← +1 line per run (trend)    │
        └──────────────┬──────────────────────────────┬──────────────┘
                       ▼                              ▼
              compare.sh ↔ baseline.json         report.sh
              (this change vs the anchor)        (trend table over time)
```

## setup
```bash
evals/setup.sh            # installs jq/coreutils/go-mutesting, verifies node/go/claude, warms fixture deps
evals/setup.sh --check    # verify only, install nothing
```

## commands
```bash
evals/run.sh --task ts-extract-component -n 1        # one cheap run of one task
evals/run.sh -n 3 --label my-change                  # full run: 6 tasks × 3 reps (~$30, hours)
evals/run.sh -n 3 --with-judge --with-mutation ...   # add the optional graders
evals/run.sh --candidate <name> ...                  # evaluate something other than afb-tdd (see candidates/)
evals/compare.sh results/runs/<run-id>/summary.json  # this run vs baseline.json
evals/report.sh                                      # trend table over all recorded runs
```

## workflow after changing the skill
1. iterate cheap: the quick set — `run.sh --task go-transparent-fake,ts-feature-errors -n 1 --label <change>` (~$5) — or all tasks at `-n 1` (~$11)
2. `evals/compare.sh results/runs/<run-id>/summary.json` — gates that dropped are the red flags; single-rep wiggles are noise, pass-*rates* are signal
3. happy? confirm with the full `-n 3` run (~$30), then promote: `cp` its `summary.json` over `results/baseline.json` and commit it together with `history.jsonl` and the skill change itself

## key places to look
- `run.sh` — the orchestration (sandbox, prompt, artifacts, rollup)
- `graders/*.sh` — each check, commented
- `tasks/<name>/task.json` + `prompt.md` — what each task asks and its per-task rules
- `candidates/` — who gets evaluated (`--candidate`, default afb-tdd: a preamble + optional agent files)
- `../references/sceptic.md` Part B — the rubric the judge scores against

## caveats
- n=3 is a coarse instrument. trust deltas > 0.5 on judge scores and gate-rate drops; ignore the rest.
- judge scores are relative (skill version A vs B) since the judge shares the generator's biases.
- shot "hedges" ("expected failure: passes immediately") are excluded from accuracy but reported — a rising hedge count means the shot-calling discipline is eroding even if accuracy looks fine. drill into `runs/<run-id>/*/artifacts/shot-pairs.json`.
- fixtures exemplify the convention docs listed in their `eval-fixture.json`; re-review fixtures when those docs change.

# afb-tdd evals

Measures the quality of tests the skill produces, so SKILL.md changes can be compared against a baseline instead of vibes.

## Quickstart

```bash
evals/run.sh --task ts-extract-component -n 1        # one cheap smoke run
evals/run.sh -n 3 --label my-change                  # full run: 6 tasks × 3 reps (~$20–55, hours)
evals/run.sh -n 3 --with-judge --with-mutation ...   # add the optional graders
evals/compare.sh results/runs/<run-id>/summary.json  # candidate vs baseline.json
evals/report.sh                                      # trend table over all recorded runs
```

Prerequisites: `jq`, `git`, `claude`, coreutils `timeout` (`brew install coreutils`). `--with-mutation` also needs Stryker (in the TS fixture's devDeps) and [`go-mutesting`](https://github.com/avito-tech/go-mutesting) (`go install github.com/avito-tech/go-mutesting/cmd/go-mutesting@latest`).

## What a run does

For each task in `evals/tasks/` × N reps: copy the fixture to a throwaway git repo, run `claude -p` headless with the task prompt (the skill in `--auto` mode), then grade:

| grader | gate | question |
|---|---|---|
| grade-suite | `suite_green` | is the final suite green with pristine output? |
| grade-revert | `revert_check` | revert the prod diff, keep the tests — does the suite fail? (tests that don't fail constrain nothing) |
| grade-process | `process_red_first` | per the transcript, did a failing test run happen before the first prod edit? |
| grade-static | `static_checks` | convention greps + per-task rule checks (e.g. no `getByTestId` in the extraction parent) |
| grade-mutation | opt-in metric | mutation score on the changed prod files |
| judge | opt-in metric | LLM scores the diff 1–5 against the sceptic rubric (`references/sceptic.md`) |

## Where results live

- `history.jsonl` — one line per run, append-only, **committed**. The long-term trend record; every line carries the skill's git sha.
- `runs/<run-id>/summary.json` — full per-rep drill-down, **committed**. Raw diffs/transcripts stay in `runs/<run-id>/artifacts/` (gitignored).
- `baseline.json` — copy of the currently accepted anchor run; the default reference for `compare.sh`.

## Iterating cheaply

While tweaking the skill, use the quick set: `run.sh --task go-transparent-fake -n 1` (the sceptic-heaviest task) plus `run.sh --task ts-feature-errors -n 1` — ~$5 for a directional read. Reserve the full all-tasks `-n 3` run (~$30) for promoting a baseline.

## Workflow after changing the skill

1. `evals/run.sh -n 3 --label <change-name>`
2. `evals/compare.sh results/runs/<run-id>/summary.json` — gates that dropped are the red flags; single-rep wiggles are noise, pass-*rates* are signal.
3. If accepted: `cp results/runs/<run-id>/summary.json results/baseline.json` and commit it together with `history.jsonl`, the run's `summary.json`, and the skill change itself.

## Caveats

- n=3 is a coarse instrument. Trust deltas > 0.5 on judge scores and gate-rate drops; ignore the rest.
- Judge scores are relative (skill version A vs B), not absolute truth — the judge shares the generator's biases.
- Fixtures exemplify the convention docs listed in their `eval-fixture.json`; re-review fixtures when those docs change.
- CI option (not wired up): run one cheap task, deterministic gates only, on PRs touching SKILL.md.

#!/usr/bin/env bash
#
# run.sh — eval orchestrator for the afb-tdd skill.
#
# For each (task, rep): copies the task's fixture into a throwaway git repo,
# runs `claude -p` headless with the task prompt (the skill in --auto mode),
# captures the diff + transcript, and grades the result. Scores land in
# results/runs/<run-id>/ and one line is appended to results/history.jsonl.
#
# Usage: run.sh [--task <name>] [--probe <name>] [-n <reps>] [--with-mutation]
#               [--with-judge]
#               [--label <name>] [--model <model>] [--keep-workdirs]
#
# See README.md (this directory) for the full workflow.

set -euo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$EVALS_DIR")"   # evals/ sits at the repo root, not inside a skill
GRADERS="$EVALS_DIR/graders"
source "$GRADERS/lib.sh"

TASK_FILTER=""; PROBE_FILTER=""; REPS=1; WITH_MUTATION=0; WITH_JUDGE=0; LABEL=""; MODEL=""; KEEP=0; CANDIDATE="afb-tdd"
while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK_FILTER="$2"; shift 2 ;;
    --probe) PROBE_FILTER="$2"; shift 2 ;;
    --candidate) CANDIDATE="$2"; shift 2 ;;
    -n) REPS="$2"; shift 2 ;;
    --with-mutation) WITH_MUTATION=1; shift ;;
    --with-judge) WITH_JUDGE=1; shift ;;
    --label) LABEL="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --keep-workdirs) KEEP=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

for tool in jq claude git; do
  have "$tool" || { echo "missing required tool: $tool — run evals/setup.sh" >&2; exit 1; }
done
CAND_DIR="$EVALS_DIR/candidates/$CANDIDATE"
[ -f "$CAND_DIR/preamble.md" ] || { echo "unknown candidate '$CANDIDATE' (no $CAND_DIR/preamble.md)" >&2; exit 1; }
TIMEOUT_BIN=timeout; have timeout || TIMEOUT_BIN=gtimeout
have "$TIMEOUT_BIN" || { echo "missing timeout (brew install coreutils)" >&2; exit 1; }

# Two ways the environment can contaminate a run, both silent:
#   .claude/skills/afb-tdd  a legacy project skill, which SHADOWS the global one
#   .claude/afb-tdd         resources, which the loop READS and prefers
# The second arrived with ADR 0001 and is the one a task seeds deliberately
# inside its own workdir; anywhere ABOVE the workdir it is contamination.
PROBE="$(mktemp -d)"; DIR="$PROBE"
while [ "$DIR" != "/" ]; do
  for contaminant in .claude/skills/afb-tdd .claude/afb-tdd; do
    if [ -e "$DIR/$contaminant" ]; then
      echo "refusing to run: $DIR/$contaminant would change what the skill sees" >&2
      exit 1
    fi
  done
  DIR="$(dirname "$DIR")"
done
rmdir "$PROBE"

RUN_ID="$(date +%Y%m%dT%H%M%S)${LABEL:+-$LABEL}"
RUN_DIR="$EVALS_DIR/results/runs/$RUN_ID"
mkdir -p "$RUN_DIR"

SKILL_SHA="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
SKILL_DIRTY=false
[ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ] && SKILL_DIRTY=true
CLAUDE_VERSION="$(claude --version 2>/dev/null | head -1 || echo unknown)"

# --- select tasks -----------------------------------------------------------
# A probe measures the rubric or the harness, not the skill, so it lives in
# probes/ and is never part of a scored sweep. See probes/README.md.
SUITE_DIR="$EVALS_DIR/tasks"
if [ -n "$PROBE_FILTER" ]; then
  SUITE_DIR="$EVALS_DIR/probes"; TASK_FILTER="$PROBE_FILTER"
fi
TASKS=()
for dir in "$SUITE_DIR"/*/; do
  name="$(basename "$dir")"
  [ -f "$dir/task.json" ] || continue
  if [ -n "$TASK_FILTER" ] && ! printf ',%s,' "$TASK_FILTER" | grep -qF ",$name,"; then continue; fi
  TASKS+=("$name")
done
[ ${#TASKS[@]} -gt 0 ] || { echo "no tasks matched '${TASK_FILTER}'" >&2; exit 1; }

# --- warm fixture dep caches once ------------------------------------------
for task in "${TASKS[@]}"; do
  fixture_name="$(jq -r .fixture "$EVALS_DIR/tasks/$task/task.json")"
  fixture_dir="$EVALS_DIR/fixtures/$fixture_name"
  marker="$(jq -r '.deps_marker // empty' "$fixture_dir/eval-fixture.json")"
  if [ -n "$marker" ] && [ -e "$fixture_dir/$marker" ]; then continue; fi
  echo "==> warming deps for $fixture_name"
  (cd "$fixture_dir" && eval "$(jq -r .deps_setup eval-fixture.json)")
done

TOTAL_COST=0

run_one() { # run_one <task> <rep>
  local task="$1" rep="$2"
  local task_dir="$SUITE_DIR/$task"
  local fixture_name fixture_dir fixture_json timeout_s max_turns
  fixture_name="$(jq -r .fixture "$task_dir/task.json")"
  fixture_dir="$EVALS_DIR/fixtures/$fixture_name"
  fixture_json="$fixture_dir/eval-fixture.json"
  timeout_s="$(jq -r '.timeout_s // 1200' "$task_dir/task.json")"
  max_turns="$(jq -r '.max_turns // 150' "$task_dir/task.json")"

  local rep_dir="$RUN_DIR/$task/rep-$rep" art
  art="$rep_dir/artifacts"
  mkdir -p "$art"

  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/afb-eval.XXXXXX")"
  tar -C "$fixture_dir" --exclude node_modules -cf - . | tar -C "$work" -xf -
  [ -d "$fixture_dir/node_modules" ] && ln -s "$fixture_dir/node_modules" "$work/node_modules"

  # A task may overlay files onto its fixture via a "seed" dir (task.json's
  # `seed` key, relative to the task dir). Used to pre-seed .claude/afb-tdd/
  # so a task can assert the loop actually reads the repo's resources.
  local seed_rel seed_dir
  seed_rel="$(jq -r '.seed // empty' "$task_dir/task.json" 2>/dev/null)"
  if [ -n "$seed_rel" ]; then
    seed_dir="$task_dir/$seed_rel"
    if [ -d "$seed_dir" ]; then
      tar -C "$seed_dir" -cf - . | tar -C "$work" -xf -
    else
      echo "task $task declares seed '$seed_rel' but $seed_dir does not exist" >&2
      return 1
    fi
  fi
  if [ -d "$CAND_DIR/agents" ]; then
    mkdir -p "$work/.claude/agents"
    cp "$CAND_DIR/agents/"*.md "$work/.claude/agents/"
  fi

  git -C "$work" init -q
  git -C "$work" -c user.name=eval -c user.email=eval@local add -A
  git -C "$work" -c user.name=eval -c user.email=eval@local commit -qm baseline
  git -C "$work" tag baseline

  local sanity
  sanity="$(mktemp)"
  if ! run_suite "$work" "$fixture_json" "$sanity"; then
    echo "  !! fixture suite not green before the run — aborting rep" >&2
    cp "$sanity" "$art/sanity-failure.txt"; rm -f "$sanity"
    jq -n '{completed: false, reason: "fixture_not_green"}' > "$rep_dir/grades.json"
    return
  fi
  rm -f "$sanity"

  echo "==> $task rep $rep (timeout ${timeout_s}s, max ${max_turns} turns)"
  local start rc=0
  start=$(date +%s)
  (cd "$work" && "$TIMEOUT_BIN" "$timeout_s" \
      claude -p "$(cat "$CAND_DIR/preamble.md")"$'\n\n'"$(cat "$task_dir/prompt.md")" \
        --dangerously-skip-permissions --output-format json \
        --max-turns "$max_turns" ${MODEL:+--model "$MODEL"} \
    ) > "$art/claude-output.json" 2> "$art/claude-stderr.txt" || rc=$?

  git -C "$work" -c user.name=eval -c user.email=eval@local add -A
  git -C "$work" -c user.name=eval -c user.email=eval@local commit -qm final --allow-empty
  git -C "$work" tag final

  # claude-output.json is EMPTY when the timeout killed claude — default all fields.
  local session_id cost turns duration model_used
  session_id="$(jq -r '.session_id // empty' "$art/claude-output.json" 2>/dev/null || true)"
  cost="$(jq -r '.total_cost_usd // 0' "$art/claude-output.json" 2>/dev/null || true)"
  turns="$(jq -r '.num_turns // 0' "$art/claude-output.json" 2>/dev/null || true)"
  # The RESOLVED model (aliases like "sonnet" and the managed-settings default
  # are opaque): take the model that incurred the most cost.
  model_used="$(jq -r '.modelUsage // {} | to_entries | max_by(.value.costUSD // 0) | .key // empty' "$art/claude-output.json" 2>/dev/null || true)"
  [ -n "$cost" ] || cost=0
  [ -n "$turns" ] || turns=0
  duration=$(( $(date +%s) - start ))
  TOTAL_COST="$(awk -v a="$TOTAL_COST" -v b="$cost" 'BEGIN {printf "%.8f", a + b}')"

  # Transcript can appear slightly after the CLI exits.
  local transcript=""
  if [ -n "$session_id" ]; then
    for _ in 1 2 3 4 5; do
      transcript="$(ls "$HOME"/.claude/projects/*/"$session_id".jsonl 2>/dev/null | head -1 || true)"
      [ -n "$transcript" ] && break
      sleep 1
    done
  fi
  [ -n "$transcript" ] && cp "$transcript" "$art/transcript.jsonl"

  git -C "$work" diff baseline final > "$art/diff.patch"
  git -C "$work" log --oneline baseline..final > "$art/git-log.txt"

  # --- grade ---
  local merged='{}' grader out
  for grader in grade-suite grade-revert grade-process grade-static grade-shots; do
    [ -x "$GRADERS/$grader.sh" ] || continue
    if out="$(AFB_SHOT_JUDGE="$WITH_JUDGE" "$GRADERS/$grader.sh" "$work" "$fixture_json" "$task_dir/task.json" "$art/transcript.jsonl" 2>"$art/$grader-stderr.txt")"; then
      merged="$(jq -n --argjson a "$merged" --argjson b "$out" '$a * $b')"
    else
      merged="$(jq -n --argjson a "$merged" --arg g "$grader" '$a * {errors: (($a.errors // []) + [$g])}')"
    fi
  done
  if [ "$WITH_MUTATION" = 1 ] && [ -x "$GRADERS/grade-mutation.sh" ]; then
    out="$("$GRADERS/grade-mutation.sh" "$work" "$fixture_json" "$task_dir/task.json" "$art/transcript.jsonl" 2>"$art/grade-mutation-stderr.txt")" \
      && merged="$(jq -n --argjson a "$merged" --argjson b "$out" '$a * $b')" \
      || merged="$(jq -n --argjson a "$merged" '$a * {errors: (($a.errors // []) + ["grade-mutation"])}')"
  fi
  if [ "$WITH_JUDGE" = 1 ] && [ -x "$GRADERS/judge.sh" ]; then
    out="$("$GRADERS/judge.sh" "$work" "$fixture_json" "$task_dir/task.json" "$art/transcript.jsonl" 2>"$art/judge-stderr.txt")" \
      && merged="$(jq -n --argjson a "$merged" --argjson b "$out" '$a * $b')" \
      || merged="$(jq -n --argjson a "$merged" '$a * {errors: (($a.errors // []) + ["judge"])}')"
  fi

  jq -n \
    --argjson grades "$merged" \
    --argjson completed "$([ "$rc" = 0 ] && echo true || echo false)" \
    --arg reason "$([ "$rc" = 124 ] && echo timeout || echo "exit_$rc")" \
    --arg session "$session_id" --argjson cost "$cost" --argjson turns "$turns" --argjson duration "$duration" \
    --arg model_used "$model_used" \
    '{completed: $completed, reason: (if $completed then "ok" else $reason end),
      session_id: $session, cost_usd: $cost, num_turns: $turns, duration_s: $duration,
      model_used: (if $model_used == "" then null else $model_used end)} + $grades' \
    > "$rep_dir/grades.json"

  local grader_errs
  grader_errs="$(jq -r '(.errors // []) | join(", ")' <<<"$merged")"
  echo "    done in ${duration}s, \$$cost, $turns turns (running total \$$TOTAL_COST)"
  # A crashed grader leaves its gate key absent, which the rollup reads as a
  # FAILED gate. Never let that pass silently as if the model had failed.
  # `if`, not `[ ... ] && echo`: under `set -e` a false test in a standalone
  # && list exits the script.
  if [ -n "$grader_errs" ]; then
    echo "    !! GRADER CRASHED: $grader_errs — its gate scores as failed, but the model may be fine" >&2
  fi
  if [ "$KEEP" = 1 ]; then echo "    workdir kept: $work"; else rm -rf "$work"; fi
}

for task in "${TASKS[@]}"; do
  for rep in $(seq 1 "$REPS"); do
    run_one "$task" "$rep"
  done
done

# --- rollup ------------------------------------------------------------------
SUMMARY="$RUN_DIR/summary.json"
find "$RUN_DIR" -name grades.json | sort | while IFS= read -r f; do
  task="$(basename "$(dirname "$(dirname "$f")")")"
  jq --arg task "$task" '{task: $task, grades: .}' "$f"
done | jq -s \
  --arg run_id "$RUN_ID" --arg label "$LABEL" --arg sha "$SKILL_SHA" \
  --argjson dirty "$SKILL_DIRTY" --arg cc "$CLAUDE_VERSION" --arg model "${MODEL:-default}" \
  --arg candidate "$CANDIDATE" --arg date "$(date +%Y-%m-%d)" '
  # A gate is pass | fail | "errored". A grader that crashed left its key
  # absent; scoring that as a failure blames the model for our bug, so it is
  # reported as "errored" and excluded from gate_pass_rate entirely.
  def gate(v; crashed): if crashed then "errored" else (v // false) end;
  def gates(g): (g.errors // []) as $e | {
    suite_green:       gate(g.suite.green;                          $e | index("grade-suite")),
    revert_check:      gate(g.revert.pass;                          $e | index("grade-revert")),
    process_red_first: gate(g.process.red_before_first_prod_edit;   $e | index("grade-process")),
    static_checks:     gate(g.static.pass;                          $e | index("grade-static"))
  };
  def scored(gs): [gs | to_entries[] | .value | select(. != "errored")];
  group_by(.task) | map({
    key: .[0].task,
    value: {
      reps: [.[] | .grades | . + {gates: gates(.)}],
      rollup: {
        gate_pass_rate: ([.[] | .grades | gates(.) | scored(.)] | flatten
                         | if length > 0 then (map(if . then 1 else 0 end) | add) / length else null end),
        judge_mean: ([.[] | .grades.judge.scores // empty | to_entries[] | select(.key != "notes") | .value | select(. != null)] | if length > 0 then (add / length) else null end),
        grader_errors: ([.[] | .grades.errors // [] | length] | add),
        mutation_mean: ([.[] | .grades.mutation.score // empty] | if length > 0 then (add / length) else null end),
        shot_accuracy_mean: ([.[] | .grades.shots.accuracy // empty] | if length > 0 then (add / length) else null end)
      }
    }
  }) | from_entries |
  { run_id: $run_id, label: $label, date: $date, skill_sha: $sha, skill_dirty: $dirty,
    claude_code_version: $cc, candidate: $candidate,
    model: (([.[] | .reps[] | .model_used | select(. != null)] | first) // $model), tasks: .,
    totals: {
      gate_pass_rate: ([.[] | .rollup.gate_pass_rate | select(. != null)] | if length > 0 then add / length else null end),
      judge_mean: ([.[] | .rollup.judge_mean | select(. != null)] | if length > 0 then add / length else null end),
      grader_errors: ([.[] | .rollup.grader_errors] | add),
      mutation_mean: ([.[] | .rollup.mutation_mean | select(. != null)] | if length > 0 then add / length else null end),
      shot_accuracy_mean: ([.[] | .rollup.shot_accuracy_mean | select(. != null)] | if length > 0 then add / length else null end),
      cost_usd: ([.[] | .reps[] | .cost_usd // 0] | add)
    }
  }' > "$SUMMARY"

jq -c '{run_id, date, label, skill_sha, model, candidate, reps: ([.tasks[].reps | length] | add),
        gate_pass_rate: .totals.gate_pass_rate,
        judge_mean: .totals.judge_mean, mutation_mean: .totals.mutation_mean,
        shot_accuracy: .totals.shot_accuracy_mean,
        per_task: (.tasks | with_entries(.value = .value.rollup.gate_pass_rate)),
        cost_usd: .totals.cost_usd}' "$SUMMARY" >> "$EVALS_DIR/results/history.jsonl"

echo
echo "==> run $RUN_ID complete — total cost \$$(jq -r .totals.cost_usd "$SUMMARY")"
echo "    summary: $SUMMARY"
echo "    trend:   $EVALS_DIR/report.sh"
"$EVALS_DIR/report.sh" 2>/dev/null | tail -5 || true

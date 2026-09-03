# Polyrepo Setup Mode (`/afb-tdd-setup` in a polyrepo)

Read this only when the detector reported a polyrepo — i.e. `.claude/skills/afb-tdd/DIGEST.txt`
begins with `POLYREPO=true`. (`setup-local.sh` detects ≥2 child git repos and delegates to
`setup-polyrepo.sh`, which wrote that digest.)

A polyrepo gets **one skill per member repo plus a top-level cross-repo index**. The index
captures what a single-repo skill can't: the shared domain, the dependency graph between repos,
and how to test the seams. The member skills are produced by the **existing single-repo Setup
Mode**, run once inside each member — no new per-repo logic. As with single-repo setup, the only
files you read for the domain are the ones the digest names; never explore the repos on your own.

1. Read `.claude/skills/afb-tdd/DIGEST.txt` (the `POLYREPO=true` one) and
   `.claude/skills/afb-tdd/SKILL.md.draft`. Then read **only** the files under **PROJECT
   KNOWLEDGE FOUND** — the top-level docs and each member's README. That fixed list is your entire
   context budget for the domain prose.

2. **Fill the top-level draft** from what you read and the digest's **CROSS-REPO CANDIDATES**,
   resolving every `# TODO(...)`:
   - **Member repos** table — one-line role per repo.
   - **Cross-repo dependencies** — turn the candidate signals (shared infra, sibling host/port
     refs, orchestrator, path deps) into the real edge list: who calls whom, over what transport.
   - **Contract testing** and **Cross-repo outside-in order** — name the real seams and repos.
   Leave the `NEEDS CONFIRMATION (P…)` markers for the question round; keep it link-based and terse.

3. **Fan out per member — detection + fill + audit, with NO human interaction.** For each member
   under **MEMBER LIST FOR FAN-OUT**, spawn one agent (run these in parallel) that, scoped to that
   member directory:
   - runs the detector (the `setup-local.sh` path from SKILL.md step 1 — pass it to the agent
     explicitly, it cannot resolve the variable itself) inside the member. It finds no child repos
     there, so it runs ordinary single-repo mode; pass `--simple` only if the user asked for a quick
     setup. If a member already has a local `SKILL.md`, it stops — note that and skip it.
   - follows the single-repo steps 2–4 in SKILL.md for that member: reads the files
     its digest names, fills the draft prose, and — if the member digest has `DEEP_AUDIT=requested`
     — runs the per-module test audit.
   - **does not** call `AskUserQuestion` (subagents can't). Instead, it returns its filled draft
     **plus** that member's **ASK THE HUMAN** questions (Q5–Q9) with the script's proposed defaults.

4. **Batch every question into consolidated rounds.** Collect the polyrepo-level **P1–P6** from the
   top-level digest and each member's returned **Q5–Q9**, and ask them with `AskUserQuestion`
   grouped into rounds of ≤4 (e.g. one round for the polyrepo domain/dependency/contract questions,
   then one round per member, or grouped by theme). Apply each answer to the right draft — P-answers
   to the top-level draft (P5 links go in the contract/domain sections as pointers; don't inline
   them), Q-answers to that member's draft.

5. **Promote everything.** For each member, write its `.claude/skills/afb-tdd/SKILL.md` and delete
   that member's `SKILL.md.draft` + `DIGEST.txt`. Then write the top-level
   `.claude/skills/afb-tdd/SKILL.md` and delete the top-level `SKILL.md.draft` + `DIGEST.txt`.

6. **Confirm.** Each generated skill invokes the loop by skill name; none records a path. Report
   the member list and that `/afb-tdd` resolves to the top-level cross-repo
   index at the container root and to each member's own skill inside that member. Show each
   member's resolved full-suite command and remind the user each member is its own git repo (commit
   per repo).

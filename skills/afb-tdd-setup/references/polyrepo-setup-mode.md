# Polyrepo setup (`/afb-tdd-setup` in a polyrepo)

Read this only when the detector reported a polyrepo: `.claude/afb-tdd/DIGEST.txt`
begins with `POLYREPO=true`. (`setup-local.sh` detects ≥2 child git repos and delegates
to `setup-polyrepo.sh`, which wrote that digest.)

**There is no top-level cross-repo skill or index.** The container usually is not a git
repo, so anything written there cannot be committed, which is the whole point of these
resources. Each member repo gets its own `.claude/afb-tdd/`, committed to that member.
Cross-repo knowledge lands in each member's `project.md` as *that member's own edges* —
who it calls, who calls it, what governs the seam — not as a copy of the whole graph.

As in single-repo setup, the only files you read are the ones the digest names. Never
explore the repos on your own.

1. Read `.claude/afb-tdd/DIGEST.txt`. Then read **only** the files under **PROJECT
   KNOWLEDGE FOUND** — the top-level docs and each member's README. That fixed list is
   your entire context budget for the domain prose.

2. **Fan out per member — detection, fill, and audit, with no human interaction.** For
   each member under **MEMBER LIST FOR FAN-OUT**, spawn one agent (run these in parallel)
   that, scoped to that member directory:
   - runs the detector (the `setup-local.sh` path from `SKILL.md` step 1 — pass it to the
     agent explicitly, it cannot resolve the variable itself) inside the member. It finds
     no child repos there, so it runs ordinary single-repo mode; pass `--simple` only if
     the user asked for a quick setup. If a member already has resources the detector
     stops; note that and skip it.
   - follows the single-repo steps 2–4 in `SKILL.md` for that member: reads the files its
     digest names, fills `project.md`, and — if the member's digest has
     `DEEP_AUDIT=requested` — runs the per-module audit and writes `practices.md`.
   - adds a **Cross-repo** section to that member's `project.md` covering only its own
     edges, using the digest's **CROSS-REPO CANDIDATES** as signals to confirm, never as
     fact. Where a seam has a contract (OpenAPI, Pact, shared schema, generated client),
     name it and say which repo owns it. Where one doesn't, say so plainly: the consumer's
     fake of that provider is unverified, and the Fake + Contract Testing rule from the
     `afb-tdd` skill's `references/test-patterns.md` applies across repo boundaries just
     as it does within one.
   - **does not** call `AskUserQuestion` (subagents can't). Instead it returns its filled
     files **plus** that member's **ASK THE HUMAN** questions (Q5–Q9) with the script's
     proposed defaults.

3. **Batch every question into consolidated rounds.** Collect the polyrepo-level **P1–P5**
   from the top-level digest and each member's returned **Q5–Q9**, and ask them with
   `AskUserQuestion` grouped into rounds of ≤4 — one round for the polyrepo-level
   questions, then one per member, or grouped by theme. Lead each with the recommended
   answer. Apply P-answers across the affected members' `project.md` files, and Q-answers
   to that member's own.

   P1's domain doc is **linked** from each member, never copied into them.

4. **Write.** For each member, write its `.claude/afb-tdd/project.md` (and `practices.md`
   where the audit ran), then delete that member's `DIGEST.txt`. Finally delete the
   container's `DIGEST.txt`.

5. **Confirm.** Report the member list, each member's resolved full-suite command, and
   that each member is its own git repo, so these resources are committed per repo. Say
   explicitly that there is no top-level index and that cross-repo edges live in each
   member's `project.md`, so nobody goes looking for one.

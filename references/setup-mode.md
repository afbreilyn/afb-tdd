# Setup Mode (`/afb-tdd setup`)

Read this only when the skill was invoked as `/afb-tdd setup`. It scaffolds a **project-local** skill at `.claude/skills/afb-tdd/SKILL.md` that inherits the global TDD workflow and adds project-specific overrides. A deterministic script does all the codebase detection (zero tokens); you fill in only what it can't detect, reading a small, fixed set of files it points you to. **Never explore the repository on your own — the only files you may read are the ones the digest names.**

By default this includes a test-suite audit (step 4). If the user asked for a quick/simple/shallow setup (e.g. `/afb-tdd setup --simple`, or words like "simple", "quick", "skip the audit"), pass `--simple` to the script in step 1.

1. Run the detector (writes only into `.claude/skills/afb-tdd/`, never your source):
   ```bash
   bash ~/.claude/skills/afb-tdd/scripts/setup-local.sh        # --force to regenerate, --simple to skip the test audit
   ```
   If that path doesn't exist (plugin install), locate it: `bash "$(find ~/.claude -path '*afb-tdd*/scripts/setup-local.sh' 2>/dev/null | head -1)"`. If it reports a local skill already exists, tell the user (re-run with `--force`) and stop.

   **Polyrepo:** if `.claude/skills/afb-tdd/DIGEST.txt` begins with `POLYREPO=true`, the detector found ≥2 child git repos and delegated to `setup-polyrepo.sh` — follow [polyrepo-setup-mode.md](polyrepo-setup-mode.md) instead of the steps below. (To force single-repo treatment of a folder-of-repos, re-run the detector with `--no-polyrepo`.)

2. Read `.claude/skills/afb-tdd/DIGEST.txt` and `.claude/skills/afb-tdd/SKILL.md.draft`. Then read **only** the files the digest lists under **PROJECT KNOWLEDGE FOUND** — the project's own style rules, instruction files (`CLAUDE.md` etc.), and the named README architecture sections. That fixed list is your entire context budget for this step; do not open anything else.

3. Fill the draft from what you just read, resolving every `# TODO(...)` / `NEEDS CONFIRMATION` marker:
   - **Stack** one-liner; **Path-scoped rules** one-line summaries; **Architecture** — what each module does and its key entry-point files; **Outside-in slice order** — refine the generic steps to name the project's real dirs/files.
   - Keep it **link-based and terse**: link the project's rules/docs, don't restate them. The draft already links only the project's own rules (or the stack-relevant global conventions if it has none) — leave that as generated.

4. **If the digest contains `DEEP_AUDIT=requested`**, run the test-suite audit now: fan out one agent per module listed under **LOCATED FOR DEEP AUDIT**. Each agent first reads the project's own style rules (located in step 2), then audits that module's test files against them and returns (a) gold-standard exemplar files with `file:line`, (b) shipped violations grouped by area, (c) the single worst file to not imitate. Fold the results into the draft's **Test helpers & gold-standard files**, **Known deviations**, and **Don't imitate this file** sections. (With `--simple` the `DEEP_AUDIT` marker and those sections are absent — skip this step.)

5. Ask the human the **ASK THE HUMAN** questions (Q5–Q9) from the digest in one `AskUserQuestion` round, using the script's proposed defaults; apply the answers. Q9's links go into the Architecture **External / linked docs** line — record them as pointers (they may need an MCP connector or the user to paste content; don't try to inline them).

6. Write the finished file to `.claude/skills/afb-tdd/SKILL.md`, delete `SKILL.md.draft` and `DIGEST.txt`, then confirm that `/afb-tdd` in this repo now runs the local version and show the resolved full-suite command.

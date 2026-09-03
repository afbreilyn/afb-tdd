---
name: afb-tdd-setup
description: Tune the afb-tdd loop to this repo — detects stack, commands, architecture and conventions, audits the existing test suite, and writes committed resources the loop reads. Invoke when asked to set up, bootstrap, or initialize TDD for a project or polyrepo.
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/setup-local.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/setup-polyrepo.sh *)
---

Write `.claude/afb-tdd/` for this repo: committed resources the `afb-tdd` loop reads instead of rediscovering the project every cycle. A deterministic script does the codebase detection (zero tokens); you fill in only what it can't detect, reading a small fixed set of files it points you to. **Never explore the repository on your own — the only files you may read are the ones the digest names.**

```
.claude/afb-tdd/
├── manifest.json   what was generated, when, against which commit   (script)
├── project.md      facts: stack, commands, layout, slice order      (script + you, step 3)
└── practices.md    taste: how this team tests                       (you, step 4)
```

This skill only sets up. It never runs the TDD loop, and it never writes a skill — the loop is the separate `afb-tdd` skill and treats these files as a **soft** dependency: it works without them and falls back to its own references. Nothing you write here may name another skill's install path.

The test-suite audit (step 4) runs by default. If the user asked for a quick/simple/shallow setup (e.g. `/afb-tdd-setup --simple`, or words like "simple", "quick", "skip the audit"), pass `--simple` in step 1 and skip step 4.

1. Run the detector (writes only into `.claude/afb-tdd/`, never your source):
   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/setup-local.sh
   ```
   Flags: `--simple` skips the test audit, `--no-polyrepo` forces single-repo treatment of a folder-of-repos, `--refresh` regenerates beside existing files for a human to merge, `--force` overwrites in place.

   If it reports resources already exist, **stop and tell the user** — these files belong to them once written. Offer `--refresh` (writes `project.md.new` to diff) or `--force` (discards their edits). Never pick `--force` for them.

   **Polyrepo:** if `.claude/afb-tdd/DIGEST.txt` begins with `POLYREPO=true`, the detector found ≥2 child git repos and delegated to `setup-polyrepo.sh` — follow [references/polyrepo-setup-mode.md](references/polyrepo-setup-mode.md) instead of the steps below. That file refers to "the detector"; the path is the one above.

2. Read `.claude/afb-tdd/DIGEST.txt` and `.claude/afb-tdd/project.md`. Then read **only** the files the digest lists under **PROJECT KNOWLEDGE FOUND** — the project's own style rules, instruction files (`CLAUDE.md` etc.), and the named README architecture sections. That fixed list is your entire context budget for this step; do not open anything else.

3. **Fill `project.md`**, resolving every `# TODO(...)` / `NEEDS CONFIRMATION` marker:
   - **Stack** one-liner; **Path-scoped rules** one-line summaries; **Architecture** — what each module does and its key entry-point files; **Outside-in slice order** — refine the generic steps to name the project's real dirs and files.
   - Keep it **link-based and terse**: link the project's rules and docs, don't restate them. Leave the generated links as they are.
   - Every path you write must be repo-relative. This file is committed and read on other people's machines.

4. **If the digest contains `DEEP_AUDIT=requested`, write `practices.md`.** This is the main event, not an appendix. Fan out one agent per module listed under **LOCATED FOR DEEP AUDIT**. Each agent first reads the project's own style rules (located in step 2), then audits that module's test files against them and returns (a) gold-standard exemplar files with `file:line`, (b) shipped violations grouped by area, (c) the single worst file to not imitate.

   Then write `.claude/afb-tdd/practices.md` with these sections:
   - **How we test here** — the stack-relevant built-in conventions (`references/conventions/*.md` in the `afb-tdd` skill, named in the digest) *rewritten against this repo*: its real helper APIs, its real names, its actual examples. Not a copy. If the repo's own rule files disagree with a built-in convention, the repo wins and you say so.
   - **Gold-standard files** — exemplars with `file:line` and one line on what each demonstrates.
   - **Known deviations** — shipped violations grouped by area, explicitly marked as *not precedent*.
   - **Don't imitate this file** — the single worst reference, and the file to copy instead.

5. Ask the human the **ASK THE HUMAN** questions (Q5–Q9) from the digest, using the script's proposed defaults. Lead each with the recommended answer so it can be accepted in a word; skip any the digest already settled. Q9's links go into `project.md`'s **External / linked docs** line as pointers (they may need an MCP connector or the user to paste content; don't try to inline them).

6. Delete `DIGEST.txt`. Then tell the user: which files were written, that they are committed and belong to the team, that `/afb-tdd` will now read them, and the resolved full-suite command. Offer once to add a pointer to the repo's `CLAUDE.md` — don't do it unprompted, it costs context in every session including non-TDD ones.

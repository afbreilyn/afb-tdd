---
name: afb-tdd
description: Interactive red-green-refactor TDD workflow. Invoke when writing new features or fixing bugs test-first.
user-invocable: true
allowed-tools: Bash
---

**Setup vs. the loop:** if invoked as `/afb-tdd setup`, **or** if the user asks — now or in any follow-up — to *set up*, *bootstrap*, or *initialize* a project-local afb-tdd skill, then do not run the red-green loop: read [references/setup-mode.md](references/setup-mode.md), follow it, then stop. (The test-suite audit runs by default; pass `--simple` if they want a quick scaffold without it.) Otherwise, ignore setup and start the loop here.

## Before You Start

Determine which layer to begin at (see [test-patterns.md](references/test-patterns.md)):
- **Has user-facing behaviour?** Start with a Playwright E2E spec.
- **Frontend-only change?** Start with a frontend component test.
- **Backend feature with no UI?** Start with a backend integration or unit test.
- **Bug fix?** Write a failing test that reproduces the bug first — before touching any code. This test prevents the regression from ever happening again.

Then follow this strict red-green-refactor loop. Do not skip or combine steps.

**Autonomous mode:** when invoked as `/afb-tdd --auto`, or when running non-interactively (headless `-p`), do not pause for user confirmation at the end of Red/Green/Refactor. Still produce the same report at each pause point (called shot, failure output, results), then continue. At the end of each Refactor step, make a git commit with message `tdd(cycle N): <behaviour>`. Every other rule is unchanged.

## Test Sequencing

When starting a new behaviour, work in this order:
1. **Degenerate/zero case** — establishes the API shape
2. **1–2 exception/error cases** — defines the valid input contract
3. **Happy path incrementally** — Fake It first, then Obvious Implementation
4. **Remaining exception cases** — once the core is established

## Red
1. Before writing the test, declare your called shot:
   - **Test name:** [descriptive name]
   - **Behaviour under test:** [observable behaviour]
   - **Expected failure:** [exact assertion message when red]

   A mismatch between predicted and actual failure is a stop condition — delete the test and reconsider.
2. Write exactly one failing test — the smallest slice of behaviour that adds value.
3. Run the tests yourself. Check whether the test fails for the right reason (not due to a typo or syntax error).
   - If it passes immediately, or fails for the wrong reason, delete the test and start over with the same goal. Do not leave broken test code for the user to deal with.
4. **Sceptic** (mandatory — never skip): launch one read-only subagent following the RED checkpoint in [sceptic.md](references/sceptic.md). Address every finding: fix blockers and rerun the test; rebut anything you disagree with. One round only — never re-sceptic a fix.
5. Report the failure output and confirm it's failing correctly, then wait for the user to confirm before continuing. The report must contain a `Sceptic:` section — findings verbatim with your response to each, or `CLEAN`.

## Green
1. Write the minimum implementation to make the test pass. Nothing more. Hardcode if possible, don't make it handle future scenarios. State which you're doing: **Fake It** (will triangulate next cycle) or **Obvious Implementation**.
2. Run the tests yourself. Check whether the new test passes and all other tests remain green.
   - If something unexpected is failing, fix it before reporting to the user.
3. **Sceptic**: same as Red step 4, but the GREEN checkpoint in [sceptic.md](references/sceptic.md).
4. Report the results and wait for the user to confirm before continuing. The report must contain a `Sceptic:` section — findings verbatim with your response to each, or `CLEAN`.

## Refactor
1. Now that tests are green, clean up thoroughly — names, duplication, extraction of well-named helpers. Do not defer this to a later cycle.
2. Only refactor while green. Never refactor while red.
3. Remove any tests that now provide redundant coverage or that didn't fail for the right reason.
4. Run the full test suite to verify no unintended side effects across the whole codebase.
5. Ask the user if they want to commit the cycle, wait for their input, and once they give you the go-ahead, return to Red for the next slice.

## Component Extraction

When extracting a component out of an existing page or parent component, assert the **contract, not the boundary**. The parent's job is to pass a piece of data down and see it represented in the output — it should not care *which* child component renders it.

1. In the **parent's test file**, pass in a distinguishing piece of data and assert that data is **visible** in the rendered output (`getByText` / `getByRole`). Do not assert on the component's identity or structure.
2. Choose data that is unique enough to query unambiguously and that the parent genuinely owns. A name or label works; a bare boolean or a value that also appears elsewhere on the page does not.
3. Redraw the ownership boundary carefully: the parent asserts only *that its data shows up*; the child's own test file owns *how* it's formatted, styled, and laid out. Don't assert the wrapping element, tag, or classes in the parent — that just relocates the brittleness.

```tsx
// ✅ Parent test — asserts the data it passes down is represented, agnostic to the child
it('shows the signed-in user', () => {
  render(<Dashboard user={{ name: 'Ada' }} />);
  expect(screen.getByText('Ada')).toBeInTheDocument();
});

// ✅ Component test — owns the content and structure assertions
it('renders all main navigation links', () => {
  render(<Sidebar />);
  expect(screen.getByRole('link', { name: /dashboard/i })).toBeVisible();
});
```

**Fallback — `data-testid`:** only when there is no user-visible data to key on (a purely presentational extraction like an icon or divider, or localized / non-accessible text). Then add `data-testid="<component-name>"` to the extracted component's root and assert `getByTestId('<component-name>')` is in the document — presence only, never internal content.

## Rules
- NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.
- If you wrote code before a test existed, delete it entirely. Do not adapt it — unverified code is technical debt.
- Never write a `catch` or error case without a failing test for it first.
- Each cycle should cover zero, one, or many — prefer the smallest slice.
- Tests written first answer "what *should* this do?". Tests written after only answer "what *does* this do?" — they prove nothing.
- If you find yourself thinking "just this once" about skipping a step, that is a red flag. Stop and restart the cycle properly.
- Each cycle is deliberately small. This is especially important when working with an AI assistant: small context = higher accuracy. Don't batch cycles together.

See [sceptic.md](references/sceptic.md) for the adversarial review rubric (shared with the eval judge).
See [test-patterns.md](references/test-patterns.md) for outside-in layer ordering, contract testing fakes, and when to use each type of test double.
See [conventions/go.md](references/conventions/go.md) for Go-specific test conventions — testify, suites, fakes, transparent fakes, time control.
See [conventions/frontend.md](references/conventions/frontend.md) for frontend test conventions — selectors, structure, factories, async patterns.
See [conventions/vitest.md](references/conventions/vitest.md) for Vitest-specific conventions — globals, vi.fn, vi.hoisted, MSW setup. Reference this from your project skill if your project uses Vitest.
See [conventions/java.md](references/conventions/java.md) for Java-specific conventions. Reference this from your project skill if your project uses Junit5.
See [testing-anti-patterns.md](references/testing-anti-patterns.md) for guidance on what not to do with mocks and test structure.
See [tdd-checklist.md](references/tdd-checklist.md) for the completion checklist and a "when stuck" reference.

## Commits
Do not attribute commits to yourself or list Claude as a co-author

# Testing Anti-Patterns

**Load this reference when:** writing or changing tests, adding mocks, or tempted to add test-only methods to production code.

Tests must verify real behaviour, not mock behaviour. Mocks are a means to isolate, not the thing being tested.

**Core principle:** Test what the code does, not what the mocks do.

## The Iron Laws

1. NEVER test mock behaviour
2. NEVER add test-only methods to production classes
3. NEVER mock without understanding dependencies

## Anti-Pattern 1: Testing Mock Behaviour

```typescript
// ❌ BAD: Testing that the mock exists
test('renders sidebar', () => {
  render(<Page />);
  expect(screen.getByTestId('sidebar-mock')).toBeInTheDocument();
});
```

You're verifying the mock works, not that the component works. This tells you nothing about real behaviour.

```typescript
// ✅ GOOD: Test real component or don't mock it
test('renders sidebar', () => {
  render(<Page />);
  expect(screen.getByRole('navigation')).toBeVisible();
});
```

### Gate Function

```
BEFORE asserting on any mock element:
  Ask: "Am I testing real component behaviour or just mock existence?"
  IF testing mock existence: delete the assertion or unmock the component
```

## Anti-Pattern 2: Test-Only Methods in Production

```typescript
// ❌ BAD: destroy() only used in tests
class Session {
  async destroy() {
    await this._workspaceManager?.destroyWorkspace(this.id);
  }
}
```

Production class polluted with test-only code. Dangerous if accidentally called in production.

```typescript
// ✅ GOOD: Test utilities handle test cleanup
export async function cleanupSession(session: Session) {
  const workspace = session.getWorkspaceInfo();
  if (workspace) await workspaceManager.destroyWorkspace(workspace.id);
}
```

### Gate Function

```
BEFORE adding any method to production class:
  Ask: "Is this only used by tests?"
  IF yes: put it in test utilities instead
```

## Anti-Pattern 3: Mocking Without Understanding

```typescript
// ❌ BAD: Mock breaks test logic
test('detects duplicate server', () => {
  // This mock prevents the config write the test depends on!
  vi.mock('ToolCatalog', () => ({            // vi.mock / jest.mock
    discoverAndCacheTools: vi.fn().mockResolvedValue(undefined)  // vi.fn / jest.fn
  }));
  await addServer(config);
  await addServer(config); // Should throw — but won't
});
```

Over-mocking to "be safe" breaks actual behaviour.

```typescript
// ✅ GOOD: Mock at the correct level
test('detects duplicate server', () => {
  vi.mock('MCPServerManager'); // vi.mock / jest.mock — mock the slow part, preserve needed behaviour
  await addServer(config);    // Config written
  await addServer(config);    // Duplicate detected ✓
});
```

### Gate Function

```
BEFORE mocking any method:
  1. Ask: "What side effects does the real method have?"
  2. Ask: "Does this test depend on any of those side effects?"
  IF yes: mock at a lower level, not the method the test depends on
  IF unsure: run the test against the real implementation first, then add minimal mocking
```

Red flags: "I'll mock this to be safe" / "This might be slow, better mock it"

## Anti-Pattern 4: Incomplete Mocks

```typescript
// ❌ BAD: Partial mock — only fields you think you need
const mockResponse = {
  status: 'success',
  data: { userId: '123', name: 'Alice' }
  // Missing: metadata that downstream code uses — silent failure
};

// ✅ GOOD: Mirror real API completeness
const mockResponse = {
  status: 'success',
  data: { userId: '123', name: 'Alice' },
  metadata: { requestId: 'req-789', timestamp: 1234567890 }
};
```

### Gate Function

```
BEFORE creating mock responses:
  1. Check what fields the real API response contains
  2. Include ALL fields the system might consume downstream
  If uncertain: include all documented fields
```

## Anti-Pattern 5: Integration Tests as Afterthought

Testing is part of implementation, not an optional follow-up. TDD prevents this by construction.

## When Mocks Become Too Complex

Warning signs:
- Mock setup is longer than test logic
- Mocking everything just to make the test pass
- Test breaks when mock changes

Consider: integration tests with real components are often simpler than complex mocks.

## Quick Reference

| Anti-Pattern | Fix |
|---|---|
| Assert on mock elements | Test real component or unmock it |
| Test-only methods in production | Move to test utilities |
| Mock without understanding | Understand dependencies first, mock minimally |
| Incomplete mocks | Mirror real API completely |
| Tests as afterthought | TDD — tests first |
| Over-complex mocks | Consider integration tests |
| Trusting a green-on-arrival legacy test | Sabotage production to force the red, then restore — or delete it |

## Anti-Pattern 6: Never Watching the Test Fail

```typescript
// ❌ BAD: test calls the wrong method entirely
it("getMessagesByUserId returns messages for the user", async () => {
  const result = await getMessagesDueAt(userId); // wrong method!
  expect(result).toHaveLength(1);
});
```

This test may pass immediately — `getMessagesDueAt` might return an empty array that happens to satisfy a loose assertion, or the test author never ran it in isolation. Either way, the test proves nothing about `getMessagesByUserId`.

The red step isn't bureaucracy. It's the only way to verify that the test is actually testing what you think it's testing. A test that was never red tells you nothing.

**The rule:** If a test passes before you write the implementation, delete it. Start over. Do not keep a test you've never seen fail.

```
Gate function:
  BEFORE marking a test red: run it and read the failure message.
  Ask: "Does this failure describe the missing behaviour I'm about to implement?"
  IF the test passes: delete it.
  IF it fails but for the wrong reason (wrong method, typo, syntax error): delete it and fix the test.
  ONLY continue if the failure is exactly what you expected.
```

---

## Anti-Pattern 7: Happy-Path Tunnel Vision

```typescript
// ❌ BAD: only the success case is covered
describe("submitApplication", () => {
  it("submits successfully with valid data", async () => { ... });
  // Error paths: missing
  // Network failure: missing
  // Validation failure: missing
  // Duplicate submission: missing
});
```

Happy-path-only test suites feel complete but leave the most dangerous behaviour untested. Real-world failures almost always happen in error paths — invalid input, network timeouts, partial failures — not in the golden path.

```typescript
// ✅ GOOD: error paths are first-class citizens
describe("submitApplication", () => {
  it("submits successfully with valid data", async () => { ... });
  it("returns VALIDATION_ERROR when required fields are missing", async () => { ... });
  it("returns DUPLICATE_ERROR when the application already exists", async () => { ... });
  it("persists the draft even when the submission service is unavailable", async () => { ... });
});
```

A useful heuristic: for every happy-path test, ask "what are all the ways this can fail?" and write a test for each answer.

---

## Anti-Pattern 8: Trusting a Driven Test You Never Watched Fail

This is Anti-Pattern 6's evil twin, and it only bites in **driving-tests / Green→Red→Green** mode (see [driving-tests.md](driving-tests.md)). When you write a test against code that *already exists*, it goes green on arrival — and that green is worthless. It might be passing because of a cache, a stubbed collaborator, a tautological assertion, or because the code path it claims to cover is never reached.

```typescript
// ❌ BAD: "characterized" legacy behaviour, never sabotaged
it("applies the loyalty discount", () => {
  const total = checkout(cartWith(loyaltyMember));
  expect(total).toBe(90); // passes immediately — but does it touch the discount code at all?
});
// Comment out the discount line in production... and this test still passes.
// It was never coupled to the behaviour. It is a green lie.
```

In red-green you get the failure for free (the code doesn't exist yet). In legacy code you must **manufacture** it: sabotage the production line that should make the test red, watch it fail for the reason you predicted, then restore. Flipping the *assertion* is not enough — that only proves the test runs. You must mutate **production** to prove the test is causally coupled to the behaviour.

```
Gate function (driving-tests mode):
  AFTER a freshly-written test passes on existing code:
  1. Predict the smallest production change that should flip THIS test, and the exact failure.
  2. Apply it (comment out / negate / stub the return). Run.
  IF this test goes red for the predicted reason: restore, and now trust it.
  IF it stays green: it does not test that behaviour — annotate the code DRIVE:UNTESTABLE,
     DELETE the hollow test, and log the finding. Do not keep a green you couldn't break.
  IF it reds for a different reason: stop — you don't yet understand the path.
```

**The rule:** A driven test you have not watched go red is not a safety net — it's a green lie that will let a refactor silently break behaviour. No commented-out production logic survives the cycle (grep for `DRIVE:SABOTAGE`).

---

## The Bottom Line

Mocks are tools to isolate, not things to test. If TDD reveals you're testing mock behaviour, you've gone wrong.

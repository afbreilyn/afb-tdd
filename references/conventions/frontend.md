# Frontend Test Conventions

These conventions apply regardless of whether you use Jest or Vitest. See your project's framework convention file for library-specific globals, mock APIs, and setup patterns.

## Assertions

- For presence: prefer visibility assertions over DOM-membership assertions.
- For absence: assert the element is not in the document.
- Prefer async query variants (`findBy*`) over polling wrappers for async elements.
- Do not wrap multiple expectations in a single async wait.
- Inline element matchers in assertions if used only once; assign to a variable only if used more than once.

## Test Structure

- Follow zero/one/many: add the smallest vertical slice of value possible.
- Each test covers one behaviour. If you need AND to describe it, split into two tests.
- Group related tests in `describe` blocks.
- Use parameterized test helpers (`it.each` / `test.each`) instead of iterating with `forEach`.
- Follow Arrange-Act-Assert separated by blank lines. No section comments.
- All setup in the test itself; avoid `beforeEach` unless setup is shared by multiple tests.

## Element Selectors

Prefer in this order:
1. `*byRole` with `name`
2. `*byText`
3. `*byTestId` (last resort)

Prefer string literals over regex patterns.

## Interaction

Prefer user-event over synthetic events — it simulates real browser behaviour more faithfully.

## Mocking

Intercept HTTP at the network layer rather than mocking fetch or your HTTP client directly. Your project's framework convention file specifies the library and setup pattern.

## Test Data

Define factory functions that return complete objects with sensible defaults and accept overrides:

```typescript
const createMockUser = (overrides: Partial<UserType> = {}): UserType => ({
  id: "user-1",
  email: "test@example.com",
  name: "Test User",
  // ...all required fields
  ...overrides,
});
```

Never use partial inline construction (`{ id: "1" } as UserType`) — missing fields cause silent failures.

## Time-Dependent Logic

For logic that depends on the current time, write tests that run in at least two different time zones (e.g. New York and Kolkata) to surface timezone-related bugs.

## Error Paths

Test both success and error paths. Do not write `catch` blocks or error cases without a failing test for them first.

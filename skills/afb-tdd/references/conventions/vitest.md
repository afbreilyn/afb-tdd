# Vitest Test Conventions

## Globals

Use Vitest globals — do NOT import `describe`, `it`, `expect`, `beforeEach`, etc. from `vitest`. They are available globally via the Vitest config.

Do NOT use Jest methods. Use the Vitest equivalents:

| Jest | Vitest |
|---|---|
| `jest.fn()` | `vi.fn()` |
| `jest.mock(...)` | `vi.mock(...)` |
| `jest.spyOn(...)` | `vi.spyOn(...)` |
| `jest.clearAllMocks()` | `vi.clearAllMocks()` |

## User Interaction

Define `const user = userEvent.setup()` once per test suite (outside `beforeEach`), not once per test.

## Assertions

- For presence: use `toBeVisible`.
- For absence: use `.not.toBeInTheDocument()`.
- `findBy*` over `waitFor` for async element queries.
- Never wrap multiple expectations in a single `waitFor`.

## Parameterized Tests

Use `it.each` instead of iterating with `forEach`.

## Mocking Modules

When a variable is used inside a `vi.mock(...)` factory, declare it with `vi.hoisted()` so it is initialised before the mock factory runs:

```typescript
const mockFetch = vi.hoisted(() => vi.fn());

vi.mock("../api", () => ({
  fetchUser: mockFetch,
}));
```

## HTTP Mocking (MSW)

Use MSW to intercept HTTP calls — do not mock fetch or axios directly.

```typescript
const server = setupServer(
  http.post("/api", async ({ request }) => {
    const body = await request.json();
    // handle and return
    return HttpResponse.json({ result: "ok" });
  }),
);

beforeAll(() => server.listen());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

Your project's convention file specifies the exact MSW helper and endpoint to use.

# Test Patterns

## Outside-In TDD

Start at the outermost layer that exercises the desired behaviour. Work inward only when the outer test forces you to.

```
Playwright E2E (browser + real backend)
    ↓ forces
Frontend unit tests (Vitest + React Testing Library)
    ↓ forces
Backend integration tests (httptest + in-memory fakes)
    ↓ forces
Backend unit tests (fakes, domain logic)
    ↓ forces
Repository layer (real DB — contract tests)
```

**Start with a Playwright spec** when the feature has user-facing behaviour. Let it fail. Work inward, writing the minimal code at each layer to make the outer test pass. Don't go deeper than the failing test requires.

**Start at a lower layer** only when the behaviour has no meaningful UI expression (e.g., a background job, a pure data transformation).

### Example

A Playwright spec describes the full user journey. It forces you to build the UI, the API call, and the backend handler — but only what the test needs:

```typescript
// e2e/user-submits-report.spec.ts
test("User can submit a report", async ({ page }) => {
  await loginAs(page, testUser);

  await expect(page.getByText("No reports yet")).toBeVisible();

  await page.getByRole("button", { name: "Submit" }).click();
  await expect(page.getByText("Title is required")).toBeVisible();

  await page.getByRole("textbox", { name: "Title" }).fill("Q1 Summary");
  await page.getByRole("combobox", { name: "Category" }).selectOption("Finance");

  await page.getByRole("button", { name: "Submit" }).click();

  await expect(page.getByText("Report submitted")).toBeVisible();
});
```

This E2E test failing drives you to write a `ReportForm` frontend unit test, which drives you to write a `Report.Submit` backend integration test, which drives the service and repository implementation.

---

## Fake + Contract Testing

A fake that isn't verified against the real implementation is a liability. It can pass all your tests while the real behaviour has diverged.

**The rule:** If you write a fake, write a shared contract test suite that runs against both the fake and the real implementation.

Define a shared test function that accepts the interface under test. Run it once against the fake and once against the real implementation. If the fake drifts, the contract tests catch it before it reaches production.

```go
// repository/fakes/user.go — in-memory implementation
func NewFakeUserRepository() *FakeUserRepository {
    fakeRepo := &FakeUserRepository{users: make(map[int32]*userData)}

    newUser := domaintest.NewUnpersistedUser(
        domaintest.WithEmail("test-user@example.com"),
        domaintest.WithPassword("s3cr3t"),
    )
    _, _ = fakeRepo.Save(context.Background(), newUser)
    return fakeRepo
}

// Contract function — runs against any UserRepositoryInterface
func RunUserRepositoryContract(t *testing.T, repo repository.UserRepositoryInterface) {
    t.Helper()
    t.Run("retrieves a saved user by email", func(t *testing.T) {
        user := domaintest.NewUnpersistedUser(domaintest.WithEmail("contract@example.com"))
        _, err := repo.Save(context.Background(), user)
        require.NoError(t, err)

        found, err := repo.GetByEmail(context.Background(), "contract@example.com")
        require.NoError(t, err)
        assert.Equal(t, "contract@example.com", found.Email())
    })
}

// Runs against fake — fast, no DB needed
func TestFakeUserRepository(t *testing.T) {
    contract.RunUserRepositoryContract(t, fakes.NewFakeUserRepository())
}

// Runs against real DB — catches drift
func TestPostgresUserRepository(t *testing.T) {
    contract.RunUserRepositoryContract(t, postgres.NewUserRepository(setupTestDB(t)))
}
```

---

## Test Data

Always build test data from domain objects using builder/factory helpers, not raw structs constructed inline. Builders enforce complete objects and accept overrides for the specific values a test cares about.

Never partially construct a mock object inline — incomplete mocks hide structural assumptions (see testing-anti-patterns.md).

```go
// ❌ BAD: raw struct construction — missing fields cause silent failures
user := &domain.User{Email: "test@example.com"} // incomplete

// ✅ GOOD: builder with sensible defaults, override only what the test cares about
user := domaintest.NewUnpersistedUser(
    domaintest.WithEmail("blocked@example.com"),
    domaintest.WithOrgID(orgID),
)
```

```typescript
// ❌ BAD: partial inline construction — TypeScript may allow it but fields are missing
const mockUser = { id: "1" } as UserType;

// ✅ GOOD: factory with defaults, override only what the test needs
const mockUser = createMockUser({ id: "2" });
```

---

## When to Use Each Type of Double

| Situation | Use |
|---|---|
| Isolate from DB in unit/integration tests | Fake (in-memory implementation of the interface) |
| Isolate from external HTTP API in frontend | MSW (intercepts fetch at the network layer) |
| Verify a method was called with specific args | Mock (`vi.fn()` / testify/mock) — sparingly |
| Replace a slow side effect you don't care about | Stub (e.g., `StubEmailService`) |
| Full stack behaviour | Real implementation via E2E or contract test |

Default to fakes over mocks. Mocks test interactions; fakes test behaviour.

### Examples

**Fake** — full in-memory implementation, used for all repository isolation:

```go
// services/userservice_test.go
func (s *userServiceSuite) SetupTest() {
    s.userRepo = fakes.NewFakeUserRepository()
    s.userService = services.NewUserService(s.userRepo)
}
```

**MSW** — intercepts HTTP calls in frontend tests:

```typescript
// components/ReportForm.test.tsx
const server = setupServer(
  http.post("/api", async ({ request }) => {
    const body = (await request.json()) as ApiRequestBody;

    if (body.method === "Report.Submit") {
      return HttpResponse.json({ jsonrpc: "2.0", result: null, id: body.id });
    }
    throw new Error("api mock fallthrough");
  }),
);

beforeAll(() => server.listen());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

**Mock** — when you need to verify a specific call was made (used sparingly):

```go
// services/registration_test.go
s.mockMailer.On("SendWelcomeEmail", ctx, newUser.Email()).Return(nil)
// ... exercise the code ...
s.mockMailer.AssertExpectations(s.T())
```

**Integration test server** — real services, fake repositories, no mocking needed:

```go
// tests/integration/report_integration_test.go
srv := apptest.NewServer(t) // spins up real app with fake repositories
defer srv.Close()

resp, err := http.Post(srv.URL+"/api/reports", "application/json",
    strings.NewReader(`{"title":"Q1","category":"finance"}`))
require.NoError(t, err)
assert.Equal(t, http.StatusCreated, resp.StatusCode)
```

---

## One Behaviour Per Test

Each test should cover one behaviour. If you need AND to describe what a test covers, split it into two tests.

A test may have multiple assertions if they all verify the same behaviour — but if one assertion failing tells you something different from another, they belong in separate tests.

```typescript
// ❌ BAD: two separate behaviours in one test
it("shows a success message and clears the form after submission", async () => {
  render(<ContactForm />);
  await user.type(screen.getByRole("textbox", { name: "Message" }), "Hello");
  await user.click(screen.getByRole("button", { name: "Send" }));

  expect(screen.getByText("Message sent!")).toBeVisible();           // behaviour 1
  expect(screen.getByRole("textbox", { name: "Message" })).toHaveValue(""); // behaviour 2
});

// ✅ GOOD: one behaviour each — multiple assertions are fine when they describe the same thing
it("shows a success message after submission", async () => {
  render(<ContactForm />);
  await user.type(screen.getByRole("textbox", { name: "Message" }), "Hello");
  await user.click(screen.getByRole("button", { name: "Send" }));

  expect(screen.getByText("Message sent!")).toBeVisible();
});

it("clears the form after submission", async () => {
  render(<ContactForm />);
  await user.type(screen.getByRole("textbox", { name: "Message" }), "Hello");
  await user.click(screen.getByRole("button", { name: "Send" }));

  expect(screen.getByRole("textbox", { name: "Message" })).toHaveValue("");
});

// ✅ ALSO FINE: multiple assertions, all describing the same behaviour (what an error state looks like)
it("shows validation errors when the form is submitted empty", async () => {
  render(<ContactForm />);
  await user.click(screen.getByRole("button", { name: "Send" }));

  expect(screen.getByText("Message is required")).toBeVisible();
  expect(screen.getByRole("button", { name: "Send" })).toBeDisabled();
});
```

In Go, inspecting multiple fields of a returned struct is fine — they all describe the shape of the same return value. The line is crossed when you also assert on a side effect (e.g., something was saved, an email was sent) in the same test.

```go
// ❌ BAD: the shape of the return value AND a side effect are two behaviours
func (s *invoiceSuite) Test_Submit_CreatesInvoiceAndNotifiesCustomer() {
    invoice, err := s.service.Submit(s.ctx, submitParams)

    s.NoError(err)
    s.Equal("INV-001", invoice.Number)       // behaviour 1: shape of returned invoice
    s.Equal(99.99, invoice.Total)

    s.mockMailer.AssertEmailSent(s.T())      // behaviour 2: side effect
}

// ✅ GOOD: shape of the return value is one behaviour — assert all fields freely
func (s *invoiceSuite) Test_Submit_ReturnsPopulatedInvoice() {
    invoice, err := s.service.Submit(s.ctx, submitParams)

    s.NoError(err)
    s.Equal("INV-001", invoice.Number)
    s.Equal(99.99, invoice.Total)
    s.Equal(s.customer.ID, invoice.CustomerID)
    s.False(invoice.IssuedAt.IsZero())
}

// ✅ GOOD: side effect gets its own test
func (s *invoiceSuite) Test_Submit_NotifiesCustomer() {
    _, err := s.service.Submit(s.ctx, submitParams)

    s.NoError(err)
    s.mockMailer.AssertEmailSent(s.T())
}
```

---

## Transparent Fakes

Some operations produce output you can't predict or inspect: hashing, encryption, ID generation. A no-op fake (`return "hashed"`) lets you verify the operation was *called*, but not what it was called *with*, and nothing downstream can use it meaningfully.

A transparent fake makes its output a **deterministic, human-readable function of its input**. You can assert on both sides — what went in, and what comes out.

```go
// ❌ NO-OP: you can only verify it was called
func (f *FakeHasher) Hash(value string) string {
    return "hashed" // always the same — useless for assertions
}

// ✅ TRANSPARENT: output encodes the input
func (f *FakeHasher) Hash(value string) string {
    return "hashed:" + value
}

func (f *FakeHasher) Verify(plain, hashed string) bool {
    return "hashed:"+plain == hashed
}
```

Now tests can assert on what was actually hashed, and the full login flow works end-to-end through the fake:

```go
func (s *authSuite) Test_Register_StoresHashedPassword() {
    _, err := s.authService.Register(s.ctx, "user@example.com", "s3cr3t")
    s.NoError(err)

    user, _ := s.userRepo.GetByEmail(s.ctx, "user@example.com")
    s.Equal("hashed:s3cr3t", user.PasswordHash())
}

func (s *authSuite) Test_Login_RejectsWrongPassword() {
    s.authService.Register(s.ctx, "user@example.com", "s3cr3t")

    _, err := s.authService.Login(s.ctx, "user@example.com", "wrongpassword")
    s.ErrorContains(err, "invalid password")
}
```

**An injected clock is already this pattern** — it makes time a deterministic function you control. Apply the same thinking to:

| Operation | No-op fake | Transparent fake |
|---|---|---|
| Hashing | `return "hashed"` | `return "hashed:" + value` |
| Encryption | `return "encrypted"` | `return "encrypted:" + plaintext` |
| ID generation | `return "fake-id"` | `return "fake-id-" + input` |
| Email sending | `return nil` | record sent emails, expose for assertion |

---

## Scenario Layering with Nested Describes

When a behaviour has multiple independent variant dimensions, nest `describe` blocks — one level per dimension. This creates a readable hierarchy and ensures each combination is covered without combinatorial explosion.

```typescript
describe("ApiFormationClient", () => {
  describe("form submission for LLC", () => {
    describe("with STARTING persona", () => {
      it("sends correct POST payload to PrepareFiling endpoint", () => { ... });
      it("includes registered agent fields", () => { ... });
    });

    describe("with OWNING persona", () => {
      it("omits registered agent fields", () => { ... });
    });
  });

  describe("form submission for Corporation", () => {
    describe("with STARTING persona", () => {
      it("sends correct POST payload", () => { ... });
    });
  });
});
```

Pick variant dimensions that are meaningful to the **behaviour**, not to the implementation. Common dimensions: entity type, user role, state (before/after), input validity (valid/invalid/missing).

Don't go deeper than three levels — if you need four, the unit under test is probably doing too much.

---

## Exhaustive Error Enumeration

When a function can fail in multiple distinct ways, give each failure mode its own `it()`. Don't group them under a generic "handles errors" test — each error type is a separate behaviour.

```typescript
// ❌ BAD: groups all error handling together — misses individual failure modes
it("handles errors", () => {
  // tests one error case and calls it done
});

// ✅ GOOD: each named error type is its own test
describe("newsletter subscription", () => {
  it("returns EMAIL_ERROR for an invalid email address", () => { ... });
  it("returns RESPONSE_ERROR when the response is malformed", () => { ... });
  it("returns CONNECTION_ERROR on network failure", () => { ... });
  it("returns TOPIC_ERROR when the subscription topic is missing", () => { ... });
  it("returns QUESTION_WARNING when a preference update fails", () => { ... });
});
```

Forcing yourself to name each error type often reveals error cases you hadn't thought of. If you find yourself writing a test and realising there's no distinct error type for a scenario — go define one.

---

## Resilience / Partial Failure Testing

Test that your system degrades gracefully when a downstream dependency fails. Don't assume the happy path is the only path worth testing end-to-end.

```typescript
// ✅ GOOD: verifies data is not lost when an external call fails
it("persists formation data even when the formation client fails", async () => {
  mockFormationClient.mockRejectedValue(new Error("service unavailable"));

  await request(app).post("/formation").send(validPayload);

  const saved = await db.getFormationData(userId);
  expect(saved).toMatchObject(validPayload);
});
```

When to write resilience tests:
- Any operation that persists data AND calls an external service — verify persistence survives the external failure
- Any operation with a fallback or retry — verify the fallback is exercised
- Any operation that must complete partially — verify the completed portion is durable

---

## Complex Setup Is a Design Smell

If a test requires extensive setup to exercise a single behaviour, the production code is probably too coupled. Listen to the test — hard to test means hard to use.

When setup becomes unwieldy:
- Consider whether the unit under test has too many dependencies
- Consider whether the behaviour belongs at a higher or lower layer
- Extract setup into a named helper only if the complexity is inherent, not if it's masking a design problem

```go
// ❌ BAD: constructing everything inline suggests the service has too many concerns
func TestAccessService_IsAllowed(t *testing.T) {
    db := setupRealDatabase(t)
    cache := setupRedis(t)
    featureFlags := loadFeatureFlags(t)
    auditLog := setupAuditLogger(t)
    blacklist := postgres.NewBlacklistRepository(db, cache)
    svc := services.NewAccessService([]string{"example.com"}, blacklist, featureFlags, auditLog)

    allowed := svc.IsAllowed("user@example.com")
    assert.True(t, allowed)
}

// ✅ GOOD: fake handles all isolation; the test describes only what it cares about
func (s *accessServiceSuite) Test_IsAllowed_MatchingDomain() {
    s.allowedDomains = []string{"example.com"}
    s.initAccessService()

    result := s.accessService.IsAllowed("user@example.com")

    s.True(result)
}
```

If your test setup is longer than the test itself, that's the design telling you something.
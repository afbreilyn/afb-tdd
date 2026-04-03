# Go Test Conventions

## Assertions and Test Structure

- Use testify for assertions (`github.com/stretchr/testify`).
- Prefer testify suites for non-trivial tests.
- Define `ctx := t.Context()` when a `Context` is needed in table-driven or standalone tests.

## Test Suites

Use `SetupSubTest()` alongside `SetupTest()` to reinitialise all dependencies before each `s.Run()` block. Without it, state leaks between subtests.

```go
func (s *myServiceSuite) SetupTest()    { s.init() }
func (s *myServiceSuite) SetupSubTest() { s.init() }

func (s *myServiceSuite) init() {
    s.repo = fakes.NewFakeRepo()
    s.service = services.NewMyService(s.repo)
}
```

## Test Data

Use builder/factory helpers to construct test objects — never raw struct literals. Builders enforce complete objects and accept overrides for only what the test cares about.

```go
// ❌ BAD: raw struct — missing fields cause silent failures
user := &domain.User{Email: "test@example.com"}

// ✅ GOOD: builder with sensible defaults
user := domaintest.NewUnpersistedUser(
    domaintest.WithEmail("blocked@example.com"),
)
```

## Fakes and Contract Tests

Write in-memory fakes that implement the same interface as the real implementation. Every fake must have a shared contract test suite that runs against both the fake and the real implementation.

```go
func RunMyRepoContract(t *testing.T, repo MyRepository) {
    t.Helper()
    t.Run("saves and retrieves", func(t *testing.T) { ... })
}

func TestFakeMyRepo(t *testing.T)     { RunMyRepoContract(t, fakes.NewFakeMyRepo()) }
func TestPostgresMyRepo(t *testing.T) { RunMyRepoContract(t, postgres.NewMyRepo(setupTestDB(t))) }
```

## Transparent Fakes

Make fake output a deterministic function of its input so tests can assert on both sides.

```go
// ❌ NO-OP: can only verify it was called
func (f *FakeHasher) Hash(value string) string { return "hashed" }

// ✅ TRANSPARENT: output encodes the input
func (f *FakeHasher) Hash(value string) string   { return "hashed:" + value }
func (f *FakeHasher) Verify(plain, hashed string) bool { return "hashed:"+plain == hashed }
```

Apply the same pattern to: encryption, ID generation, email sending (record sent emails), etc.

## Time Control

Never call `time.Now()` directly in production code. Inject time via an interface so tests can control it with a frozen clock.

```go
clock.Advance(4 * time.Hour)
```

Initialise the clock in `SetupTest` / `SetupSubTest` so each test starts from a known time.
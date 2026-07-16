Add password authentication to `AccessService` (in `service/access.go`):

- `Register(ctx, email, orgID, password string) error` — stores the user with a hashed password (never the plaintext).
- `Login(ctx, email, password string) (Session, error)` — returns a session on correct credentials; unknown email or wrong password both return an "invalid credentials" error.

Introduce a `Hasher` interface for the hashing, with a real implementation based on `crypto/sha256` (standard library only — no new dependencies). Follow the project's existing patterns for fakes and contract tests.

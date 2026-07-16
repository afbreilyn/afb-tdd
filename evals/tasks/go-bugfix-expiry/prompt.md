Bug report for `AccessService` (in `service/access.go`):

1. A session whose `ExpiresAt` equals the current instant is treated as valid. It should be expired — a session is valid strictly *before* its expiry.
2. The service reads the wall clock (`time.Now()`) directly, which makes the expiry behaviour untestable and flaky in CI. The codebase already has an injectable clock (`clock.Clock` / `clock.FrozenClock`) that the service should use instead.

Fix test-first.

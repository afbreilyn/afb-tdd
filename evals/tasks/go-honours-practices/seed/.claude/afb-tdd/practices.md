# afb-tdd: testing practices

House style for this repo. Where this disagrees with the afb-tdd built-in
conventions, this file wins.

## How we test here

- **Every test function calls `t.Parallel()` as its first statement**, including
  every subtest closure. Tests here must be safe to run concurrently; a test that
  cannot be is a design problem to fix, not an exception to grant.
- **Table-driven subtests use `tc` as the loop variable**, never `tt`, `test`, or
  `x`. Reviewers grep for `tc` when tracing a failing case, and a stray name breaks
  that.
- Build domain values through the builders in `domaintest/`, never struct literals.
- One behaviour per test. A test whose name needs "and" is two tests.

## Gold-standard files

- `service/access_test.go:1` — the shape to copy: parallel, table-driven with `tc`,
  builders for setup, one assertion target per case.

## Known deviations

- `repository/memstore/user_test.go` predates the parallel rule and does not call
  `t.Parallel()`. It is grandfathered, not precedent. Do not copy it.

## Don't imitate this file

`repository/fakes/user_test.go` — asserts on the fake's internals rather than the
contract. Copy `service/access_test.go` instead.

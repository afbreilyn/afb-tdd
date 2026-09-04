# afb-tdd: project profile

## Stack

Go service, standard library plus testify. In-memory and fake repository
implementations behind a shared contract test.

## Commands

- Full suite: `go test ./...`
- Single test: `go test ./path -run TestName`
- Before green, also run: `go vet ./...`

## Architecture: where a feature lives

- `domain/` — entities and value objects; no I/O.
- `domaintest/` — builders for domain values. Test setup goes through these.
- `repository/` — the contract, the in-memory store, and the fake.
- `service/` — business logic over the repository.
- `clock/` — time control; never call `time.Now()` in production code.

## Outside-in slice order for a user-facing feature

1. Service / business-logic test.
2. Repository/persistence test; keep the in-memory fake in sync.

## Commits
- Do not attribute commits to Claude or list it as a co-author.

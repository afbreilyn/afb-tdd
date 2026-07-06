package repository

import (
	"context"
	"errors"

	"evalfixture/domain"
)

var ErrNotFound = errors.New("user not found")

// UserRepository persists users. Implementations: fakes (in-memory) and
// memstore (file-backed). Both must satisfy the shared contract suite in
// repository/contract.
type UserRepository interface {
	Save(ctx context.Context, user *domain.User) (*domain.User, error)
	GetByEmail(ctx context.Context, email string) (*domain.User, error)
}

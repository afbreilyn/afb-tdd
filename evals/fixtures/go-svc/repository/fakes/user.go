package fakes

import (
	"context"

	"evalfixture/domain"
	"evalfixture/repository"
)

// FakeUserRepository is a transparent in-memory implementation: assigned IDs
// are a deterministic function of the input ("user-" + email) so tests can
// assert on both sides.
type FakeUserRepository struct {
	users map[string]*domain.User
}

func NewFakeUserRepository() *FakeUserRepository {
	return &FakeUserRepository{users: make(map[string]*domain.User)}
}

func (r *FakeUserRepository) Save(_ context.Context, user *domain.User) (*domain.User, error) {
	saved := domain.RehydrateUser("user-"+user.Email(), user.Email(), user.OrgID())
	r.users[saved.Email()] = saved
	return saved, nil
}

func (r *FakeUserRepository) GetByEmail(_ context.Context, email string) (*domain.User, error) {
	user, ok := r.users[email]
	if !ok {
		return nil, repository.ErrNotFound
	}
	return user, nil
}

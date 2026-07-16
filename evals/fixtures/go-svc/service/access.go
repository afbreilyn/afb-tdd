package service

import (
	"context"
	"fmt"
	"time"

	"evalfixture/repository"
)

// Session grants access until ExpiresAt.
type Session struct {
	Email     string
	ExpiresAt time.Time
}

type AccessService struct {
	users      repository.UserRepository
	sessionTTL time.Duration
}

func NewAccessService(users repository.UserRepository, sessionTTL time.Duration) *AccessService {
	return &AccessService{users: users, sessionTTL: sessionTTL}
}

func (s *AccessService) GrantSession(ctx context.Context, email string) (Session, error) {
	user, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		return Session{}, fmt.Errorf("granting session: %w", err)
	}
	return Session{
		Email:     user.Email(),
		ExpiresAt: time.Now().Add(s.sessionTTL),
	}, nil
}

func (s *AccessService) IsSessionValid(session Session) bool {
	return !session.ExpiresAt.Before(time.Now())
}

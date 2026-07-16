package service_test

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/suite"

	"evalfixture/domaintest"
	"evalfixture/repository"
	"evalfixture/repository/fakes"
	"evalfixture/service"
)

type accessServiceSuite struct {
	suite.Suite
	ctx     context.Context
	users   *fakes.FakeUserRepository
	service *service.AccessService
}

func TestAccessServiceSuite(t *testing.T) {
	suite.Run(t, new(accessServiceSuite))
}

func (s *accessServiceSuite) SetupTest()    { s.init() }
func (s *accessServiceSuite) SetupSubTest() { s.init() }

func (s *accessServiceSuite) init() {
	s.ctx = context.Background()
	s.users = fakes.NewFakeUserRepository()
	s.service = service.NewAccessService(s.users, time.Hour)
}

func (s *accessServiceSuite) Test_GrantSession_ReturnsSessionForKnownUser() {
	user := domaintest.NewUnpersistedUser(domaintest.WithEmail("known@example.com"))
	_, err := s.users.Save(s.ctx, user)
	s.Require().NoError(err)

	session, err := s.service.GrantSession(s.ctx, "known@example.com")

	s.NoError(err)
	s.Equal("known@example.com", session.Email)
	s.False(session.ExpiresAt.IsZero())
}

func (s *accessServiceSuite) Test_GrantSession_ErrorsForUnknownEmail() {
	_, err := s.service.GrantSession(s.ctx, "stranger@example.com")

	s.ErrorIs(err, repository.ErrNotFound)
}

func (s *accessServiceSuite) Test_IsSessionValid_FutureExpiry() {
	session := service.Session{Email: "known@example.com", ExpiresAt: time.Now().Add(time.Hour)}

	s.True(s.service.IsSessionValid(session))
}

func (s *accessServiceSuite) Test_IsSessionValid_PastExpiry() {
	session := service.Session{Email: "known@example.com", ExpiresAt: time.Now().Add(-time.Hour)}

	s.False(s.service.IsSessionValid(session))
}

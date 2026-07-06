package domaintest

import "evalfixture/domain"

type userConfig struct {
	email string
	orgID string
}

type UserOption func(*userConfig)

func WithEmail(email string) UserOption {
	return func(c *userConfig) { c.email = email }
}

func WithOrgID(orgID string) UserOption {
	return func(c *userConfig) { c.orgID = orgID }
}

// NewUnpersistedUser builds a complete, valid user with sensible defaults.
// Override only what the test cares about.
func NewUnpersistedUser(opts ...UserOption) *domain.User {
	cfg := &userConfig{
		email: "test-user@example.com",
		orgID: "org-1",
	}
	for _, opt := range opts {
		opt(cfg)
	}
	return domain.NewUser(cfg.email, cfg.orgID)
}

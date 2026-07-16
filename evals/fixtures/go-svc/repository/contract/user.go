package contract

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"evalfixture/domaintest"
	"evalfixture/repository"
)

// RunUserRepositoryContract verifies any UserRepository implementation. Run it
// against every fake AND the real implementation so the fake can't drift.
func RunUserRepositoryContract(t *testing.T, repo repository.UserRepository) {
	t.Helper()
	ctx := t.Context()

	t.Run("assigns an id when saving", func(t *testing.T) {
		user := domaintest.NewUnpersistedUser(domaintest.WithEmail("save@example.com"))

		saved, err := repo.Save(ctx, user)

		require.NoError(t, err)
		assert.NotEmpty(t, saved.ID())
	})

	t.Run("retrieves a saved user by email", func(t *testing.T) {
		user := domaintest.NewUnpersistedUser(
			domaintest.WithEmail("contract@example.com"),
			domaintest.WithOrgID("org-42"),
		)
		_, err := repo.Save(ctx, user)
		require.NoError(t, err)

		found, err := repo.GetByEmail(ctx, "contract@example.com")

		require.NoError(t, err)
		assert.Equal(t, "contract@example.com", found.Email())
		assert.Equal(t, "org-42", found.OrgID())
	})

	t.Run("returns ErrNotFound for an unknown email", func(t *testing.T) {
		_, err := repo.GetByEmail(ctx, "nobody@example.com")

		assert.ErrorIs(t, err, repository.ErrNotFound)
	})
}

package memstore_test

import (
	"testing"

	"evalfixture/repository/contract"
	"evalfixture/repository/memstore"
)

func TestMemstoreUserRepository(t *testing.T) {
	contract.RunUserRepositoryContract(t, memstore.NewUserRepository(t.TempDir()))
}

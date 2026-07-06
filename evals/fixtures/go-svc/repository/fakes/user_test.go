package fakes_test

import (
	"testing"

	"evalfixture/repository/contract"
	"evalfixture/repository/fakes"
)

func TestFakeUserRepository(t *testing.T) {
	contract.RunUserRepositoryContract(t, fakes.NewFakeUserRepository())
}

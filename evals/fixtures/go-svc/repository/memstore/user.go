package memstore

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"

	"evalfixture/domain"
	"evalfixture/repository"
)

// UserRepository is the "real" implementation: users persisted as JSON in a
// directory. It exists so the contract suite has a second subject without a
// database.
type UserRepository struct {
	path string
}

func NewUserRepository(dir string) *UserRepository {
	return &UserRepository{path: filepath.Join(dir, "users.json")}
}

type userRecord struct {
	ID    string `json:"id"`
	Email string `json:"email"`
	OrgID string `json:"org_id"`
}

func (r *UserRepository) Save(_ context.Context, user *domain.User) (*domain.User, error) {
	records, err := r.load()
	if err != nil {
		return nil, err
	}
	record := userRecord{ID: "user-" + user.Email(), Email: user.Email(), OrgID: user.OrgID()}
	records[record.Email] = record
	if err := r.store(records); err != nil {
		return nil, err
	}
	return domain.RehydrateUser(record.ID, record.Email, record.OrgID), nil
}

func (r *UserRepository) GetByEmail(_ context.Context, email string) (*domain.User, error) {
	records, err := r.load()
	if err != nil {
		return nil, err
	}
	record, ok := records[email]
	if !ok {
		return nil, repository.ErrNotFound
	}
	return domain.RehydrateUser(record.ID, record.Email, record.OrgID), nil
}

func (r *UserRepository) load() (map[string]userRecord, error) {
	data, err := os.ReadFile(r.path)
	if errors.Is(err, os.ErrNotExist) {
		return make(map[string]userRecord), nil
	}
	if err != nil {
		return nil, err
	}
	records := make(map[string]userRecord)
	if err := json.Unmarshal(data, &records); err != nil {
		return nil, err
	}
	return records, nil
}

func (r *UserRepository) store(records map[string]userRecord) error {
	data, err := json.Marshal(records)
	if err != nil {
		return err
	}
	return os.WriteFile(r.path, data, 0o644)
}

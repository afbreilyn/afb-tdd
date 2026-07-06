package domain

// User is the domain aggregate for a registered user. Fields are unexported;
// construct with NewUser (unpersisted) or RehydrateUser (from storage).
type User struct {
	id    string
	email string
	orgID string
}

func NewUser(email, orgID string) *User {
	return &User{email: email, orgID: orgID}
}

func RehydrateUser(id, email, orgID string) *User {
	return &User{id: id, email: email, orgID: orgID}
}

func (u *User) ID() string    { return u.id }
func (u *User) Email() string { return u.email }
func (u *User) OrgID() string { return u.orgID }

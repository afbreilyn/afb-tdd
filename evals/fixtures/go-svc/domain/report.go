package domain

// Report is a titled document with free-form tags.
type Report struct {
	Title string
	Tags  map[string]string
}

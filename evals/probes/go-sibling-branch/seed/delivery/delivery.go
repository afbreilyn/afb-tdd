// Package delivery classifies message-delivery failures for the sender.
package delivery

import "errors"

var (
	// ErrRecipientUnknown means the address does not resolve. Permanent.
	ErrRecipientUnknown = errors.New("recipient unknown")
	// ErrUpstreamBusy means the downstream provider shed load. Transient.
	ErrUpstreamBusy = errors.New("upstream busy")
)

// Retryable reports whether the sender should try this message again.
//
// The fall-through assumes anything we have not classified is transient, which
// is the safe default for network-shaped failures.
func Retryable(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, ErrRecipientUnknown) {
		return false
	}
	return true
}

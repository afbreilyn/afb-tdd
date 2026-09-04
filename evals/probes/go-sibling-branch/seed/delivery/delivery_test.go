package delivery

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestRetryableIsFalseForNoError(t *testing.T) {
	assert.False(t, Retryable(nil))
}

func TestRetryableIsFalseForUnknownRecipient(t *testing.T) {
	assert.False(t, Retryable(ErrRecipientUnknown))
}

func TestRetryableIsTrueForUpstreamBusy(t *testing.T) {
	assert.True(t, Retryable(ErrUpstreamBusy))
}

In `delivery/delivery.go`, add a new classified failure `ErrPayloadTooLarge` ("payload too large").

A payload that is too large will never succeed on retry, so `Retryable` must return false for it.

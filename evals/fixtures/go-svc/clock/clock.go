package clock

import "time"

// Clock abstracts time.Now so tests can control time deterministically.
type Clock interface {
	Now() time.Time
}

type RealClock struct{}

func (RealClock) Now() time.Time { return time.Now() }

// FrozenClock returns a fixed instant until advanced.
type FrozenClock struct {
	now time.Time
}

func NewFrozenClock(now time.Time) *FrozenClock {
	return &FrozenClock{now: now}
}

func (c *FrozenClock) Now() time.Time { return c.now }

func (c *FrozenClock) Advance(d time.Duration) { c.now = c.now.Add(d) }

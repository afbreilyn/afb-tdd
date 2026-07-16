Users report two bugs in `subscribe()` in `src/newsletter.ts`:

1. Email addresses without a dot in the domain, like `a@b`, are accepted. A valid address must have a TLD (e.g. `a@b.co`).
2. Subscribing a second time with the same email and topic shows "unexpected response from the newsletter service". The backend responds to duplicates with HTTP 409 and body `{"error": "already_subscribed"}`; the user should instead get a distinct already-subscribed result with a friendly message.

Fix both, one at a time.

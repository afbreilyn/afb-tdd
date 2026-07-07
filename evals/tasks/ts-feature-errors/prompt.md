Add an `unsubscribe(email: string, topic: string)` function to `src/newsletter.ts`.

The backend method is `newsletter.unsubscribe`, called via POST /api like the existing subscribe flow. It must distinguish each of these outcomes as a named result variant:

- success (the service confirms removal)
- an invalid email address
- an unknown topic
- the service reports the address is not subscribed to that topic (HTTP 404, body `{"error": "not_subscribed"}`)
- network failure

Follow the project's existing conventions and test helpers.

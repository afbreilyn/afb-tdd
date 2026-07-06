import { setupServer } from "msw/node";
import type { RequestHandler } from "msw";

// Creates an MSW server and wires the standard lifecycle hooks.
// Call once per test file; add per-test overrides with server.use(...).
export function startApiServer(...handlers: RequestHandler[]) {
  const server = setupServer(...handlers);

  beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
  afterEach(() => server.resetHandlers());
  afterAll(() => server.close());

  return server;
}

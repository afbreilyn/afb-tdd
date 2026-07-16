import { http, HttpResponse } from "msw";
import { subscribe } from "./newsletter";
import { startApiServer } from "./testing/msw";
import type { ApiRequest } from "./api/client";

const server = startApiServer(
  http.post("/api", async ({ request }) => {
    const body = (await request.json()) as ApiRequest;

    if (body.method === "newsletter.subscribe") {
      return HttpResponse.json({ subscriberId: `sub-${body.params.email}` });
    }
    throw new Error("api mock fallthrough");
  }),
);

describe("subscribe", () => {
  it("returns email_error for an empty email", async () => {
    const result = await subscribe("", "product");

    expect(result).toEqual({ kind: "email_error", message: '"" is not a valid email address' });
  });

  it("returns email_error when the address has no @", async () => {
    const result = await subscribe("not-an-email", "product");

    expect(result.kind).toBe("email_error");
  });

  it("returns topic_error for an unknown topic", async () => {
    const result = await subscribe("reader@example.com", "gossip");

    expect(result).toEqual({ kind: "topic_error", message: '"gossip" is not a known topic' });
  });

  it("returns the subscriber id issued by the service", async () => {
    const result = await subscribe("reader@example.com", "product");

    expect(result).toEqual({ kind: "subscribed", subscriberId: "sub-reader@example.com" });
  });

  it("returns connection_error when the service is unreachable", async () => {
    server.use(http.post("/api", () => HttpResponse.error()));

    const result = await subscribe("reader@example.com", "product");

    expect(result.kind).toBe("connection_error");
  });
});

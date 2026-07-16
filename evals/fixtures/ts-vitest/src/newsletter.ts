import { postApi } from "./api/client";

export const KNOWN_TOPICS = ["product", "engineering", "design"] as const;
export type Topic = (typeof KNOWN_TOPICS)[number];

export type SubscribeResult =
  | { kind: "subscribed"; subscriberId: string }
  | { kind: "email_error"; message: string }
  | { kind: "topic_error"; message: string }
  | { kind: "connection_error"; message: string }
  | { kind: "response_error"; message: string };

export async function subscribe(email: string, topic: string): Promise<SubscribeResult> {
  if (!/^\S+@\S+$/.test(email)) {
    return { kind: "email_error", message: `"${email}" is not a valid email address` };
  }
  if (!KNOWN_TOPICS.includes(topic as Topic)) {
    return { kind: "topic_error", message: `"${topic}" is not a known topic` };
  }

  let body: unknown;
  try {
    body = await postApi("newsletter.subscribe", { email, topic });
  } catch {
    return { kind: "connection_error", message: "could not reach the newsletter service" };
  }

  if (
    typeof body !== "object" ||
    body === null ||
    typeof (body as { subscriberId?: unknown }).subscriberId !== "string"
  ) {
    return { kind: "response_error", message: "unexpected response from the newsletter service" };
  }
  return { kind: "subscribed", subscriberId: (body as { subscriberId: string }).subscriberId };
}

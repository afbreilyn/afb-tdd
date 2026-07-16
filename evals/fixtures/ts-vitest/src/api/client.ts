export interface ApiRequest {
  method: string;
  params: Record<string, unknown>;
}

export async function postApi(method: string, params: Record<string, unknown>): Promise<unknown> {
  const response = await fetch("/api", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ method, params } satisfies ApiRequest),
  });
  return response.json();
}

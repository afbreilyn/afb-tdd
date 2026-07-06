export interface Subscriber {
  id: string;
  name: string;
  email: string;
  topics: string[];
}

export const createSubscriber = (overrides: Partial<Subscriber> = {}): Subscriber => ({
  id: "subscriber-1",
  name: "Test Subscriber",
  email: "subscriber@example.com",
  topics: ["product"],
  ...overrides,
});

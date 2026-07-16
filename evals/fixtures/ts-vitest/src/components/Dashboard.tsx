import type { Subscriber } from "../testing/factories";

interface DashboardProps {
  subscribers: Subscriber[];
}

export function Dashboard({ subscribers }: DashboardProps) {
  return (
    <main>
      <h1>Newsletter Dashboard</h1>
      <p>
        {subscribers.length} {subscribers.length === 1 ? "subscriber" : "subscribers"}
      </p>
      <ul aria-label="Subscribers">
        {subscribers.map((subscriber) => (
          <li key={subscriber.id}>
            <span>{subscriber.name}</span>
            <a href={`mailto:${subscriber.email}`}>{subscriber.email}</a>
            <span>{subscriber.topics.join(", ")}</span>
          </li>
        ))}
      </ul>
    </main>
  );
}

import { render, screen } from "@testing-library/react";
import { Dashboard } from "./Dashboard";
import { createSubscriber } from "../testing/factories";

describe("Dashboard", () => {
  it("shows the dashboard heading", () => {
    render(<Dashboard subscribers={[]} />);

    expect(screen.getByRole("heading", { name: "Newsletter Dashboard" })).toBeVisible();
  });

  it("shows the subscriber count", () => {
    const subscribers = [createSubscriber({ id: "s1" }), createSubscriber({ id: "s2" })];

    render(<Dashboard subscribers={subscribers} />);

    expect(screen.getByText("2 subscribers")).toBeVisible();
  });

  it("shows each subscriber's name", () => {
    const subscribers = [
      createSubscriber({ id: "s1", name: "Ada Lovelace" }),
      createSubscriber({ id: "s2", name: "Grace Hopper" }),
    ];

    render(<Dashboard subscribers={subscribers} />);

    expect(screen.getByText("Ada Lovelace")).toBeVisible();
    expect(screen.getByText("Grace Hopper")).toBeVisible();
  });

  it("links each subscriber's email address", () => {
    render(<Dashboard subscribers={[createSubscriber({ email: "ada@example.com" })]} />);

    expect(screen.getByRole("link", { name: "ada@example.com" })).toHaveAttribute(
      "href",
      "mailto:ada@example.com",
    );
  });
});

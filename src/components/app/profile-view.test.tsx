import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { ProfileView } from "./profile-view";

const person = { display_name: "Solomon K", username: "solomon", avatar_path: null, bio: "Hello", expertise: null, interests: [] };
const provider = { headline: "Founder", about: "I build things.", rating_count: 0, rating_sum: 0 };
const offering = { id: "o1", kind: "voice" as const, title: "Founder chat", description: null, duration_minutes: 30, price_minor: 500000 };

// Regression: your own profile used to omit provider information that other people could see.
describe("ProfileView", () => {
  it("shows provider headline, about text and offerings to a visitor", () => {
    render(<ProfileView person={person} provider={provider} offerings={[offering]} />);
    expect(screen.getByText("Founder")).toBeTruthy();
    expect(screen.getByText("I build things.")).toBeTruthy();
    expect(screen.getByText("Founder chat")).toBeTruthy();
    expect(screen.getByText(/Booking opens/)).toBeTruthy();
  });

  it("shows the same provider information to the owner, plus status and a manage link", () => {
    render(
      <ProfileView
        isSelf
        person={person}
        provider={{ ...provider, statusLabel: "Approved" }}
        offerings={[{ ...offering, badge: "Live" }]}
      />,
    );
    expect(screen.getByText("Founder")).toBeTruthy();
    expect(screen.getByText("Founder chat")).toBeTruthy();
    expect(screen.getByText("Live")).toBeTruthy();
    expect(screen.getByText(/Provider · Approved/)).toBeTruthy();
    expect(screen.getByRole("link", { name: "Manage" }).getAttribute("href")).toBe("/create");
    expect(screen.queryByText(/Booking opens/)).toBeNull();
  });

  it("shows no provider section for a non-provider", () => {
    render(<ProfileView person={person} provider={null} offerings={[]} />);
    expect(screen.queryByText("Paid conversations")).toBeNull();
  });
});

import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import Home from "@/app/(marketing)/page";
import { routes } from "@/lib/site";

describe("Home page", () => {
  it("shows the headline as the page's only h1", () => {
    render(<Home />);
    const headings = screen.getAllByRole("heading", { level: 1 });
    expect(headings).toHaveLength(1);
    expect(headings[0]).toHaveTextContent("One conversation can change your perspective.");
  });

  it("sends both calls to action to their routes", () => {
    render(<Home />);
    for (const link of screen.getAllByRole("link", { name: "Explore People" })) {
      expect(link).toHaveAttribute("href", routes.explore);
    }
    for (const link of screen.getAllByRole("link", { name: "Become a Provider" })) {
      expect(link).toHaveAttribute("href", routes.becomeProvider);
    }
  });

  it("explains the three steps in order", () => {
    render(<Home />);
    const steps = within(screen.getByRole("list")).getAllByRole("listitem");
    expect(steps).toHaveLength(3);
    expect(steps[0]).toHaveTextContent("Find someone");
    expect(steps[1]).toHaveTextContent("Book a time");
    expect(steps[2]).toHaveTextContent("Have the conversation");
  });

  it("does not invent testimonials or ratings", () => {
    const { container } = render(<Home />);
    expect(container.textContent).not.toMatch(/★|\bstars?\b|testimonial|\brated\b/i);
  });
});

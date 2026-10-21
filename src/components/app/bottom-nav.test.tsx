import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { BottomNav } from "./bottom-nav";

let pathname = "/discover";
vi.mock("next/navigation", () => ({ usePathname: () => pathname }));

describe("BottomNav", () => {
  it("renders the five tabs and marks the current one", () => {
    pathname = "/discover";
    render(<BottomNav />);
    const links = screen.getAllByRole("link");
    expect(links.map((l) => l.textContent)).toEqual(["Home", "Discover", "Create", "Inbox", "Profile"]);
    expect(screen.getByRole("link", { name: "Discover" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("link", { name: "Home" })).not.toHaveAttribute("aria-current");
  });
  it("shows unread messages on Inbox only when there are some", () => {
    pathname = "/home";
    const { rerender } = render(<BottomNav unread={0} />);
    expect(screen.queryByText(/unread/)).toBeNull();
    rerender(<BottomNav unread={3} />);
    expect(screen.getByText("3 unread")).toBeInTheDocument();
  });
});

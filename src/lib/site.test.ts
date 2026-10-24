import { describe, expect, it } from "vitest";
import { ctaLabels, primaryNav, routes, siteConfig } from "@/lib/site";
describe("siteConfig", () => {
  it("uses the messaging-first product direction", () => {
    expect(siteConfig.headline).toBe("Find your people. Start a conversation.");
    expect(siteConfig.description).toBe("Discover people by name or username, send a message request, and chat privately once they accept.");
  });
  it("uses clear account call-to-action labels", () => {
    expect(ctaLabels.explore).toBe("Get started"); expect(ctaLabels.becomeProvider).toBe("Sign in");
    expect(routes.getStarted).toBe("/register"); expect(routes.signIn).toBe("/login");
  });
});
describe("navigation", () => {
  it("only links to the home page's own sections", () => { for (const item of primaryNav) expect(item.href.startsWith("/#")).toBe(true); });
  it("defines absolute routes", () => { for (const path of Object.values(routes)) expect(path.startsWith("/")).toBe(true); });
});
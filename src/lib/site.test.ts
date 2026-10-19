import { describe, expect, it } from "vitest";
import { ctaLabels, primaryNav, routes, siteConfig } from "@/lib/site";

describe("siteConfig", () => {
  it("uses the agreed headline and supporting message", () => {
    expect(siteConfig.headline).toBe("One conversation can change your perspective.");
    expect(siteConfig.description).toBe(
      "Find people worth talking to. Get advice, explore new perspectives, and learn from real experiences through one-on-one conversations.",
    );
  });

  it("uses the agreed call-to-action labels", () => {
    expect(ctaLabels.explore).toBe("Explore People");
    expect(ctaLabels.becomeProvider).toBe("Become a Provider");
  });
});

describe("navigation", () => {
  it("only links to the home page's own sections", () => {
    for (const item of primaryNav) {
      expect(item.href.startsWith("/#")).toBe(true);
    }
  });

  it("defines absolute routes", () => {
    for (const path of Object.values(routes)) {
      expect(path.startsWith("/")).toBe(true);
    }
  });
});

import { describe, expect, it } from "vitest";
import { activeTab, appTabs, safeNextPath } from "./navigation";

describe("safeNextPath", () => {
  it("allows same-site paths", () => {
    expect(safeNextPath("/discover?q=ada")).toBe("/discover?q=ada");
  });
  it("falls back for anything that could leave the site", () => {
    for (const bad of ["https://evil.test", "//evil.test", "/\\evil.test", "javascript:alert(1)", "discover", "/a\nb", "", null, undefined]) {
      expect(safeNextPath(bad as string | null | undefined)).toBe("/home");
    }
  });
});

describe("tabs", () => {
  it("has the five agreed tabs in order", () => {
    expect(appTabs.map((t) => t.label)).toEqual(["Home", "Discover", "Create", "Inbox", "Profile"]);
  });
  it("maps paths to tabs", () => {
    expect(activeTab("/home")).toBe("home");
    expect(activeTab("/discover")).toBe("discover");
    expect(activeTab("/u/ada")).toBe("discover");
    expect(activeTab("/create")).toBe("create");
    expect(activeTab("/inbox/123")).toBe("inbox");
    expect(activeTab("/me/edit")).toBe("profile");
    expect(activeTab("/login")).toBeNull();
  });
});

import { describe, expect, it } from "vitest";
import { activeTab, appTabs, safeNextPath } from "./navigation";
describe("safeNextPath", () => {
  it("allows same-site paths", () => { expect(safeNextPath("/discover?q=ada")).toBe("/discover?q=ada"); });
  it("falls back to discovery for unsafe destinations", () => {
    for (const bad of ["https://evil.test","//evil.test","/\\evil.test","javascript:alert(1)","discover","/a\nb","",null,undefined]) expect(safeNextPath(bad as string | null | undefined)).toBe("/discover");
  });
});
describe("tabs", () => {
  it("uses messaging-first navigation", () => { expect(appTabs.map((t)=>t.label)).toEqual(["Discover","Requests","Messages","Profile"]); });
  it("maps routes to the right tab", () => {
    expect(activeTab("/home")).toBe("discover"); expect(activeTab("/discover")).toBe("discover"); expect(activeTab("/u/ada")).toBe("discover");
    expect(activeTab("/requests")).toBe("requests"); expect(activeTab("/inbox/123")).toBe("messages"); expect(activeTab("/me/edit")).toBe("profile"); expect(activeTab("/login")).toBeNull();
  });
});
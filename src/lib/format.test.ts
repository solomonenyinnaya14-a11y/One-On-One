import { describe, expect, it } from "vitest";
import { formatCount, formatNaira } from "./format";

describe("format", () => {
  it("formats kobo as naira", () => {
    expect(formatNaira(500000)).toContain("5,000");
    expect(formatNaira(500000)).toContain("₦");
    expect(formatNaira(150)).toContain("1.50");
  });
  it("shortens large counts", () => {
    expect(formatCount(999)).toBe("999");
    expect(formatCount(1200)).toBe("1.2K");
    expect(formatCount(2_000_000)).toBe("2M");
  });
});

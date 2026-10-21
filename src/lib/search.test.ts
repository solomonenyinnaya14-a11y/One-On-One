import { describe, expect, it } from "vitest";
import { sanitizeSearchTerm } from "./search";

describe("sanitizeSearchTerm", () => {
  it("returns an empty string for nothing", () => {
    expect(sanitizeSearchTerm(undefined)).toBe("");
    expect(sanitizeSearchTerm("   ")).toBe("");
  });
  it("strips a leading @ and collapses spaces", () => {
    expect(sanitizeSearchTerm("@ada   lovelace")).toBe("ada lovelace");
  });
  it("removes characters that could change a filter or LIKE pattern", () => {
    const hostile = 'a,b)(c%d_e*f"g\\h';
    expect(sanitizeSearchTerm(hostile)).toBe("a b c d e f g h");
    expect(sanitizeSearchTerm("x),id.neq.0")).not.toMatch(/[,()]/);
  });
  it("limits the length", () => {
    expect(sanitizeSearchTerm("a".repeat(100))).toHaveLength(40);
  });
});

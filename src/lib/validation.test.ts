import { describe, expect, it } from "vitest";
import {
  normalizeUsername,
  parseInterests,
  validateBio,
  validateDisplayName,
  validateEmail,
  validatePassword,
  validateUsername,
} from "./validation";

describe("validateUsername", () => {
  it("accepts 3–30 lowercase letters, numbers and underscores", () => {
    expect(validateUsername("ada_99")).toBeNull();
    expect(validateUsername("a".repeat(30))).toBeNull();
  });
  it("normalises case, spaces and a leading @ before checking", () => {
    expect(normalizeUsername("  @Ada_99 ")).toBe("ada_99");
    expect(validateUsername("  @Ada_99 ")).toBeNull();
  });
  it("rejects too short, too long and bad characters", () => {
    expect(validateUsername("ab")).toMatch(/at least 3/);
    expect(validateUsername("a".repeat(31))).toMatch(/at most 30/);
    expect(validateUsername("ada lovelace")).toMatch(/lowercase/);
    expect(validateUsername("ada-l")).toMatch(/lowercase/);
    expect(validateUsername("")).toMatch(/Choose/);
  });
  it("rejects reserved names", () => {
    expect(validateUsername("admin")).toMatch(/not available/);
    expect(validateUsername("Support")).toMatch(/not available/);
  });
});

describe("other validators", () => {
  it("checks names", () => {
    expect(validateDisplayName("  ")).not.toBeNull();
    expect(validateDisplayName("Ada")).toBeNull();
    expect(validateDisplayName("x".repeat(81))).not.toBeNull();
  });
  it("checks emails", () => {
    expect(validateEmail("")).not.toBeNull();
    expect(validateEmail("nope")).not.toBeNull();
    expect(validateEmail("a@b")).not.toBeNull();
    expect(validateEmail("ada@example.com")).toBeNull();
  });
  it("checks passwords", () => {
    expect(validatePassword("short")).not.toBeNull();
    expect(validatePassword("long enough")).toBeNull();
    expect(validatePassword("x".repeat(73))).not.toBeNull();
  });
  it("limits bios to 500 characters", () => {
    expect(validateBio("x".repeat(500))).toBeNull();
    expect(validateBio("x".repeat(501))).not.toBeNull();
  });
});

describe("parseInterests", () => {
  it("trims, drops blanks and de-duplicates ignoring case", () => {
    expect(parseInterests(" Music, ,music,  Running ,")).toEqual(["Music", "Running"]);
  });
  it("keeps at most 10, each at most 30 characters", () => {
    const many = Array.from({ length: 15 }, (_, i) => `topic${i}`).join(",");
    expect(parseInterests(many)).toHaveLength(10);
    expect(parseInterests("x".repeat(50))[0]).toHaveLength(30);
  });
});

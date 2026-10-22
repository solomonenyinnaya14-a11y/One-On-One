import { describe, expect, it } from "vitest";
import { parseOtpType } from "./otp";

describe("parseOtpType", () => {
  it("accepts known email link types", () => {
    expect(parseOtpType("signup")).toBe("signup");
    expect(parseOtpType("recovery")).toBe("recovery");
    expect(parseOtpType("email")).toBe("email");
  });
  it("rejects anything else", () => {
    expect(parseOtpType("admin")).toBeNull();
    expect(parseOtpType("")).toBeNull();
    expect(parseOtpType(null)).toBeNull();
    expect(parseOtpType(undefined)).toBeNull();
  });
});

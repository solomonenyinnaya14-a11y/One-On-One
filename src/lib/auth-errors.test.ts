import { describe, expect, it } from "vitest";
import { friendlyAuthError } from "./auth-errors";

describe("friendlyAuthError", () => {
  it("never leaks raw errors", () => {
    expect(friendlyAuthError({ message: "boom internal", code: "unexpected" })).toBe("Something went wrong. Please try again.");
    expect(friendlyAuthError(null)).toBe("Something went wrong. Please try again.");
  });
  it("explains the common cases", () => {
    expect(friendlyAuthError({ code: "invalid_credentials" })).toMatch(/don't match/);
    expect(friendlyAuthError({ code: "email_not_confirmed" })).toMatch(/Confirm your email/);
    expect(friendlyAuthError({ code: "user_already_exists" })).toMatch(/already exists/);
    expect(friendlyAuthError({ status: 429 })).toMatch(/Too many/);
  });
});

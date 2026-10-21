import { afterEach, describe, expect, it, vi } from "vitest";
import { avatarUrl, initials, isOwnAvatarPath } from "./avatar";

afterEach(() => vi.unstubAllEnvs());

describe("avatarUrl", () => {
  it("builds the public storage URL", () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://x.supabase.co/");
    expect(avatarUrl("u1/a b.png")).toBe("https://x.supabase.co/storage/v1/object/public/avatars/u1/a%20b.png");
  });
  it("returns null without a path or configuration", () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://x.supabase.co");
    expect(avatarUrl(null)).toBeNull();
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "");
    expect(avatarUrl("u1/a.png")).toBeNull();
  });
});

describe("isOwnAvatarPath", () => {
  it("accepts only files inside the owner's folder", () => {
    expect(isOwnAvatarPath("u1/abc.webp", "u1")).toBe(true);
    expect(isOwnAvatarPath("u2/abc.webp", "u1")).toBe(false);
    expect(isOwnAvatarPath("u1/../u2/abc.png", "u1")).toBe(false);
    expect(isOwnAvatarPath("u1/script.html", "u1")).toBe(false);
  });
});

describe("initials", () => {
  it("uses first and last name", () => {
    expect(initials("ada lovelace")).toBe("AL");
    expect(initials("Ada")).toBe("A");
    expect(initials("  ")).toBe("?");
  });
});

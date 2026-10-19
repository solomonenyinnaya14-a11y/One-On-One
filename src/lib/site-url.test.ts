import { describe, expect, it } from "vitest";
import { getSiteUrl } from "@/lib/site-url";

describe("getSiteUrl", () => {
  it("uses an explicit NEXT_PUBLIC_SITE_URL", () => {
    const url = getSiteUrl({ NEXT_PUBLIC_SITE_URL: "https://oneonone.example" });
    expect(url.origin).toBe("https://oneonone.example");
  });

  it("adds https when the protocol is missing", () => {
    const url = getSiteUrl({ NEXT_PUBLIC_SITE_URL: "oneonone.example" });
    expect(url.origin).toBe("https://oneonone.example");
  });

  it("ignores a malformed value instead of throwing", () => {
    const url = getSiteUrl({ NEXT_PUBLIC_SITE_URL: "https://not a url" });
    expect(url.origin).toBe("http://localhost:3000");
  });

  it("uses the deployment URL on previews", () => {
    const url = getSiteUrl({
      VERCEL_ENV: "preview",
      VERCEL_URL: "one-on-one-git-feat.vercel.app",
      VERCEL_PROJECT_PRODUCTION_URL: "oneonone.example",
    });
    expect(url.origin).toBe("https://one-on-one-git-feat.vercel.app");
  });

  it("uses the production domain on production builds", () => {
    const url = getSiteUrl({
      VERCEL_ENV: "production",
      VERCEL_URL: "one-on-one-abc123.vercel.app",
      VERCEL_PROJECT_PRODUCTION_URL: "oneonone.example",
    });
    expect(url.origin).toBe("https://oneonone.example");
  });

  it("falls back to localhost when nothing is set", () => {
    expect(getSiteUrl({}).origin).toBe("http://localhost:3000");
  });
});

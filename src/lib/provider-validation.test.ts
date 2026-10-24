import { describe, expect, it } from "vitest";
import { nairaToMinor, offeringStatus, parseLanguages, validateOffering } from "./provider-validation";

const good = { kind: "text", title: "Career chat", description: "", duration: "30", price: "5000", topicId: "" };

describe("nairaToMinor", () => {
  it("converts whole and decimal naira", () => {
    expect(nairaToMinor("5000")).toBe(500000);
    expect(nairaToMinor("5,000")).toBe(500000);
    expect(nairaToMinor("₦1500.50")).toBe(150050);
  });
  it("rejects junk and too many decimals", () => {
    expect(nairaToMinor("")).toBeNull();
    expect(nairaToMinor("abc")).toBeNull();
    expect(nairaToMinor("10.555")).toBeNull();
    expect(nairaToMinor("-5")).toBeNull();
  });
});

describe("validateOffering", () => {
  it("accepts a valid offering and converts the price", () => {
    const r = validateOffering(good);
    expect(r.errors).toEqual({});
    expect(r.value).toMatchObject({ kind: "text", priceMinor: 500000, durationMinutes: 30, description: null, topicId: null });
  });
  it("rejects bad kind, title, duration and price", () => {
    const r = validateOffering({ ...good, kind: "video", title: " ", duration: "7", price: "0" });
    expect(Object.keys(r.errors).sort()).toEqual(["duration", "kind", "price", "title"]);
    expect(r.value).toBeNull();
  });
  it("enforces price bounds", () => {
    expect(validateOffering({ ...good, price: "1000001" }).errors.price).toMatch(/highest/);
  });
});

describe("parseLanguages", () => {
  it("trims, dedupes and caps", () => {
    expect(parseLanguages(" English, Yoruba,English ,, ")).toEqual(["English", "Yoruba"]);
    expect(parseLanguages("a,b,c,d,e,f,g,h,i,j,k,l")).toHaveLength(10);
  });
});

describe("offeringStatus", () => {
  const base = { is_active: true, accepts_bookings: true, requires_subscription: false };
  it("reports live, paused, pending approval and lapsed subscription", () => {
    expect(offeringStatus(base, true).label).toBe("Live");
    expect(offeringStatus({ ...base, is_active: false }, true).label).toBe("Paused");
    expect(offeringStatus({ ...base, accepts_bookings: false }, false).label).toBe("Waiting for approval");
    expect(offeringStatus({ ...base, accepts_bookings: false, requires_subscription: true }, true).label).toBe("Needs a subscription");
  });
});

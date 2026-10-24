import { describe, expect, it } from "vitest";
import { fitWithin } from "./image-resize";

describe("fitWithin", () => {
  it("scales a large landscape photo down, keeping the ratio", () => {
    expect(fitWithin(4032, 3024, 640)).toEqual({ width: 640, height: 480 });
  });
  it("scales a large portrait photo down", () => {
    expect(fitWithin(3024, 4032, 640)).toEqual({ width: 480, height: 640 });
  });
  it("never scales a small image up", () => {
    expect(fitWithin(200, 100, 640)).toEqual({ width: 200, height: 100 });
  });
  it("handles invalid sizes", () => {
    expect(fitWithin(0, 100, 640)).toEqual({ width: 0, height: 0 });
  });
});

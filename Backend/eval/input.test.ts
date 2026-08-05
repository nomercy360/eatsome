import sharp from "sharp";
import { describe, expect, it } from "vitest";
import { MODEL_INPUT_VERSION, readPhoto } from "./harness";

describe("eval model input", () => {
  it("uses the app's versioned 1024px JPEG boundary", async () => {
    const input = await readPhoto("IMG_3128.jpeg");
    const metadata = await sharp(Buffer.from(input.base64, "base64")).metadata();
    expect(input.inputVersion).toBe(MODEL_INPUT_VERSION);
    expect(input.mimeType).toBe("image/jpeg");
    expect(Math.max(metadata.width ?? 0, metadata.height ?? 0)).toBe(1024);
    expect(input.hash).toMatch(/^[a-f0-9]{64}$/);
  });
});

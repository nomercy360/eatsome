import { describe, expect, it } from "vitest";
import { decodeBase64Image, encodeBase64Image, sha256Hex } from "./image";

describe("recognition image input", () => {
  it("decodes base64 and computes the content hash", async () => {
    const bytes = decodeBase64Image(btoa("abc"));
    await expect(sha256Hex(bytes)).resolves.toBe(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
  });

  it("round-trips binary data in chunks", () => {
    const bytes = Uint8Array.from({ length: 70_000 }, (_, index) => index % 251);
    expect(decodeBase64Image(encodeBase64Image(bytes))).toEqual(bytes);
  });
});

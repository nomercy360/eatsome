import { describe, expect, it } from "vitest";
import { inputFingerprint } from "./recognitions";

const photoHash = "a".repeat(64);

describe("recognition cache fingerprint", () => {
  it("keys a bare photograph on its own hash, as every existing row does", async () => {
    expect(await inputFingerprint({ photoHash })).toBe(photoHash);
    expect(await inputFingerprint({ photoHash: photoHash.toUpperCase() })).toBe(photoHash);
  });

  it("covers the text of a meal that has no photograph", async () => {
    // The silent, data-corrupting failure this guards against: with no photo
    // hash in play, two different typed meals hashing to the same fingerprint
    // would replay one person's lentil soup as their oatmeal — a cache hit that
    // looks exactly like a recognition.
    const soup = await inputFingerprint({ said: "leftover lentil soup, big bowl" });
    const oats = await inputFingerprint({ said: "oatmeal with a banana" });
    expect(soup).not.toBe(oats);
    expect(soup).toMatch(/^[a-f0-9]{64}$/);
  });

  it("replays the same words as the same question", async () => {
    const first = await inputFingerprint({ said: "leftover lentil soup" });
    const again = await inputFingerprint({ said: "  leftover lentil soup  " });
    expect(again).toBe(first);
  });

  it("keeps a caption and a note apart, even with identical text", async () => {
    // The prompt frames them differently, so the same words are a different
    // question depending on which field carried them.
    const asMessage = await inputFingerprint({ photoHash, said: "fried in butter" });
    const asNote = await inputFingerprint({ photoHash, note: "fried in butter" });
    expect(asMessage).not.toBe(asNote);
  });

  it("makes a captioned photo a different question from the photo alone", async () => {
    const bare = await inputFingerprint({ photoHash });
    const captioned = await inputFingerprint({ photoHash, said: "2 of this at 11 am" });
    expect(captioned).not.toBe(bare);
  });

  it("never lets a typed meal collide with a photographed one", async () => {
    const typed = await inputFingerprint({ said: photoHash });
    expect(typed).not.toBe(photoHash);
  });
});

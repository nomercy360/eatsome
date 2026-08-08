import { describe, expect, it } from "vitest";
import { privacyPage } from "./privacy";

const get = (path: string) => privacyPage(new Request(`https://eatsome-api.example${path}`));

describe("privacy policy page", () => {
  it("is served as a page, and only at /privacy", () => {
    expect(get("/privacy")?.status).toBe(200);
    expect(get("/privacy/")?.status).toBe(200);
    expect(get("/api/health")).toBeNull();
    expect(get("/")).toBeNull();
  });

  it("is HTML a browser and a reviewer can read", async () => {
    const response = get("/privacy");
    expect(response?.headers.get("content-type")).toContain("text/html");
    await expect(response?.text()).resolves.toContain("<!doctype html>");
  });

  // The reason the page exists. A policy that omits the health claim or the
  // third-party disclosure is the one App Review asks about, and each of these
  // is a statement the app has to keep true.
  it("makes the disclosures the app is judged on", async () => {
    // Collapsed first: the claims are sentences, and a sentence in the source
    // is wrapped wherever the line ran out. Matching the raw HTML would make
    // this test fail on a reflow that changed no word.
    const text = ((await get("/privacy")?.text()) ?? "").replace(/\s+/g, " ");
    for (const claim of [
      "never written back to Health",
      "consent screen",
      "Delete all cloud data",
      "no third-party SDKs",
      "maximkadocnikov@gmail.com",
    ]) {
      expect(text).toContain(claim);
    }
  });
});

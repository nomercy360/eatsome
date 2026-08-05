import { describe, expect, it } from "vitest";
import type { Env } from "../env";
import { corpusKey } from "./corpus";
import { ensureMediaObject, mediaKey, mediaPrefix } from "./media";

function storageEnv() {
  type Row = {
    accountId: string;
    photoHash: string;
    objectKey: string;
    mimeType: string;
    byteSize: number;
    createdAt: string;
    storedAt: string | null;
  };
  const rows = new Map<string, Row>();
  const objects = new Map<string, Uint8Array>();
  let puts = 0;
  const DB = {
    prepare(sql: string) {
      return {
        bind(...values: unknown[]) {
          return {
            async first() {
              if (!sql.includes("FROM media_objects")) return null;
              return rows.get(`${values[0]}:${values[1]}`) ?? null;
            },
            async run() {
              if (sql.includes("INSERT OR IGNORE INTO media_objects")) {
                const [accountId, photoHash, objectKey, mimeType, byteSize, createdAt] = values as [
                  string,
                  string,
                  string,
                  string,
                  number,
                  string,
                ];
                const id = `${accountId}:${photoHash}`;
                if (!rows.has(id)) {
                  rows.set(id, {
                    accountId,
                    photoHash,
                    objectKey,
                    mimeType,
                    byteSize,
                    createdAt,
                    storedAt: null,
                  });
                }
              }
              if (sql.includes("UPDATE media_objects SET stored_at")) {
                const [storedAt, accountId, photoHash] = values as [string, string, string];
                const row = rows.get(`${accountId}:${photoHash}`);
                if (row) row.storedAt = storedAt;
              }
              return { meta: { changes: 1 } };
            },
          };
        },
      };
    },
  };
  const MEDIA = {
    async head(key: string) {
      return objects.has(key) ? ({ key } as R2Object) : null;
    },
    async put(key: string, value: Uint8Array) {
      puts += 1;
      objects.set(key, new Uint8Array(value));
      return { key } as R2Object;
    },
  };
  return {
    env: { DB, MEDIA } as unknown as Env,
    objects,
    puts: () => puts,
  };
}

describe("R2 object layout", () => {
  it("partitions private media by account for bounded account deletion", () => {
    const account = "device:0198F222AADB7E008000ABCDEF01";
    expect(mediaPrefix(account)).toBe("media/device%3A0198F222AADB7E008000ABCDEF01/");
    expect(mediaKey(account, "a".repeat(64), "image/jpeg", new Date("2026-08-05T00:00:00Z"))).toBe(
      `media/device%3A0198F222AADB7E008000ABCDEF01/2026-08/${"a".repeat(64)}.jpg`,
    );
  });

  it("content-addresses the corpus by the crop bytes, not source bytes", () => {
    expect(corpusKey("b".repeat(64))).toBe(`corpus/${"b".repeat(64)}.jpg`);
  });

  it("writes the exact model input once and repairs from the D1 reservation", async () => {
    const fake = storageEnv();
    const bytes = new Uint8Array([1, 2, 3, 4]);
    const first = await ensureMediaObject(
      fake.env,
      "device:phone",
      "a".repeat(64),
      "image/jpeg",
      bytes,
      new Date("2026-08-05T00:00:00Z"),
    );
    const second = await ensureMediaObject(
      fake.env,
      "device:phone",
      "a".repeat(64),
      "image/jpeg",
      bytes,
      new Date("2026-09-05T00:00:00Z"),
    );

    expect(second.objectKey).toBe(first.objectKey);
    expect(fake.puts()).toBe(1);
    expect(fake.objects.get(first.objectKey)).toEqual(bytes);
  });
});

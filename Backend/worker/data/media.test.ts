import { describe, expect, it } from "vitest";
import type { IngestEventsRequest } from "../../src/contracts";
import type { Env } from "../env";
import { ensureMediaObject, mealFrom, mediaKey, mediaPrefix, projectMealMedia } from "./media";

const composition = {
  protein: 4.5,
  fat: 3.2,
  carbohydrate: 12.1,
  kcal: 95,
  sodium_mg: 210,
  alcohol: 0,
  caffeine_mg: 0,
};

/** `MealEntry` as EatsomeCore's `JSONEncoder` writes it. See `contracts.test.ts`. */
function swiftMeal(id: string, photoHash: string | null) {
  return {
    id,
    schemaVersion: 1,
    eatenAt: 1_754_300_000_000,
    dishes: [
      {
        id: "0198F222-AADB-7E00-8000-0000000000AA",
        name: "rice",
        count: 1,
        items: [
          {
            id: "0198F222-AADB-7E00-8000-0000000000BB",
            label: "white rice",
            preparation: ["boiled"],
            grams: 180,
            per_100g: composition,
            provenance: {
              protein: "model",
              fat: "model",
              carbohydrate: "model",
              kcal: "model",
              sodium: "model",
              alcohol: "model",
              caffeine: "model",
            },
            alternatives: [],
            sizes: [],
          },
        ],
      },
    ],
    source: photoHash ? "photo" : "text",
    ...(photoHash ? { photoHash } : {}),
    wasCorrected: false,
  };
}

function event(
  kind: "meal_logged" | "meal_deleted",
  data: unknown,
  recordedAt = 1_700_000_000_100,
): IngestEventsRequest["events"][number] {
  return {
    id: "0198F333-AADB-7E00-8000-ABCDEF012345",
    occurredAt: recordedAt - 100,
    recordedAt,
    payload: { kind, data } as IngestEventsRequest["events"][number]["payload"],
  };
}

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
  return { env: { DB, MEDIA } as unknown as Env, objects, puts: () => puts };
}

function deletionEnv(account: string, mealId: string, photoHash: string) {
  const objectKey = `media/${account}/2026-08/${photoHash}.jpg`;
  const mealState = new Map<string, string | null>([[`${account}:${mealId}`, photoHash]]);
  const media = new Map([
    [
      `${account}:${photoHash}`,
      {
        accountId: account,
        photoHash,
        objectKey,
        mimeType: "image/jpeg",
        byteSize: 4,
        createdAt: "2026-08-01T00:00:00Z",
        storedAt: "2026-08-01T00:00:01Z",
      },
    ],
  ]);
  const deletedObjects: string[] = [];
  const DB = {
    prepare(sql: string) {
      return {
        bind(...values: unknown[]) {
          return {
            async first() {
              if (sql.includes("SELECT photo_hash AS photoHash FROM meal_media")) {
                const value = mealState.get(`${values[0]}:${values[1]}`);
                return value === undefined ? null : { photoHash: value };
              }
              if (sql.includes("SELECT 1 AS used FROM meal_media")) {
                return [...mealState.entries()].some(
                  ([key, value]) => key.startsWith(`${values[0]}:`) && value === values[1],
                )
                  ? { used: 1 }
                  : null;
              }
              if (sql.includes("FROM media_objects")) {
                return media.get(`${values[0]}:${values[1]}`) ?? null;
              }
              return null;
            },
            async run() {
              if (sql.includes("INSERT INTO meal_media")) {
                const [account, id, hash] = values as [string, string, string | null];
                mealState.set(`${account}:${id}`, hash);
              }
              if (sql.includes("DELETE FROM media_objects")) {
                media.delete(`${values[0]}:${values[1]}`);
              }
              return { meta: { changes: 1 } };
            },
          };
        },
      };
    },
  };
  const MEDIA = {
    async delete(key: string) {
      deletedObjects.push(key);
    },
  };
  return { env: { DB, MEDIA } as unknown as Env, objectKey, mealState, media, deletedObjects };
}

describe("R2 object layout", () => {
  it("partitions private media by account for bounded account deletion", () => {
    const account = "acct:0198F222AADB7E008000ABCDEF01";
    expect(mediaPrefix(account)).toBe("media/acct%3A0198F222AADB7E008000ABCDEF01/");
    expect(mediaKey(account, "a".repeat(64), "image/jpeg", new Date("2026-08-05T00:00:00Z"))).toBe(
      `media/acct%3A0198F222AADB7E008000ABCDEF01/2026-08/${"a".repeat(64)}.jpg`,
    );
  });

  it("writes the exact model input once and repairs from the D1 reservation", async () => {
    const fake = storageEnv();
    const bytes = new Uint8Array([1, 2, 3, 4]);
    const first = await ensureMediaObject(
      fake.env,
      "acct:one",
      "a".repeat(64),
      "image/jpeg",
      bytes,
      new Date("2026-08-05T00:00:00Z"),
    );
    const second = await ensureMediaObject(
      fake.env,
      "acct:one",
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

describe("projecting meals into media references", () => {
  const mealId = "0198F222-AADB-7E00-8000-ABCDEF012345";
  const photoHash = "a".repeat(64);

  it("releases the photograph a deletion tombstone supersedes", async () => {
    const fake = deletionEnv("acct:one", mealId, photoHash);
    await projectMealMedia(fake.env, "acct:one", [event("meal_deleted", { mealID: mealId })]);

    expect(fake.mealState.get(`acct:one:${mealId}`)).toBeNull();
    expect(fake.media.has(`acct:one:${photoHash}`)).toBe(false);
    expect(fake.deletedObjects).toEqual([fake.objectKey]);
  });

  it("refuses a meal it cannot read, loudly, rather than skipping it", async () => {
    // The failure this replaced was silent and cost real photographs: a
    // `safeParse` that failed here wrote no `meal_media` row, sync reported
    // success, and `deleteOrphanMedia` deleted the picture a day later as an
    // abandoned upload. A skipped meal is as wrong as a rejected one and says
    // nothing, so it is rejected — with the failing field in the message.
    const fake = deletionEnv("acct:one", mealId, photoHash);
    const { schemaVersion: _gone, ...unversioned } = swiftMeal(mealId, photoHash);

    await expect(
      projectMealMedia(fake.env, "acct:one", [event("meal_logged", unversioned)]),
    ).rejects.toMatchObject({ status: 400 });
    // And the picture is still there, because nothing was written.
    expect(fake.media.has(`acct:one:${photoHash}`)).toBe(true);
  });

  it("names the field that is wrong", () => {
    const meal = swiftMeal(mealId, photoHash) as Record<string, unknown>;
    meal.recognitionEvidence = { promptVersion: "meal-v27" };
    expect(() => mealFrom(event("meal_logged", meal))).toThrow(/recognitionEvidence/);
  });

  it("stores the photo a meal references, and reads a text meal as having none", async () => {
    const fake = deletionEnv("acct:one", mealId, photoHash);
    await projectMealMedia(fake.env, "acct:one", [
      event("meal_logged", swiftMeal(mealId, photoHash)),
    ]);
    expect(fake.mealState.get(`acct:one:${mealId}`)).toBe(photoHash);

    // Revised into a meal with no photograph: the old reference is released.
    await projectMealMedia(fake.env, "acct:one", [
      event("meal_logged", swiftMeal(mealId, null), 1_700_000_000_200),
    ]);
    expect(fake.mealState.get(`acct:one:${mealId}`)).toBeNull();
    expect(fake.deletedObjects).toEqual([fake.objectKey]);
  });
});

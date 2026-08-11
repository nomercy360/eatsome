import { describe, expect, it } from "vitest";
import {
  createPostRequestSchema,
  createTableRequestSchema,
  tableFeedQuerySchema,
  tablesListQuerySchema,
  updateTableNoteRequestSchema,
} from "../../src/contracts";
import type { Env } from "../env";
import {
  deleteTablesData,
  newInviteCode,
  postMediaKey,
  redactTableShare,
  tableMediaPrefix,
  tableMembersForCaller,
} from "./tables";

describe("invite codes", () => {
  it("are ten characters from the unambiguous alphabet", () => {
    for (let round = 0; round < 20; round += 1) {
      const code = newInviteCode();
      expect(code).toHaveLength(10);
      expect(code).toMatch(/^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]+$/);
    }
  });

  it("do not repeat", () => {
    const codes = new Set(Array.from({ length: 50 }, () => newInviteCode()));
    expect(codes.size).toBe(50);
  });
});

describe("table privacy and notes", () => {
  const create = {
    id: "11111111-2222-4333-8444-555555555555",
    name: "Flat dinners",
    displayName: "You",
  };

  it("keeps old clients private by default", () => {
    expect(createTableRequestSchema.parse(create).visibility).toEqual({
      photos: true,
      nutrition: false,
      bodyAndGoals: false,
    });
  });

  it("accepts an explicit per-member boundary", () => {
    const visibility = { photos: false, nutrition: true, bodyAndGoals: false };
    expect(createTableRequestSchema.parse({ ...create, visibility }).visibility).toEqual(
      visibility,
    );
  });

  it("allows one note to be replaced or removed", () => {
    expect(updateTableNoteRequestSchema.parse({ note: "  still warm  " }).note).toBe("still warm");
    expect(updateTableNoteRequestSchema.parse({ note: null }).note).toBeNull();
    expect(
      updateTableNoteRequestSchema.safeParse({ note: "x", replyToPostId: create.id }).success,
    ).toBe(false);
  });

  it("enforces the member boundary even when a client sends private fields", () => {
    const share = createPostRequestSchema.parse({
      id: "11111111-2222-4333-8444-555555555556",
      kind: "share",
      mealId: "99999999-2222-4333-8444-555555555555",
      dishName: "Salmon bowl",
      caption: null,
      ingredients: [{ group: "fish", grams: 140, label: "salmon" }],
      photoHash: "a".repeat(64),
    });
    if (share.kind !== "share") throw new Error("Expected a share");

    expect(redactTableShare({ showPhotos: 0, showNutrition: 0 }, share)).toEqual({
      photoHash: null,
      ingredients: null,
    });
    expect(redactTableShare({ showPhotos: 1, showNutrition: 1 }, share)).toEqual({
      photoHash: share.photoHash,
      ingredients: share.ingredients,
    });
  });

  it("shows one seat when anonymous and Apple partitions were merged", () => {
    const members = tableMembersForCaller(
      [
        {
          memberId: "old-device-seat",
          displayName: "Maksim",
          role: "creator",
          accountId: "device:old",
        },
        {
          memberId: "friend-seat",
          displayName: "Mira",
          role: "member",
          accountId: "acct:friend",
        },
        {
          memberId: "apple-seat",
          displayName: "You",
          role: "member",
          accountId: "acct:apple",
        },
      ],
      ["acct:apple", "device:old"],
    );

    expect(members).toHaveLength(2);
    expect(members.filter((member) => member.isMe)).toEqual([
      {
        memberId: "old-device-seat",
        displayName: "Maksim",
        role: "creator",
        isMe: true,
      },
    ]);
  });
});

describe("shared photo keys", () => {
  it("embed the table and the post, never an account", () => {
    const key = postMediaKey("11111111-2222-4333-8444-555555555555", "post-1", "image/jpeg");
    expect(key).toBe("tables/11111111-2222-4333-8444-555555555555/media/post-1.jpg");
    expect(key).not.toContain("device:");
    expect(key).not.toContain("acct:");
  });

  it("keep every table's objects under one deletable prefix", () => {
    const prefix = tableMediaPrefix("t-1");
    expect(postMediaKey("t-1", "p-1", "image/png").startsWith(prefix)).toBe(true);
    expect(postMediaKey("t-1", "p-2", "image/webp").startsWith(prefix)).toBe(true);
  });
});

describe("the share contract is the redaction", () => {
  const share = {
    id: "11111111-2222-4333-8444-555555555555",
    kind: "share" as const,
    mealId: "99999999-2222-4333-8444-555555555555",
    dishName: "Blueberry buns",
    caption: "still warm",
    ingredients: [{ group: "pastry", grams: 120, label: "sweet dough" }],
    photoHash: "a".repeat(64),
  };

  it("accepts exactly what the share sheet shows", () => {
    expect(createPostRequestSchema.parse(share)).toMatchObject({ kind: "share" });
  });

  it("rejects anything from the private half of the log", () => {
    // The fields a reference-based post would have leaked one by one. A strict
    // object refuses them at the door, which is the whole point of the copy.
    for (const leak of [
      { olives: 4 },
      { note: "fried in butter" },
      { recognitionEvidence: {} },
      { share: "part" },
    ]) {
      expect(createPostRequestSchema.safeParse({ ...share, ...leak }).success).toBe(false);
    }
  });

  it("rejects ingredient fields beyond group, grams and label", () => {
    for (const extra of [{ portion: "large" }, { alternatives: ["fish"] }, { servings: 2 }]) {
      const leaked = { ...share, ingredients: [{ ...share.ingredients[0], ...extra }] };
      expect(createPostRequestSchema.safeParse(leaked).success).toBe(false);
    }
  });

  it("takes a message with or without a reply target", () => {
    const message = {
      id: "11111111-2222-4333-8444-555555555556",
      kind: "message" as const,
      text: "recipe?? they look unreal",
      replyToPostId: null,
    };
    expect(createPostRequestSchema.parse(message).kind).toBe("message");
    expect(createPostRequestSchema.parse({ ...message, replyToPostId: share.id }).kind).toBe(
      "message",
    );
    expect(createPostRequestSchema.safeParse({ ...message, text: "  " }).success).toBe(false);
  });
});

describe("query boundaries stay the caller's", () => {
  it("coerces since but never invents one", () => {
    expect(tablesListQuerySchema.parse({ since: "1754800000000" }).since).toBe(1_754_800_000_000);
    expect(tablesListQuerySchema.parse({}).since).toBeUndefined();
  });

  it("pages the feed by seq with a bounded limit", () => {
    const query = tableFeedQuerySchema.parse({ cursor: "42", limit: "50" });
    expect(query.cursor).toBe(42);
    expect(query.limit).toBe(50);
    expect(tableFeedQuerySchema.safeParse({ limit: "500" }).success).toBe(false);
  });
});

/**
 * Account erasure across the social tables, against a fake D1/R2 pair. The
 * promise under test is the shipped one: "delete my cloud data" removes every
 * authored post's bytes from R2, every row the partitions own, and any table
 * left standing empty.
 */
function socialEnv() {
  type Post = { id: string; tableId: string; authorAccount: string; objectKey: string | null };
  type Member = { tableId: string; accountId: string };
  const state = {
    posts: [
      {
        id: "p1",
        tableId: "t1",
        authorAccount: "device:gone",
        objectKey: "tables/t1/media/p1.jpg",
      },
      { id: "p2", tableId: "t1", authorAccount: "device:stays", objectKey: null },
      { id: "p3", tableId: "t2", authorAccount: "acct:gone", objectKey: "tables/t2/media/p3.jpg" },
    ] as Post[],
    members: [
      { tableId: "t1", accountId: "device:gone" },
      { tableId: "t1", accountId: "device:stays" },
      { tableId: "t2", accountId: "acct:gone" },
    ] as Member[],
    reactions: [
      { postId: "p2", accountId: "device:gone" },
      { postId: "p1", accountId: "device:stays" },
    ],
    tables: ["t1", "t2"],
    deletedObjects: [] as string[],
  };

  function run(sql: string, values: unknown[]) {
    if (sql.includes("DELETE FROM table_reactions WHERE post_id IN")) {
      state.reactions = state.reactions.filter((r) => !values.includes(r.postId));
    } else if (sql.includes("DELETE FROM table_reactions WHERE account_id IN")) {
      state.reactions = state.reactions.filter((r) => !values.includes(r.accountId));
    } else if (sql.includes("DELETE FROM table_reactions")) {
      state.reactions = state.reactions.filter((r) => r.postId !== values[0]);
    } else if (sql.includes("DELETE FROM table_posts WHERE id IN")) {
      state.posts = state.posts.filter((p) => !values.includes(p.id));
    } else if (sql.includes("DELETE FROM table_posts WHERE table_id")) {
      state.posts = state.posts.filter((p) => p.tableId !== values[0]);
    } else if (sql.includes("DELETE FROM table_members WHERE account_id IN")) {
      state.members = state.members.filter((m) => !values.includes(m.accountId));
    } else if (sql.includes("DELETE FROM table_members WHERE table_id")) {
      state.members = state.members.filter((m) => m.tableId !== values[0]);
    } else if (sql.includes("DELETE FROM tables WHERE id")) {
      state.tables = state.tables.filter((t) => t !== values[0]);
    }
    return { meta: { changes: 1 } };
  }

  const DB = {
    prepare(sql: string) {
      return {
        bind(...values: unknown[]) {
          return {
            sql,
            values,
            async all() {
              if (sql.includes("photo_object_key AS objectKey")) {
                return {
                  results: state.posts
                    .filter((p) => values.includes(p.authorAccount))
                    .map((p) => ({ id: p.id, tableId: p.tableId, objectKey: p.objectKey })),
                };
              }
              if (sql.includes("SELECT DISTINCT table_id")) {
                return {
                  results: state.members
                    .filter((m) => values.includes(m.accountId))
                    .map((m) => ({ tableId: m.tableId })),
                };
              }
              return { results: [] };
            },
            async first() {
              if (sql.includes("COUNT(*) AS members")) {
                return {
                  members: state.members.filter((m) => m.tableId === values[0]).length,
                };
              }
              return null;
            },
            async run() {
              return run(sql, values);
            },
          };
        },
      };
    },
    async batch(statements: { sql: string; values: unknown[] }[]) {
      return statements.map((statement) => run(statement.sql, statement.values));
    },
  };

  const MEDIA = {
    async delete(keys: string | string[]) {
      state.deletedObjects.push(...(Array.isArray(keys) ? keys : [keys]));
    },
    async list({ prefix }: { prefix: string }) {
      return {
        objects: state.posts
          .filter((p) => p.objectKey?.startsWith(prefix))
          .map((p) => ({ key: p.objectKey as string })),
      };
    },
  };

  return { env: { DB, MEDIA } as unknown as Env, state };
}

describe("deleteTablesData", () => {
  it("removes authored bytes, owned rows, and any table left empty", async () => {
    const { env, state } = socialEnv();
    const result = await deleteTablesData(env, ["device:gone", "acct:gone"]);

    // Both authored photos are gone from R2 — the promise's sharp edge.
    expect(state.deletedObjects).toContain("tables/t1/media/p1.jpg");
    expect(state.deletedObjects).toContain("tables/t2/media/p3.jpg");
    // The friend's post and their table survive; the account's rows do not.
    expect(state.posts.map((p) => p.id)).toEqual(["p2"]);
    expect(state.members).toEqual([{ tableId: "t1", accountId: "device:stays" }]);
    expect(state.reactions).toEqual([]);
    // t2 stood empty afterwards and was collected; t1 still has a member.
    expect(state.tables).toEqual(["t1"]);
    expect(result.tablesDeleted).toBe(1);
    expect(result.photoObjects).toBe(2);
  });

  it("does nothing for no partitions", async () => {
    const { env, state } = socialEnv();
    await deleteTablesData(env, []);
    expect(state.posts).toHaveLength(3);
    expect(state.deletedObjects).toEqual([]);
  });
});

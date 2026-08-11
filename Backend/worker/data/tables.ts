import type {
  CreatePostRequest,
  PostReactions,
  TableFeedResponse,
  TableMember,
  TablePost,
  TableSummary,
  TablesListResponse,
} from "../../src/contracts";
import { TABLE_MAX_MEMBERS, TABLE_MAX_MEMBERSHIPS_PER_ACCOUNT } from "../../src/contracts";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { uuidV7 } from "../lib/ids";

/**
 * Tables: your log, with friends in it.
 *
 * Two decisions carry everything here, both argued at their definition sites:
 * a post is a *copy* redacted at share time (`src/contracts.ts`), and members
 * are public only as a per-table `member_id` plus a typed display name — never
 * as a partition string, because before sign-in a partition IS a device id and
 * the device id is the key to a person's whole log.
 *
 * Identity follows the accounts milestone's union model rather than fighting
 * it: rows are written under the caller's current partition (`accountId`) and
 * every check that asks "is this row mine" reads `account_id IN (partitions)`,
 * exactly as event reads do. A membership joined anonymously keeps working
 * after sign-in without a single row moving, and there is no rename sweep for
 * a merge to forget.
 */

/** Who is asking. Structurally `Principal` from `data/accounts.ts`, importable
 *  without pulling identity verification into every test that touches a feed. */
export type TableCaller = { accountId: string; partitions: string[] };

/** The one preview line under the day glance: long enough for "Marta: recipe??
 *  they look unreal", short enough that the list endpoint never ships essays. */
const PREVIEW_MAX = 200;

/** No I/L/O/0/1: this code gets read off one phone screen and typed into
 *  another, and a table of six does not need more than 32^10 of keyspace. */
const INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const INVITE_LENGTH = 10;
export const TABLE_INVITE_TTL_MS = 24 * 60 * 60 * 1_000;

export function newInviteCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(INVITE_LENGTH));
  return [...bytes].map((byte) => INVITE_ALPHABET[byte % INVITE_ALPHABET.length]).join("");
}

function placeholders(count: number): string {
  return Array.from({ length: count }, () => "?").join(", ");
}

function extensionFor(mimeType: string): string {
  if (mimeType === "image/png") return "png";
  if (mimeType === "image/webp") return "webp";
  return "jpg";
}

/** Keys embed the table and the post, never an account: membership is the only
 *  ACL, a dead table is one prefix delete, and an account merge renames nothing. */
export function tableMediaPrefix(tableId: string): string {
  return `tables/${encodeURIComponent(tableId)}/`;
}

export function postMediaKey(tableId: string, postId: string, mimeType: string): string {
  return `${tableMediaPrefix(tableId)}media/${postId}.${extensionFor(mimeType)}`;
}

type MemberRow = {
  tableId: string;
  accountId: string;
  memberId: string;
  displayName: string;
  role: string;
  lastReadSeq: number;
  showPhotos: number;
  showNutrition: number;
  showBodyGoals: number;
};

type PostRow = {
  id: string;
  tableId: string;
  seq: number;
  authorAccount: string;
  authorMemberId: string;
  authorName: string;
  kind: string;
  replyToPostId: string | null;
  mealId: string | null;
  dishName: string | null;
  body: string | null;
  ingredientsJson: string | null;
  photoObjectKey: string | null;
  photoMime: string | null;
  createdAt: number;
};

const POST_COLUMNS = `id, table_id AS tableId, seq, author_account AS authorAccount,
       author_member_id AS authorMemberId, author_name AS authorName, kind,
       reply_to_post_id AS replyToPostId, meal_id AS mealId, dish_name AS dishName,
       body, ingredients_json AS ingredientsJson, photo_object_key AS photoObjectKey,
       photo_mime AS photoMime, created_at AS createdAt`;

async function membershipFor(
  database: D1Database,
  tableId: string,
  partitions: string[],
): Promise<MemberRow | null> {
  const rows = await database
    .prepare(
      `SELECT table_id AS tableId, account_id AS accountId, member_id AS memberId,
              display_name AS displayName, role, last_read_seq AS lastReadSeq,
              show_photos AS showPhotos, show_nutrition AS showNutrition,
              show_body_goals AS showBodyGoals
         FROM table_members
        WHERE table_id = ? AND account_id IN (${placeholders(partitions.length)})
        ORDER BY joined_at, member_id`,
    )
    .bind(tableId, ...partitions)
    .all<MemberRow>();
  const first = rows.results[0];
  if (!first) return null;

  // An anonymous membership and an Apple-account membership can both belong
  // to the same caller after account union. Keep one public identity, but
  // combine state conservatively: read position advances, privacy never does.
  const canonical = rows.results.find((row) => row.role === "creator") ?? first;
  return {
    ...canonical,
    lastReadSeq: Math.max(...rows.results.map((row) => row.lastReadSeq)),
    showPhotos: Math.min(...rows.results.map((row) => row.showPhotos)),
    showNutrition: Math.min(...rows.results.map((row) => row.showNutrition)),
    showBodyGoals: Math.min(...rows.results.map((row) => row.showBodyGoals)),
  };
}

/** 404 rather than 403 for a non-member: whether a table id exists is itself
 *  information, and a guessed id should learn nothing. */
async function requireMembership(
  database: D1Database,
  tableId: string,
  partitions: string[],
): Promise<MemberRow> {
  const member = await membershipFor(database, tableId, partitions);
  if (!member) throw new HttpError(404, "No such table for this account.");
  return member;
}

type TableRow = {
  id: string;
  name: string;
  creatorAccount: string;
  inviteCode: string;
  inviteExpiresAt: number;
};

async function tableRow(database: D1Database, tableId: string): Promise<TableRow | null> {
  return database
    .prepare(
      `SELECT id, name, creator_account AS creatorAccount, invite_code AS inviteCode,
              invite_expires_at AS inviteExpiresAt
         FROM tables WHERE id = ?`,
    )
    .bind(tableId)
    .first<TableRow>();
}

/** What the slim row and the feed header both need, for a batch of tables in
 *  one D1 round trip. The unread count and the page it annotates come from the
 *  same snapshot; a client must never rebuild the count from a partial page. */
async function summarize(
  env: Env,
  tables: {
    row: TableRow;
    myLastReadSeq: number;
    visibility: { showPhotos: number; showNutrition: number; showBodyGoals: number };
  }[],
  caller: TableCaller,
  since: number | undefined,
): Promise<TableSummary[]> {
  if (tables.length === 0) return [];
  const parts = caller.partitions;
  const statements = tables.flatMap(({ row, myLastReadSeq }) => [
    env.DB.prepare(
      `SELECT member_id AS memberId, display_name AS displayName, role,
              account_id AS accountId
         FROM table_members WHERE table_id = ? ORDER BY joined_at, member_id`,
    ).bind(row.id),
    env.DB.prepare(
      `SELECT seq, author_name AS authorName, body, dish_name AS dishName,
              created_at AS createdAt
         FROM table_posts WHERE table_id = ? ORDER BY seq DESC LIMIT 1`,
    ).bind(row.id),
    env.DB.prepare(
      `SELECT COUNT(*) AS unread FROM table_posts
        WHERE table_id = ? AND seq > ?
          AND author_account NOT IN (${placeholders(parts.length)})`,
    ).bind(row.id, myLastReadSeq, ...parts),
    env.DB.prepare(
      `SELECT COUNT(*) AS plates, COUNT(DISTINCT author_member_id) AS cooked FROM table_posts
        WHERE table_id = ? AND kind = 'share' AND created_at >= ?`,
    ).bind(row.id, since ?? 0),
    env.DB.prepare(
      `SELECT p.id, p.author_account AS authorAccount, p.author_name AS authorName,
              p.created_at AS createdAt,
              CASE WHEN p.photo_object_key IS NULL THEN 0 ELSE 1 END AS hasPhoto,
              (SELECT COUNT(*) FROM table_reactions AS r WHERE r.post_id = p.id) AS reactionCount
         FROM table_posts AS p
        WHERE p.table_id = ? AND p.kind = 'share'
        ORDER BY p.seq DESC LIMIT 3`,
    ).bind(row.id),
  ]);
  const results = await env.DB.batch(statements);

  return tables.map(({ row, myLastReadSeq, visibility }, index) => {
    const offset = index * 5;
    const memberRows = (results[offset]?.results ?? []) as {
      memberId: string;
      displayName: string;
      role: string;
      accountId: string;
    }[];
    const latestRow = (results[offset + 1]?.results ?? [])[0] as
      | {
          seq: number;
          authorName: string;
          body: string | null;
          dishName: string | null;
          createdAt: number;
        }
      | undefined;
    const unreadRow = (results[offset + 2]?.results ?? [])[0] as { unread: number } | undefined;
    const cookedRow = (results[offset + 3]?.results ?? [])[0] as
      | { cooked: number; plates: number }
      | undefined;
    const recentRows = (results[offset + 4]?.results ?? []) as {
      id: string;
      authorAccount: string;
      authorName: string;
      createdAt: number;
      hasPhoto: number;
      reactionCount: number;
    }[];

    const members = tableMembersForCaller(memberRows, parts);

    const latestText = latestRow ? (latestRow.body ?? latestRow.dishName ?? "") : "";
    return {
      id: row.id,
      name: row.name,
      members,
      inviteCode: row.inviteCode,
      inviteExpiresAt: row.inviteExpiresAt,
      visibility: {
        photos: visibility.showPhotos === 1,
        nutrition: visibility.showNutrition === 1,
        bodyAndGoals: visibility.showBodyGoals === 1,
      },
      unreadCount: unreadRow?.unread ?? 0,
      latestSeq: latestRow?.seq ?? 0,
      myLastReadSeq,
      // Null when the caller did not say where their day starts: the server has
      // no idea where the phone's midnight is, and a count against a made-up
      // UTC boundary would be a number pretending to be a fact.
      cookedToday: since === undefined ? null : (cookedRow?.cooked ?? 0),
      platesToday: since === undefined ? null : (cookedRow?.plates ?? 0),
      recentPlates: recentRows.map((plate) => ({
        id: plate.id,
        authorName: plate.authorName,
        mine: parts.includes(plate.authorAccount),
        createdAt: plate.createdAt,
        hasPhoto: plate.hasPhoto === 1,
        reactionCount: plate.reactionCount,
      })),
      latest: latestRow
        ? {
            authorName: latestRow.authorName,
            text: latestText.slice(0, PREVIEW_MAX),
            createdAt: latestRow.createdAt,
          }
        : null,
    };
  });
}

/** Collapse every partition belonging to the caller into one public seat.
 * Account ids are consumed here and never cross the response boundary. */
export function tableMembersForCaller(
  rows: { memberId: string; displayName: string; role: string; accountId: string }[],
  partitions: string[],
): TableMember[] {
  const mine = rows.filter((row) => partitions.includes(row.accountId));
  const canonicalMine = mine.find((row) => row.role === "creator") ?? mine[0];
  let emittedMine = false;
  const members: TableMember[] = [];

  for (const row of rows) {
    if (!partitions.includes(row.accountId)) {
      members.push({
        memberId: row.memberId,
        displayName: row.displayName,
        role: row.role === "creator" ? "creator" : "member",
        isMe: false,
      });
      continue;
    }
    if (emittedMine || !canonicalMine) continue;
    emittedMine = true;
    members.push({
      memberId: canonicalMine.memberId,
      displayName: canonicalMine.displayName,
      role: mine.some((member) => member.role === "creator") ? "creator" : "member",
      isMe: true,
    });
  }
  return members;
}

async function summaryFor(
  env: Env,
  row: TableRow,
  member: MemberRow,
  caller: TableCaller,
  since?: number,
): Promise<TableSummary> {
  const [summary] = await summarize(
    env,
    [
      {
        row,
        myLastReadSeq: member.lastReadSeq,
        visibility: member,
      },
    ],
    caller,
    since,
  );
  if (!summary) throw new HttpError(500, "Could not read the table back.");
  return summary;
}

export async function createTable(
  env: Env,
  caller: TableCaller,
  input: {
    id: string;
    name: string;
    displayName: string;
    visibility: { photos: boolean; nutrition: boolean; bodyAndGoals: boolean };
  },
  now = Date.now(),
): Promise<TableSummary> {
  await enforceMembershipCeiling(env.DB, caller.partitions);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO tables
        (id, name, creator_account, invite_code, invite_expires_at, created_at)
       VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING`,
    ).bind(input.id, input.name, caller.accountId, newInviteCode(), now + TABLE_INVITE_TTL_MS, now),
    env.DB.prepare(
      `INSERT INTO table_members
        (table_id, account_id, member_id, display_name, role, joined_at, last_read_seq,
         show_photos, show_nutrition, show_body_goals)
       VALUES (?, ?, ?, ?, 'creator', ?, 0, ?, ?, ?)
       ON CONFLICT(table_id, account_id) DO NOTHING`,
    ).bind(
      input.id,
      caller.accountId,
      uuidV7(now),
      input.displayName,
      now,
      input.visibility.photos ? 1 : 0,
      input.visibility.nutrition ? 1 : 0,
      input.visibility.bodyAndGoals ? 1 : 0,
    ),
  ]);

  // The id is client-generated so a retried create is the same table — but the
  // same id sent by a *different* account is a collision, not a retry, and the
  // membership insert above will have silently attached them to a stranger's
  // table. Undo it and refuse.
  const row = await tableRow(env.DB, input.id);
  if (!row) throw new HttpError(500, "Could not create the table.");
  if (!caller.partitions.includes(row.creatorAccount)) {
    await env.DB.prepare("DELETE FROM table_members WHERE table_id = ? AND account_id = ?")
      .bind(input.id, caller.accountId)
      .run();
    throw new HttpError(409, "That table id already belongs to someone else.");
  }
  const member = await requireMembership(env.DB, input.id, caller.partitions);
  return summaryFor(env, row, member, caller);
}

async function enforceMembershipCeiling(database: D1Database, partitions: string[]): Promise<void> {
  const row = await database
    .prepare(
      `SELECT COUNT(DISTINCT table_id) AS memberships FROM table_members
        WHERE account_id IN (${placeholders(partitions.length)})`,
    )
    .bind(...partitions)
    .first<{ memberships: number }>();
  if ((row?.memberships ?? 0) >= TABLE_MAX_MEMBERSHIPS_PER_ACCOUNT) {
    throw new HttpError(409, "This account is at its table limit.");
  }
}

export async function joinTable(
  env: Env,
  caller: TableCaller,
  input: { code: string; displayName: string },
  now = Date.now(),
): Promise<TableSummary> {
  const row = await env.DB.prepare(
    `SELECT id, name, creator_account AS creatorAccount, invite_code AS inviteCode,
            invite_expires_at AS inviteExpiresAt
       FROM tables WHERE invite_code = ?`,
  )
    .bind(input.code.toUpperCase())
    .first<TableRow>();
  if (!row) throw new HttpError(404, "No table answers to that code.");
  if (row.inviteExpiresAt <= now) throw new HttpError(410, "That invite link has expired.");

  const existing = await membershipFor(env.DB, row.id, caller.partitions);
  if (existing) return summaryFor(env, row, existing, caller);

  await enforceMembershipCeiling(env.DB, caller.partitions);
  const seated = await env.DB.prepare(
    "SELECT COUNT(*) AS members FROM table_members WHERE table_id = ?",
  )
    .bind(row.id)
    .first<{ members: number }>();
  if ((seated?.members ?? 0) >= TABLE_MAX_MEMBERS) {
    throw new HttpError(409, "That table is full.");
  }

  await env.DB.prepare(
    `INSERT INTO table_members
      (table_id, account_id, member_id, display_name, role, joined_at, last_read_seq)
     VALUES (?, ?, ?, ?, 'member', ?, 0)
     ON CONFLICT(table_id, account_id) DO NOTHING`,
  )
    .bind(row.id, caller.accountId, uuidV7(now), input.displayName, now)
    .run();
  const member = await requireMembership(env.DB, row.id, caller.partitions);
  return summaryFor(env, row, member, caller);
}

export async function listTables(
  env: Env,
  caller: TableCaller,
  since: number | undefined,
): Promise<TablesListResponse> {
  const rows = await env.DB.prepare(
    `SELECT t.id, t.name, t.creator_account AS creatorAccount, t.invite_code AS inviteCode,
            t.invite_expires_at AS inviteExpiresAt,
            MAX(m.last_read_seq) AS lastReadSeq, MIN(m.show_photos) AS showPhotos,
            MIN(m.show_nutrition) AS showNutrition, MIN(m.show_body_goals) AS showBodyGoals
       FROM table_members AS m JOIN tables AS t ON t.id = m.table_id
      WHERE m.account_id IN (${placeholders(caller.partitions.length)})
      GROUP BY t.id, t.name, t.creator_account, t.invite_code, t.invite_expires_at
      ORDER BY MIN(m.joined_at)`,
  )
    .bind(...caller.partitions)
    .all<
      TableRow & {
        lastReadSeq: number;
        showPhotos: number;
        showNutrition: number;
        showBodyGoals: number;
      }
    >();

  const tables = await summarize(
    env,
    rows.results.map((row) => ({
      row,
      myLastReadSeq: row.lastReadSeq,
      visibility: row,
    })),
    caller,
    since,
  );
  return { tables, asOf: Date.now() };
}

function parseIngredients(json: string | null): TablePost["ingredients"] {
  if (!json) return null;
  try {
    return JSON.parse(json) as TablePost["ingredients"];
  } catch {
    return null;
  }
}

function buildPost(row: PostRow, partitions: string[], reactions: PostReactions[]): TablePost {
  const share = row.kind === "share";
  return {
    id: row.id,
    seq: row.seq,
    kind: share ? "share" : "message",
    authorMemberId: row.authorMemberId,
    authorName: row.authorName,
    mine: partitions.includes(row.authorAccount),
    createdAt: row.createdAt,
    mealId: share ? row.mealId : null,
    dishName: share ? row.dishName : null,
    caption: share ? row.body : null,
    ingredients: share ? parseIngredients(row.ingredientsJson) : null,
    hasPhoto: share && row.photoObjectKey !== null,
    text: share ? null : row.body,
    replyToPostId: row.replyToPostId,
    reactions,
  };
}

async function reactionsByPost(
  database: D1Database,
  postIds: string[],
  partitions: string[],
): Promise<Map<string, PostReactions[]>> {
  const map = new Map<string, PostReactions[]>();
  if (postIds.length === 0) return map;
  const rows = await database
    .prepare(
      `SELECT post_id AS postId, kind, COUNT(*) AS count,
              MAX(CASE WHEN account_id IN (${placeholders(partitions.length)}) THEN 1 ELSE 0 END) AS mine
         FROM table_reactions
        WHERE post_id IN (${placeholders(postIds.length)})
        GROUP BY post_id, kind`,
    )
    .bind(...partitions, ...postIds)
    .all<{ postId: string; kind: string; count: number; mine: number }>();
  for (const row of rows.results) {
    const list = map.get(row.postId) ?? [];
    list.push({
      kind: row.kind === "olive" ? "olive" : "heart",
      count: row.count,
      mine: row.mine === 1,
    });
    map.set(row.postId, list);
  }
  return map;
}

export async function getFeed(
  env: Env,
  caller: TableCaller,
  tableId: string,
  query: { cursor?: number; limit: number; since?: number },
): Promise<TableFeedResponse> {
  const member = await requireMembership(env.DB, tableId, caller.partitions);
  const row = await tableRow(env.DB, tableId);
  if (!row) throw new HttpError(404, "No such table for this account.");

  const page = await env.DB.prepare(
    `SELECT ${POST_COLUMNS} FROM table_posts
      WHERE table_id = ? AND (? IS NULL OR seq < ?)
      ORDER BY seq DESC LIMIT ?`,
  )
    .bind(tableId, query.cursor ?? null, query.cursor ?? null, query.limit)
    .all<PostRow>();

  const reactions = await reactionsByPost(
    env.DB,
    page.results.map((post) => post.id),
    caller.partitions,
  );
  const posts = page.results.map((post) =>
    buildPost(post, caller.partitions, reactions.get(post.id) ?? []),
  );
  const table = await summaryFor(env, row, member, caller, query.since);
  return {
    table,
    posts,
    nextCursor: page.results.length === query.limit ? (page.results.at(-1)?.seq ?? null) : null,
    asOf: Date.now(),
  };
}

/**
 * The redaction, applied by construction: this SELECT names every column a
 * post will ever hold, and the share branch fills them from the request's
 * whitelisted fields alone. Nothing reads the sharer's log here — the client
 * sends what the share sheet showed, and the server stores no more than the
 * contract can spell.
 */
export async function createPost(
  env: Env,
  caller: TableCaller,
  tableId: string,
  input: CreatePostRequest,
  now = Date.now(),
): Promise<TablePost> {
  const member = await requireMembership(env.DB, tableId, caller.partitions);
  const visibleShare = input.kind === "share" ? redactTableShare(member, input) : null;

  let photoObjectKey: string | null = null;
  let photoMime: string | null = null;
  if (visibleShare?.photoHash) {
    const copied = await copySharedPhoto(
      env,
      caller.partitions,
      tableId,
      input.id,
      visibleShare.photoHash,
    );
    photoObjectKey = copied.objectKey;
    photoMime = copied.mimeType;
  }

  if (input.kind === "message" && input.replyToPostId) {
    const parent = await env.DB.prepare(
      "SELECT 1 AS present FROM table_posts WHERE id = ? AND table_id = ?",
    )
      .bind(input.replyToPostId, tableId)
      .first<{ present: number }>();
    if (!parent) throw new HttpError(400, "That reply answers a post this table does not have.");
  }

  await env.DB.prepare(
    `INSERT OR IGNORE INTO table_posts
      (id, table_id, seq, author_account, author_member_id, author_name, kind,
       reply_to_post_id, meal_id, dish_name, body, ingredients_json,
       photo_object_key, photo_mime, created_at)
     VALUES (?, ?, (SELECT COALESCE(MAX(seq), 0) + 1 FROM table_posts WHERE table_id = ?),
             ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      input.id,
      tableId,
      tableId,
      caller.accountId,
      member.memberId,
      member.displayName,
      input.kind,
      input.kind === "message" ? input.replyToPostId : null,
      input.kind === "share" ? input.mealId : null,
      input.kind === "share" ? input.dishName : null,
      input.kind === "share" ? input.caption : input.text,
      visibleShare?.ingredients ? JSON.stringify(visibleShare.ingredients) : null,
      photoObjectKey,
      photoMime,
      now,
    )
    .run();

  const stored = await env.DB.prepare(`SELECT ${POST_COLUMNS} FROM table_posts WHERE id = ?`)
    .bind(input.id)
    .first<PostRow>();
  if (!stored) throw new HttpError(500, "Could not read the post back.");
  // OR IGNORE makes a retried send one post; the same id landing in another
  // table is a different client's id, not a retry.
  if (stored.tableId !== tableId) throw new HttpError(409, "That post id is already taken.");
  const reactions = await reactionsByPost(env.DB, [stored.id], caller.partitions);
  return buildPost(stored, caller.partitions, reactions.get(stored.id) ?? []);
}

/** Membership preferences are enforced again at the storage boundary. An old
 * or modified client can ask for more, but the Worker never stores it. */
export function redactTableShare(
  member: Pick<MemberRow, "showPhotos" | "showNutrition">,
  input: Extract<CreatePostRequest, { kind: "share" }>,
): {
  photoHash: string | null;
  ingredients: Extract<CreatePostRequest, { kind: "share" }>["ingredients"];
} {
  return {
    photoHash: member.showPhotos === 1 ? input.photoHash : null,
    ingredients: member.showNutrition === 1 ? input.ingredients : null,
  };
}

/** The only words at a table are the author's one-line plate note. Updating it
 * never creates a row, a reply target, or an unread conversation. */
export async function updateTableNote(
  env: Env,
  caller: TableCaller,
  tableId: string,
  postId: string,
  note: string | null,
): Promise<{ note: string | null }> {
  await requireMembership(env.DB, tableId, caller.partitions);
  const post = await env.DB.prepare(
    `SELECT author_account AS authorAccount, kind FROM table_posts
      WHERE id = ? AND table_id = ?`,
  )
    .bind(postId, tableId)
    .first<{ authorAccount: string; kind: string }>();
  if (post?.kind !== "share") throw new HttpError(404, "No such plate at this table.");
  if (!caller.partitions.includes(post.authorAccount)) {
    throw new HttpError(403, "Only the plate's author can edit its note.");
  }
  const normalized = note?.trim() || null;
  await env.DB.prepare("UPDATE table_posts SET body = ? WHERE id = ? AND table_id = ?")
    .bind(normalized, postId, tableId)
    .run();
  return { note: normalized };
}

/**
 * The bytes move server-side from the sharer's own private object to a
 * table-owned key. The tables API accepts no image bytes at all, so the one
 * route where bytes enter R2 stays the recognition path with its limits and
 * its consent story; and the `media/<account>/` prefix stays readable by
 * exactly one account, because nothing here ever serves from it.
 */
async function copySharedPhoto(
  env: Env,
  partitions: string[],
  tableId: string,
  postId: string,
  photoHash: string,
): Promise<{ objectKey: string; mimeType: string }> {
  const source = await env.DB.prepare(
    `SELECT object_key AS objectKey, mime_type AS mimeType FROM media_objects
      WHERE photo_hash = ? AND stored_at IS NOT NULL
        AND account_id IN (${placeholders(partitions.length)})
      LIMIT 1`,
  )
    .bind(photoHash.toLowerCase(), ...partitions)
    .first<{ objectKey: string; mimeType: string }>();
  if (!source) throw new HttpError(404, "That photo is not on the server for this account.");

  const objectKey = postMediaKey(tableId, postId, source.mimeType);
  const existing = await env.MEDIA.head(objectKey);
  if (!existing) {
    const object = await env.MEDIA.get(source.objectKey);
    if (!object) throw new HttpError(404, "That photo is not on the server for this account.");
    await env.MEDIA.put(objectKey, await object.arrayBuffer(), {
      httpMetadata: { contentType: source.mimeType, cacheControl: "private, no-store" },
      customMetadata: { purpose: "table-share", sourceHash: photoHash.toLowerCase() },
    });
  }
  return { objectKey, mimeType: source.mimeType };
}

export async function getPostPhoto(
  env: Env,
  caller: TableCaller,
  tableId: string,
  postId: string,
): Promise<R2ObjectBody | null> {
  await requireMembership(env.DB, tableId, caller.partitions);
  const post = await env.DB.prepare(
    "SELECT photo_object_key AS objectKey FROM table_posts WHERE id = ? AND table_id = ?",
  )
    .bind(postId, tableId)
    .first<{ objectKey: string | null }>();
  if (!post?.objectKey) return null;
  return env.MEDIA.get(post.objectKey);
}

export async function deletePost(
  env: Env,
  caller: TableCaller,
  tableId: string,
  postId: string,
): Promise<{ deleted: boolean }> {
  const member = await requireMembership(env.DB, tableId, caller.partitions);
  const post = await env.DB.prepare(
    `SELECT author_account AS authorAccount, photo_object_key AS objectKey
       FROM table_posts WHERE id = ? AND table_id = ?`,
  )
    .bind(postId, tableId)
    .first<{ authorAccount: string; objectKey: string | null }>();
  if (!post) return { deleted: false };
  const isAuthor = caller.partitions.includes(post.authorAccount);
  if (!isAuthor && member.role !== "creator") {
    throw new HttpError(403, "Only the author or the table's creator can remove a post.");
  }
  if (post.objectKey) await env.MEDIA.delete(post.objectKey);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM table_reactions WHERE post_id = ?").bind(postId),
    // Replies survive on purpose and render as plain messages: deleting your
    // share should not delete your friends' words about it.
    env.DB.prepare("DELETE FROM table_posts WHERE id = ?").bind(postId),
  ]);
  return { deleted: true };
}

export async function setReaction(
  env: Env,
  caller: TableCaller,
  tableId: string,
  input: { postId: string; kind: "olive" | "heart"; on: boolean },
  now = Date.now(),
): Promise<{ on: boolean }> {
  await requireMembership(env.DB, tableId, caller.partitions);
  const post = await env.DB.prepare(
    "SELECT 1 AS present FROM table_posts WHERE id = ? AND table_id = ?",
  )
    .bind(input.postId, tableId)
    .first<{ present: number }>();
  if (!post) throw new HttpError(404, "No such post at this table.");

  const parts = caller.partitions;
  if (input.on) {
    // Checked over the union first: a reaction left before sign-in is already
    // "mine", and inserting a second row under the account partition would
    // count one person twice.
    const existing = await env.DB.prepare(
      `SELECT 1 AS present FROM table_reactions
        WHERE post_id = ? AND kind = ? AND account_id IN (${placeholders(parts.length)})`,
    )
      .bind(input.postId, input.kind, ...parts)
      .first<{ present: number }>();
    if (!existing) {
      await env.DB.prepare(
        `INSERT OR IGNORE INTO table_reactions (post_id, account_id, kind, created_at)
         VALUES (?, ?, ?, ?)`,
      )
        .bind(input.postId, caller.accountId, input.kind, now)
        .run();
    }
  } else {
    await env.DB.prepare(
      `DELETE FROM table_reactions
        WHERE post_id = ? AND kind = ? AND account_id IN (${placeholders(parts.length)})`,
    )
      .bind(input.postId, input.kind, ...parts)
      .run();
  }
  return { on: input.on };
}

export async function markRead(
  env: Env,
  caller: TableCaller,
  tableId: string,
  seq: number,
): Promise<{ lastReadSeq: number }> {
  await requireMembership(env.DB, tableId, caller.partitions);
  // MAX() keeps this monotonic: a stale request from a phone that was offline
  // cannot un-read what a fresher one already read.
  await env.DB.prepare(
    `UPDATE table_members SET last_read_seq = MAX(last_read_seq, ?)
      WHERE table_id = ? AND account_id IN (${placeholders(caller.partitions.length)})`,
  )
    .bind(seq, tableId, ...caller.partitions)
    .run();
  const member = await requireMembership(env.DB, tableId, caller.partitions);
  return { lastReadSeq: member.lastReadSeq };
}

export async function rotateInvite(
  env: Env,
  caller: TableCaller,
  tableId: string,
  now = Date.now(),
): Promise<{ inviteCode: string; inviteExpiresAt: number }> {
  await requireMembership(env.DB, tableId, caller.partitions);
  const code = newInviteCode();
  const inviteExpiresAt = now + TABLE_INVITE_TTL_MS;
  await env.DB.prepare("UPDATE tables SET invite_code = ?, invite_expires_at = ? WHERE id = ?")
    .bind(code, inviteExpiresAt, tableId)
    .run();
  return { inviteCode: code, inviteExpiresAt };
}

/**
 * Leaving keeps your past posts: a chat does not grow holes because somebody
 * left it. The one force that removes them is `deleteTablesData` below — the
 * "delete my cloud data" promise wins over the thread. When the last chair
 * empties, the table and its whole R2 prefix go with it.
 */
export async function leaveTable(
  env: Env,
  caller: TableCaller,
  tableId: string,
): Promise<{ left: boolean; tableDeleted: boolean }> {
  await requireMembership(env.DB, tableId, caller.partitions);
  await env.DB.prepare(
    `DELETE FROM table_members
      WHERE table_id = ? AND account_id IN (${placeholders(caller.partitions.length)})`,
  )
    .bind(tableId, ...caller.partitions)
    .run();
  const remaining = await env.DB.prepare(
    "SELECT COUNT(*) AS members FROM table_members WHERE table_id = ?",
  )
    .bind(tableId)
    .first<{ members: number }>();
  if ((remaining?.members ?? 0) > 0) return { left: true, tableDeleted: false };
  await destroyTable(env, tableId);
  return { left: true, tableDeleted: true };
}

export async function deleteTable(
  env: Env,
  caller: TableCaller,
  tableId: string,
): Promise<{ deleted: boolean }> {
  const member = await requireMembership(env.DB, tableId, caller.partitions);
  if (member.role !== "creator") {
    throw new HttpError(403, "Only the table's creator can delete it.");
  }
  await destroyTable(env, tableId);
  return { deleted: true };
}

async function destroyTable(env: Env, tableId: string): Promise<void> {
  const prefix = tableMediaPrefix(tableId);
  while (true) {
    // Restart from the beginning each page: deleting mutates the listing, and
    // an old cursor would step over keys that shifted left.
    const page = await env.MEDIA.list({ prefix, limit: 1_000 });
    const keys = page.objects.map((object) => object.key);
    if (keys.length === 0) break;
    await env.MEDIA.delete(keys);
  }
  await env.DB.batch([
    env.DB.prepare(
      `DELETE FROM table_reactions
        WHERE post_id IN (SELECT id FROM table_posts WHERE table_id = ?)`,
    ).bind(tableId),
    env.DB.prepare("DELETE FROM table_posts WHERE table_id = ?").bind(tableId),
    env.DB.prepare("DELETE FROM table_members WHERE table_id = ?").bind(tableId),
    env.DB.prepare("DELETE FROM tables WHERE id = ?").bind(tableId),
  ]);
}

const DELETE_CHUNK = 200;

function chunked<T>(values: T[], size = DELETE_CHUNK): T[][] {
  const chunks: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size));
  }
  return chunks;
}

/**
 * The tables half of account erasure, called from `deleteAccountData`.
 *
 * "Delete my cloud data" is an already-shipped promise, and shared copies are
 * still the person's data: every post they authored goes, photo bytes first —
 * the R2 keys are enumerable from the author index, which is half the reason
 * the copy-on-share keys exist. Runs across every partition, for the same
 * reason the rest of erasure does.
 */
export async function deleteTablesData(
  env: Env,
  partitions: string[],
): Promise<{ posts: number; memberships: number; photoObjects: number; tablesDeleted: number }> {
  if (partitions.length === 0)
    return { posts: 0, memberships: 0, photoObjects: 0, tablesDeleted: 0 };
  const parts = placeholders(partitions.length);

  const authored = await env.DB.prepare(
    `SELECT id, table_id AS tableId, photo_object_key AS objectKey
       FROM table_posts WHERE author_account IN (${parts})`,
  )
    .bind(...partitions)
    .all<{ id: string; tableId: string; objectKey: string | null }>();
  const seatedAt = await env.DB.prepare(
    `SELECT DISTINCT table_id AS tableId FROM table_members WHERE account_id IN (${parts})`,
  )
    .bind(...partitions)
    .all<{ tableId: string }>();

  const photoKeys = authored.results
    .map((post) => post.objectKey)
    .filter((key): key is string => key !== null);
  for (const keys of chunked(photoKeys, 500)) {
    await env.MEDIA.delete(keys);
  }

  for (const ids of chunked(authored.results.map((post) => post.id))) {
    const marks = placeholders(ids.length);
    await env.DB.batch([
      env.DB.prepare(`DELETE FROM table_reactions WHERE post_id IN (${marks})`).bind(...ids),
      env.DB.prepare(`DELETE FROM table_posts WHERE id IN (${marks})`).bind(...ids),
    ]);
  }
  await env.DB.batch([
    env.DB.prepare(`DELETE FROM table_reactions WHERE account_id IN (${parts})`).bind(
      ...partitions,
    ),
    env.DB.prepare(`DELETE FROM table_members WHERE account_id IN (${parts})`).bind(...partitions),
  ]);

  // Tables the account touched that now stand empty are garbage-collected the
  // same way the last leaver collects them.
  const affected = new Set<string>([
    ...authored.results.map((post) => post.tableId),
    ...seatedAt.results.map((row) => row.tableId),
  ]);
  let tablesDeleted = 0;
  for (const tableId of affected) {
    const remaining = await env.DB.prepare(
      "SELECT COUNT(*) AS members FROM table_members WHERE table_id = ?",
    )
      .bind(tableId)
      .first<{ members: number }>();
    if ((remaining?.members ?? 0) === 0) {
      await destroyTable(env, tableId);
      tablesDeleted += 1;
    }
  }

  return {
    posts: authored.results.length,
    memberships: seatedAt.results.length,
    photoObjects: photoKeys.length,
    tablesDeleted,
  };
}

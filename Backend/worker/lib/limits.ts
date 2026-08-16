import { and, count, eq, gte } from "drizzle-orm";
import { createDb } from "../db/client";
import { recognitions } from "../db/schema";
import type { Env } from "../env";
import { HttpError } from "./http-error";

export type Counters = {
  /** Recognitions in the last 24h for one account. */
  todayFor(env: Env, accountId: string): Promise<number>;
};

export const d1Counters: Counters = {
  async todayFor(env, accountId) {
    const since = new Date(Date.now() - 86_400_000).toISOString();
    const [row] = await createDb(env.DB)
      .select({ used: count() })
      .from(recognitions)
      .where(and(gte(recognitions.createdAt, since), eq(recognitions.accountId, accountId)));
    return row?.used ?? 0;
  },
};

/**
 * Three layers, and they guarantee different things.
 *
 * The rate limiting binding is per-Cloudflare-location — counters live on the
 * machine the Worker runs on, which is why it costs no latency and also why a
 * caller spread across colos gets one allowance per colo. It stops a script
 * hammering one endpoint and guarantees nothing about the bill.
 *
 * The per-account day quota is fairness: one person cannot spend everyone's
 * budget by accident. It reads a count, so it races — tolerable for fairness,
 * not tolerable for money.
 *
 * The money guarantee is `reserveRecognition`, and it happens after the cache
 * lookup, because a cached answer costs nothing and refusing it once the day is
 * full would deny free work.
 *
 * All three key on the verified account. They keyed on `X-Device-Id` while a
 * device was a partition; a quota attached to a header the caller writes is one
 * the caller can reset by editing it.
 */
export async function enforceRecognitionLimits(env: Env, accountId: string): Promise<void> {
  const { success } = await env.RECOGNITION_LIMIT.limit({ key: accountId });
  if (!success) throw new HttpError(429, "Too many photos at once. Wait a minute and try again.");
}

/** Cache hits are free, so the daily fairness quota is checked only on misses. */
export async function enforcePaidRecognitionFairness(
  env: Env,
  accountId: string,
  counters: Counters = d1Counters,
): Promise<void> {
  const perAccount = Number(env.RECOGNITIONS_PER_DEVICE_PER_DAY || 0);
  if (perAccount > 0 && (await counters.todayFor(env, accountId)) >= perAccount) {
    throw new HttpError(429, "That is a day's worth of photos from this account.");
  }
}

export async function enforceSyncLimits(env: Env, accountId: string): Promise<void> {
  const { success } = await env.SYNC_LIMIT.limit({ key: accountId });
  if (!success) throw new HttpError(429, "Too many requests. Slow down.");
}

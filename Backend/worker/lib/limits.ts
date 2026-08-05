import { and, count, eq, gte } from "drizzle-orm";
import { createDb } from "../db/client";
import { recognitions } from "../db/schema";
import type { Env } from "../env";
import { accountForDevice } from "./auth";
import { HttpError } from "./http-error";

export { accountForDevice as callerFor } from "./auth";

export type Counters = {
  /** Recognitions in the last 24h, everywhere. */
  today(env: Env): Promise<number>;
  /** Recognitions in the last 24h for one caller. */
  todayFor(env: Env, caller: string): Promise<number>;
};

export const d1Counters: Counters = {
  async today(env) {
    const since = new Date(Date.now() - 86_400_000).toISOString();
    const [row] = await createDb(env.DB)
      .select({ used: count() })
      .from(recognitions)
      .where(gte(recognitions.createdAt, since));
    return row?.used ?? 0;
  },
  async todayFor(env, caller) {
    const since = new Date(Date.now() - 86_400_000).toISOString();
    const [row] = await createDb(env.DB)
      .select({ used: count() })
      .from(recognitions)
      // `accountId` is the device when nobody logs in, so a per-caller quota is
      // one WHERE clause rather than a new column.
      .where(and(gte(recognitions.createdAt, since), eq(recognitions.accountId, caller)));
    return row?.used ?? 0;
  },
};

/**
 * Three layers, bounding three different things.
 *
 * The rate limiting binding is per-Cloudflare-location — counters live on the
 * machine the Worker runs on, which is why it costs no latency and also why a
 * caller spread across colos gets one allowance per colo. It stops a script
 * hammering one endpoint and guarantees nothing about the bill.
 *
 * The per-caller day quota is fairness: one phone cannot spend everyone's
 * budget by accident.
 *
 * The global day ceiling is the guarantee, denominated in the thing that costs
 * money. At 400 recognitions the worst case is a few dollars, whoever is
 * calling and however they spread it.
 */
export async function enforceRecognitionLimits(
  env: Env,
  request: Request,
  counters: Counters = d1Counters,
): Promise<string> {
  const caller = accountForDevice(request);
  const { success } = await env.RECOGNITION_LIMIT.limit({ key: caller });
  if (!success) throw new HttpError(429, "Too many photos at once. Wait a minute and try again.");

  const perCaller = Number(env.RECOGNITIONS_PER_DEVICE_PER_DAY || 0);
  if (perCaller > 0 && (await counters.todayFor(env, caller)) >= perCaller) {
    throw new HttpError(429, "That is a day's worth of photos from this device.");
  }

  const ceiling = Number(env.RECOGNITIONS_PER_DAY || 0);
  if (ceiling > 0 && (await counters.today(env)) >= ceiling) {
    // Deliberately not "try again shortly": the window is a day, and a client
    // that retries into it spends tomorrow's budget too.
    throw new HttpError(
      503,
      "Recognition is closed for today. This is a spending cap, not an outage.",
    );
  }
  return caller;
}

export async function enforceSyncLimits(env: Env, request: Request): Promise<void> {
  const { success } = await env.SYNC_LIMIT.limit({ key: accountForDevice(request) });
  if (!success) throw new HttpError(429, "Too many requests. Slow down.");
}

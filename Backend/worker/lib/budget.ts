import type { Env } from "../env";

/**
 * Reserve one paid call, or refuse.
 *
 * Reading a count and then spending is a time-of-check race: under load every
 * request sees 399 and every one of them proceeds. The Cloudflare rate limiter
 * cannot close it either — its counters are per-location and deliberately
 * permissive, which is what makes them free of network latency.
 *
 * D1 serialises writes within a database, so a conditional UPDATE is a real
 * reservation: it either matches while the day is under its ceiling and
 * increments, or matches nothing. `meta.changes` says which happened. That
 * makes the ceiling a promise about money rather than a hope.
 */
export async function reserveRecognition(env: Env, ceiling: number): Promise<boolean> {
  if (ceiling <= 0) return true;
  const day = new Date().toISOString().slice(0, 10);

  await env.DB.prepare("INSERT OR IGNORE INTO budget (day, used) VALUES (?, 0)").bind(day).run();
  const result = await env.DB.prepare(
    "UPDATE budget SET used = used + 1 WHERE day = ? AND used < ?",
  )
    .bind(day, ceiling)
    .run();
  return (result.meta?.changes ?? 0) === 1;
}

/**
 * Hand a reservation back when the call it was for never happened.
 *
 * A provider error costs nothing, so charging the day for it would let a broken
 * upstream close the service. Best effort: losing a unit is a rounding error
 * against the ceiling, while double-counting one is not.
 */
export async function releaseRecognition(env: Env, ceiling: number): Promise<void> {
  if (ceiling <= 0) return;
  const day = new Date().toISOString().slice(0, 10);
  await env.DB.prepare("UPDATE budget SET used = used - 1 WHERE day = ? AND used > 0")
    .bind(day)
    .run()
    .catch(() => undefined);
}

import {
  type Composition,
  type IngestLegacyEventsRequest,
  ingestEventsRequestSchema,
  legacyEventSchema,
  legacyMealEventDataSchema,
  MEAL_SCHEMA_VERSION,
} from "../../src/contracts";
import type { Env } from "../env";
import { ingestEvents } from "./events";

/**
 * Accept meals written by v20, for exactly one release.
 *
 * The alternative was asking a person to open the old build on every device
 * before upgrading, and losing whatever they missed. That is not a migration
 * plan, it is a hope — and the data it protects is the data of whoever forgot.
 *
 * The v21 client cannot decode one of these, but it does not need to: the log
 * is JSONL, and an unreadable line is still a line. It forwards the raw text
 * and this converts it, which is the only place in the system that still knows
 * the old shape. Delete both with the endpoint once the audit reports zero.
 *
 * Composition comes from `food_prices`, which the bulk migration fills with
 * every distinct label already in the log. A late line comes off the same trays
 * as the ones already priced, so it almost always hits. When it does not, the
 * row is DROPPED and named in the response rather than being given an invented
 * figure — a fabricated number in the one place reserved for stored facts is
 * worse than a visibly short meal.
 */
export async function ingestLegacyEvents(
  env: Env,
  accountId: string,
  input: IngestLegacyEventsRequest,
): Promise<{ accepted: number; converted: number; inserted: number; unpriced: string[] }> {
  const parsed = input.lines
    .map((line) => {
      try {
        return JSON.parse(line) as unknown;
      } catch {
        return null;
      }
    })
    .filter((value): value is Record<string, unknown> => value !== null)
    .map((value) => legacyEventSchema.safeParse(value))
    .filter((result) => result.success)
    .map((result) => result.data);

  const meals = parsed.filter(
    (event) => event.payload.kind === "meal_logged" || event.payload.kind === "meal_revised",
  );
  if (!meals.length) return { accepted: parsed.length, converted: 0, inserted: 0, unpriced: [] };

  const labels = new Set<string>();
  for (const event of meals) {
    const data = legacyMealEventDataSchema.safeParse(
      (event.payload as { data?: unknown }).data ?? {},
    );
    if (!data.success) continue;
    for (const item of data.data.items) {
      const label = (item.label ?? "").trim().toLowerCase();
      if (label) labels.add(label);
    }
  }

  const prices = new Map<string, Composition>();
  if (labels.size) {
    const placeholders = [...labels].map(() => "?").join(",");
    const rows = await env.DB.prepare(
      `SELECT label, per_100g_json FROM food_prices WHERE label IN (${placeholders})`,
    )
      .bind(...labels)
      .all<{ label: string; per_100g_json: string }>();
    for (const row of rows.results ?? []) {
      prices.set(row.label, JSON.parse(row.per_100g_json) as Composition);
    }
  }

  const unpriced = new Set<string>();
  const converted: unknown[] = [];

  for (const event of meals) {
    const data = legacyMealEventDataSchema.safeParse(
      (event.payload as { data?: unknown }).data ?? {},
    );
    if (!data.success) continue;

    const byDish = new Map<string | null, unknown[]>();
    const order: (string | null)[] = [];
    for (const item of data.data.items) {
      const label = (item.label ?? "").trim();
      const key = label.toLowerCase();
      const per100g = prices.get(key);
      if (!label || item.grams == null || !per100g) {
        if (label && !per100g) unpriced.add(label);
        continue;
      }
      const dish = item.dish ?? null;
      if (!byDish.has(dish)) {
        byDish.set(dish, []);
        order.push(dish);
      }
      byDish.get(dish)?.push({
        id: item.id,
        label,
        grams: item.grams,
        per_100g: per100g,
        // Priced by the same pass that priced the rest of the history, and the
        // person did not ask for it. `model`, even on a corrected meal: what
        // they corrected was the food, and the food is what was priced.
        provenance: {
          protein: "model",
          fat: "model",
          carbohydrate: "model",
          kcal: "model",
          sodium: "model",
        },
        preparation: item.preparation ?? [],
        alternatives: [],
      });
    }

    const dishes = order
      .map((name) => ({
        id: crypto.randomUUID(),
        name: name || null,
        count: 1,
        panel: null,
        items: byDish.get(name) ?? [],
      }))
      .filter((dish) => dish.items.length > 0);
    if (!dishes.length) continue;

    converted.push({
      id: event.id,
      occurredAt: event.occurredAt,
      recordedAt: event.recordedAt,
      payload: {
        kind: event.payload.kind,
        data: {
          id: data.data.id,
          schemaVersion: MEAL_SCHEMA_VERSION,
          eatenAt: data.data.eatenAt,
          dishes,
          source: ["photo", "manual", "recipe", "text"].includes(data.data.source)
            ? data.data.source
            : "manual",
          share: data.data.share ?? null,
          note: data.data.note ?? null,
          photoHash: data.data.photoHash ?? null,
          wasCorrected: data.data.wasCorrected ?? false,
          recipeID: data.data.recipeID ?? null,
          messageID: data.data.messageID ?? null,
        },
      },
    });
  }

  if (!converted.length) {
    return {
      accepted: parsed.length,
      converted: 0,
      inserted: 0,
      unpriced: [...unpriced].sort(),
    };
  }

  // Down the ordinary ingest path, so a converted event is validated against
  // the v21 contract exactly like one the app wrote. Anything this produced
  // that v21 would not accept fails here rather than reaching the log.
  const batch = ingestEventsRequestSchema.parse({
    deviceId: input.deviceId,
    events: converted,
  });
  const result = await ingestEvents(env, accountId, batch);

  return {
    accepted: parsed.length,
    converted: converted.length,
    inserted: result.inserted,
    unpriced: [...unpriced].sort(),
  };
}

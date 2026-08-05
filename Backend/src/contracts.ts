import * as z from "zod";

export const foodGroups = [
  "olive_oil",
  "vegetables",
  "fruit",
  "legumes",
  "fish",
  "nuts",
  "healthy_fats",
  "whole_grains",
  "refined_grains",
  "white_meat",
  "red_meat",
  "processed_meat",
  "dairy",
  "egg",
  "sweets",
  "pastry",
  "sugary_drinks",
  "butter",
  "alcohol",
  "sofrito",
  "other",
] as const;

export const portions = ["small", "medium", "large"] as const;

/// Both answer the same contract and the same prompt, so a device can switch
/// and the eval rows stay comparable. Which one served a request is recorded on
/// the recognition row, and the cache keys on the model.
export const recognitionProviders = ["openai", "gemini", "anthropic", "qwen"] as const;
export type RecognitionProvider = (typeof recognitionProviders)[number];
export const eventKinds = [
  "meal_logged",
  "meal_revised",
  "meal_deleted",
  "set_completed",
  "habits_updated",
  "recipe_saved",
  "recipe_deleted",
] as const;

export const sha256Schema = z
  .string()
  .regex(/^[a-f0-9]{64}$/i, "Expected a 64-character SHA-256 hex digest.");

const rawJsonSchema = z
  .string()
  .min(2)
  .max(200_000)
  .refine((value) => {
    try {
      JSON.parse(value);
      return true;
    } catch {
      return false;
    }
  }, "Expected valid raw model JSON.");

export const mealRecognitionItemSchema = z.strictObject({
  group: z.enum(foodGroups),
  portion: z.enum(portions),
  label: z.string().max(200).nullable(),
  // Uncertainty is a shortlist of rival groups, not a number. A model asked to
  // score its own certainty returns the same round value for every item on the
  // plate; asked what else the food could be, it answers about the food — and
  // the answer doubles as the one-tap correction in the client.
  alternatives: z.array(z.enum(foodGroups)),
});

export const mealRecognitionSchema = z.strictObject({
  items: z.array(mealRecognitionItemSchema).max(64),
  other_meals_visible: z.boolean(),
  notes: z.string().max(2_000).nullable(),
});

export type MealRecognition = z.infer<typeof mealRecognitionSchema>;

export function mealRecognitionJsonSchema(): Record<string, unknown> {
  const schema = z.toJSONSchema(mealRecognitionSchema, { target: "draft-07" });
  delete schema.$schema;
  return schema;
}

export const recognitionRequestSchema = z.strictObject({
  // Absent means the server's default, so an older client keeps working.
  provider: z.enum(recognitionProviders).optional(),
  photoHash: sha256Schema,
  mimeType: z.enum(["image/jpeg", "image/png", "image/webp"]),
  imageBase64: z
    .string()
    .min(16)
    .max(12_000_000)
    .regex(/^[A-Za-z0-9+/]*={0,2}$/),
  // The note changes the question, so it is part of the recognition cache
  // fingerprint. "Fried in butter" must not replay the answer produced before
  // the person supplied that fact.
  note: z.string().max(2_000).nullable().optional(),
});

export type RecognitionRequest = z.infer<typeof recognitionRequestSchema>;

export const rerunRecognitionRequestSchema = z.strictObject({
  provider: z.enum(recognitionProviders).optional(),
  note: z.string().max(2_000).nullable().optional(),
  // A menu action means "ask again", not "show me the cache again". The
  // switch remains explicit so diagnostics can exercise the stored-input path
  // without buying another inference.
  refresh: z.boolean().default(true),
});

export type RerunRecognitionRequest = z.infer<typeof rerunRecognitionRequestSchema>;

export const mealItemSchema = z.strictObject({
  id: z.string().uuid(),
  group: z.enum(foodGroups),
  portion: z.enum(portions),
  label: z.string().max(200).nullable().optional(),
  modelAlternatives: z.array(z.enum(foodGroups)).nullable().optional(),
  // Events written before the alternatives contract still sync from devices
  // that have them in their append-only log. Accept, do not require.
  modelConfidence: z.number().min(0).max(1).nullable().optional(),
});

export const recognitionEvidenceSchema = z.strictObject({
  promptVersion: z.string().min(1).max(120),
  rawModelJSON: rawJsonSchema,
  initialItems: z.array(mealItemSchema).max(64),
  otherMealsVisible: z.boolean(),
});

export const mealEventDataSchema = z.strictObject({
  id: z.string().uuid(),
  eatenAt: z.number().int().nonnegative(),
  items: z.array(mealItemSchema).max(64),
  source: z.enum(["photo", "manual", "recipe"]),
  // Absent on entries logged before the switch existed; those were scored whole.
  share: z.enum(["whole", "part"]).nullable().optional(),
  // What the photo could not show, in the person's own words. Natural-language
  // labelling of exactly what recognition missed — a better input for clustering
  // weekly failures than any diff of the JSON.
  note: z.string().max(2_000).nullable().optional(),
  recognitionRating: z.enum(["good", "bad"]).nullable().optional(),
  photoHash: sha256Schema.nullable().optional(),
  modelConfidence: z.number().min(0).max(1).nullable().optional(),
  recognitionEvidence: recognitionEvidenceSchema.nullable().optional(),
  wasCorrected: z.boolean(),
});

export const loggedEventSchema = z.strictObject({
  id: z.string().uuid(),
  occurredAt: z.number().int().nonnegative(),
  recordedAt: z.number().int().nonnegative(),
  payload: z.strictObject({
    kind: z.enum(eventKinds),
    data: z.record(z.string(), z.unknown()),
  }),
});

export type LoggedEventInput = z.infer<typeof loggedEventSchema>;

export const ingestEventsRequestSchema = z.strictObject({
  deviceId: z.string().min(8).max(200),
  events: z.array(loggedEventSchema).min(1).max(500),
});

export type IngestEventsRequest = z.infer<typeof ingestEventsRequestSchema>;

export const eventListQuerySchema = z.strictObject({
  cursor: z.string().max(200).optional(),
  limit: z.coerce.number().int().min(1).max(500).default(100),
});

export const evalListQuerySchema = z.strictObject({
  limit: z.coerce.number().int().min(1).max(500).default(100),
});

/**
 * A corpus image is deliberately not the media image again. It is a separate,
 * privacy-filtered render produced at save time; because cropping changes the
 * bytes, it has its own content hash while retaining the source photo hash for
 * provenance and deletion.
 */
export const corpusItemRequestSchema = z.strictObject({
  mealId: z.string().uuid(),
  sourcePhotoHash: sha256Schema,
  corpusHash: sha256Schema,
  mimeType: z.literal("image/jpeg"),
  imageBase64: z
    .string()
    .min(16)
    .max(8_000_000)
    .regex(/^[A-Za-z0-9+/]*={0,2}$/),
  consent: z.strictObject({
    granted: z.literal(true),
    policyVersion: z.string().min(1).max(120),
    capturedAt: z.number().int().nonnegative(),
  }),
  privacy: z.strictObject({
    cropMethod: z.string().min(1).max(120),
    facesExcluded: z.literal(true),
    otherMealsExcluded: z.literal(true),
  }),
});

export type CorpusItemRequest = z.infer<typeof corpusItemRequestSchema>;

export const mealDeleteDataSchema = z.strictObject({ mealID: z.string().uuid() });

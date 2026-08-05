import { describe, expect, it } from "vitest";
import {
  ingestEventsRequestSchema,
  mealRecognitionJsonSchema,
  mealRecognitionSchema,
} from "./contracts";

describe("meal recognition contract", () => {
  it("requires per-item alternatives and the other-meals flag", () => {
    const parsed = mealRecognitionSchema.parse({
      items: [
        {
          group: "white_meat",
          portion: "medium",
          label: "minced meat",
          alternatives: ["red_meat"],
        },
      ],
      other_meals_visible: true,
      notes: "Could be pork.",
    });

    expect(parsed.items[0]?.alternatives).toEqual(["red_meat"]);
    expect(parsed.other_meals_visible).toBe(true);

    const jsonSchema = mealRecognitionJsonSchema();
    expect(jsonSchema).not.toHaveProperty("$schema");
    expect(JSON.stringify(jsonSchema)).toContain("other_meals_visible");
  });
});

describe("event sync contract", () => {
  it("accepts a complete model-to-human eval pair", () => {
    const itemId = "0198f222-aadb-7e00-8000-000000000001";
    const mealId = "0198f222-aadb-7e00-8000-000000000002";
    const eventId = "0198f222-aadb-7e00-8000-000000000003";
    const request = ingestEventsRequestSchema.parse({
      deviceId: "iphone-owner",
      events: [
        {
          id: eventId,
          occurredAt: 1_754_300_000_000,
          recordedAt: 1_754_300_001_000,
          payload: {
            kind: "meal_logged",
            data: {
              id: mealId,
              eatenAt: 1_754_300_000_000,
              items: [
                {
                  id: itemId,
                  group: "red_meat",
                  portion: "medium",
                  label: "minced meat",
                },
              ],
              source: "photo",
              photoHash: "a".repeat(64),
              recognitionEvidence: {
                promptVersion: "meal-v3-test",
                rawModelJSON: '{"items":[]}',
                initialItems: [
                  {
                    id: itemId,
                    group: "white_meat",
                    portion: "medium",
                    label: "minced meat",
                    modelAlternatives: ["red_meat"],
                  },
                ],
                otherMealsVisible: true,
              },
              wasCorrected: true,
            },
          },
        },
      ],
    });

    expect(request.events).toHaveLength(1);
  });
});

import { describe, expect, it } from "vitest";
import {
  corpusItemRequestSchema,
  flattenDishes,
  ingestEventsRequestSchema,
  mealRecognitionJsonSchema,
  mealRecognitionSchema,
  mealRevisionSchema,
  panelPerContainer,
  recognitionRequestSchema,
  refinementRequestSchema,
} from "./contracts";

describe("meal recognition contract", () => {
  it("requires per-ingredient alternatives and the other-meals flag", () => {
    const parsed = mealRecognitionSchema.parse({
      dishes: [
        {
          name: "keema curry",
          count: 1,
          panel: null,
          ingredients: [
            {
              group: "white_meat",
              grams: 140,
              label: "minced meat",
              alternatives: ["red_meat"],
            },
          ],
        },
      ],
      other_meals_visible: true,
      notes: "Could be pork.",
    });

    expect(parsed.dishes[0]?.ingredients[0]?.alternatives).toEqual(["red_meat"]);
    expect(parsed.other_meals_visible).toBe(true);

    const jsonSchema = mealRecognitionJsonSchema();
    expect(jsonSchema).not.toHaveProperty("$schema");
    expect(JSON.stringify(jsonSchema)).toContain("other_meals_visible");
    expect(JSON.stringify(jsonSchema)).toContain("ingredients");
  });

  it("rejects an ingredient with no weight", () => {
    // The whole point of v17. While `grams` was nullable behind a `portion`
    // fallback, the production Gemini schema omitted the field entirely and
    // every answer still parsed — the failure was silent for a month.
    expect(() =>
      mealRecognitionSchema.parse({
        dishes: [
          {
            name: "beer",
            count: 1,
            panel: null,
            ingredients: [{ group: "alcohol", label: "beer", alternatives: [] }],
          },
        ],
        other_meals_visible: false,
        notes: null,
      }),
    ).toThrow();
  });

  it("passes weights through untouched and multiplies nothing", () => {
    const flat = flattenDishes({
      dishes: [
        // Three beers: the count says three and the grams already hold all
        // three. Multiplying here is what made one bowl of ramen 126 g of
        // protein — the model called the bowl large and the noodles large.
        {
          name: "beer",
          count: 3,
          panel: null,
          ingredients: [{ group: "alcohol", grams: 1_200, label: "beer", alternatives: [] }],
        },
        // One salad: mostly leaves, a drizzle of oil. Two dressed salads must
        // not clear the 4 tbsp/day olive oil criterion between them.
        {
          name: "green salad",
          count: 1,
          panel: null,
          ingredients: [
            { group: "vegetables", grams: 90, label: "leaves", alternatives: [] },
            { group: "olive_oil", grams: 8, label: "dressing", alternatives: [] },
          ],
        },
      ],
      other_meals_visible: false,
      notes: null,
    });

    expect(flat.items.map((item) => [item.dish, item.group, item.grams])).toEqual([
      ["beer", "alcohol", 1_200],
      ["green salad", "vegetables", 90],
      ["green salad", "olive_oil", 8],
    ]);
    // No arithmetic left to record. A client that finds a number here is
    // reading a server that still multiplied.
    expect(flat.items.every((item) => item.servings === null)).toBe(true);
    // The dishes survive alongside the flat list a shipped build still reads.
    expect(flat.dishes).toHaveLength(2);
  });
});

describe("meal refinement contract", () => {
  it("accepts a minimal delta against a numbered current list", () => {
    const request = refinementRequestSchema.parse({
      // A hand-typed row has no weight to send, and says so rather than
      // inventing one for the field.
      current: [
        { group: "white_meat", grams: 160, label: "chicken" },
        { group: "vegetables", grams: null, label: "salad" },
      ],
      note: "fried in butter",
    });
    expect(request.current).toHaveLength(2);
    expect(
      mealRevisionSchema.parse({
        add: [{ group: "butter", grams: 12, label: "butter", alternatives: [] }],
        revise: [],
        remove: [],
        notes: null,
      }).add[0]?.grams,
    ).toBe(12);
  });

  it("revises a weight, which is the correction that used to do nothing", () => {
    // A revise carrying a portion could not move a weighed item: grams win in
    // `effectiveServings`, so the delta applied and changed no score.
    const revision = mealRevisionSchema.parse({
      add: [],
      revise: [{ index: 1, group: "egg", grams: 100 }],
      remove: [],
      notes: null,
    });
    expect(revision.revise[0]?.grams).toBe(100);
  });
});

describe("stored recognition input", () => {
  it("accepts the note that changes the cache fingerprint", () => {
    const input = recognitionRequestSchema.parse({
      photoHash: "a".repeat(64),
      mimeType: "image/jpeg",
      imageBase64: "a".repeat(16),
      note: "fried in butter",
    });
    expect(input.note).toBe("fried in butter");
  });

  it("requires a separately hashed, privacy-filtered corpus crop", () => {
    const item = corpusItemRequestSchema.parse({
      mealId: "0198f222-aadb-7e00-8000-000000000002",
      sourcePhotoHash: "a".repeat(64),
      corpusHash: "b".repeat(64),
      mimeType: "image/jpeg",
      imageBase64: "a".repeat(16),
      consent: { granted: true, policyVersion: "research-v1", capturedAt: 1_754_300_000_000 },
      privacy: {
        cropMethod: "vision-saliency-v1",
        facesExcluded: true,
        otherMealsExcluded: true,
      },
    });
    expect(item.corpusHash).not.toBe(item.sourcePhotoHash);
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

describe("a panel is only usable with its unit", () => {
  const monster = {
    protein: 0,
    calories: 0,
    fat: 0,
    carbohydrate: 1,
    salt: 0.1,
    sodium: null,
    caffeine: 40,
    basis: "per_100ml" as const,
    net_ml: 355,
    net_g: null,
  };

  it("scales a per-100ml panel to the can, which is what was drunk", () => {
    const scaled = panelPerContainer(monster);
    expect(scaled?.caffeine).toBe(142);
    expect(scaled?.carbohydrate).toBe(3.55);
    expect(scaled?.basis).toBe("per_container");
  });

  it("derives sodium from the salt the label actually printed", () => {
    // Twice the model did this division itself, unasked and invisibly. It is
    // arithmetic, so it belongs here where it can be checked.
    const scaled = panelPerContainer(monster);
    expect(scaled?.salt).toBe(0.36);
    expect(scaled?.sodium).toBe(0.142);
  });

  it("leaves a printed sodium alone rather than overwriting it", () => {
    const american = { ...monster, salt: null, sodium: 0.2, basis: "per_container" as const };
    expect(panelPerContainer(american)?.sodium).toBe(0.2);
  });

  it("leaves a per-container panel alone", () => {
    const savas = { ...monster, basis: "per_container" as const, protein: 15, net_ml: 200 };
    expect(panelPerContainer(savas)?.protein).toBe(15);
  });

  it("refuses to guess the volume it was not given", () => {
    // Inventing the missing 355ml is the one thing worse than a number that
    // still carries the unit it was printed in.
    const noVolume = { ...monster, net_ml: null };
    expect(panelPerContainer(noVolume)?.caffeine).toBe(40);
    expect(panelPerContainer(noVolume)?.basis).toBe("per_100ml");
  });
});

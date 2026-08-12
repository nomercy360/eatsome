import { describe, expect, it } from "vitest";
import {
  ATWATER_TOLERANCE,
  atwaterDelta,
  corpusItemRequestSchema,
  ingestEventsRequestSchema,
  mealRecognitionJsonSchema,
  mealRecognitionSchema,
  mealRevisionSchema,
  normalizePanels,
  panelPerContainer,
  recognitionRequestSchema,
  refinementRequestSchema,
} from "./contracts";

const composition = {
  protein: 4.5,
  fat: 3.2,
  carbohydrate: 12.1,
  kcal: 95,
  sodium_mg: 210,
};

describe("meal recognition contract", () => {
  it("requires a weight and a composition on every ingredient", () => {
    const parsed = mealRecognitionSchema.parse({
      dishes: [
        {
          name: "keema curry",
          count: 1,
          panel: null,
          ingredients: [
            {
              grams: 140,
              label: "minced meat",
              per_100g: composition,
              preparation: [],
              alternatives: [{ label: "beef mince", per_100g: composition }],
            },
          ],
        },
      ],
    });

    expect(parsed.dishes[0]?.ingredients[0]?.per_100g.kcal).toBe(95);
    // An alternative is priced too, so answering the one question the sentence
    // raises is a local swap rather than a second call.
    expect(parsed.dishes[0]?.ingredients[0]?.alternatives[0]?.per_100g).toEqual(composition);

    const jsonSchema = mealRecognitionJsonSchema();
    expect(jsonSchema).not.toHaveProperty("$schema");
    expect(JSON.stringify(jsonSchema)).toContain("per_100g");
    expect(JSON.stringify(jsonSchema)).toContain("sodium_mg");
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
            ingredients: [
              { label: "beer", per_100g: composition, preparation: [], alternatives: [] },
            ],
          },
        ],
      }),
    ).toThrow();
  });

  it("rejects an ingredient with no composition", () => {
    // The v21 counterpart of the rule above, and for the same reason: with
    // nothing to fall back to, a missing figure has to be loud. There is no
    // table behind this any more — a silently absent `per_100g` would be a meal
    // worth zero calories.
    expect(() =>
      mealRecognitionSchema.parse({
        dishes: [
          {
            name: "beer",
            count: 1,
            panel: null,
            ingredients: [{ label: "beer", grams: 500, preparation: [], alternatives: [] }],
          },
        ],
      }),
    ).toThrow();
  });

  it("keeps the four macronutrients consistent with the energy figure", () => {
    // The only check available with no table to compare against, and the
    // replacement for the unresolved-grams signal that used to make a bad
    // answer visible.
    expect(atwaterDelta(composition)).toBeLessThan(ATWATER_TOLERANCE);
    expect(atwaterDelta({ ...composition, kcal: 400 })).toBeGreaterThan(ATWATER_TOLERANCE);
    expect(atwaterDelta({ ...composition, kcal: 0 })).toBeNull();
  });

  it("passes weights through untouched and multiplies nothing", () => {
    const payload = normalizePanels({
      dishes: [
        // Three beers: the count says three and the grams already hold all
        // three. Multiplying here is what made one bowl of ramen 126 g of
        // protein — the model called the bowl large and the noodles large.
        {
          name: "beer",
          count: 3,
          panel: null,
          ingredients: [
            {
              grams: 1_200,
              label: "beer",
              per_100g: composition,
              preparation: [],
              alternatives: [],
            },
          ],
        },
      ],
    });

    expect(payload.dishes[0]?.ingredients[0]?.grams).toBe(1_200);
    expect(payload.dishes[0]?.count).toBe(3);
  });
});

describe("meal refinement contract", () => {
  it("accepts a minimal delta against a numbered current list", () => {
    const request = refinementRequestSchema.parse({
      current: [
        { label: "chicken", grams: 160 },
        { label: "salad leaves", grams: 40 },
      ],
      note: "fried in butter",
    });
    expect(request.current).toHaveLength(2);
    expect(
      mealRevisionSchema.parse({
        add: [
          {
            label: "butter",
            grams: 12,
            per_100g: { protein: 0.9, fat: 81.1, carbohydrate: 0.1, kcal: 717, sodium_mg: 11 },
            preparation: [],
            alternatives: [],
          },
        ],
        revise: [],
        remove: [],
        notes: null,
      }).add[0]?.grams,
    ).toBe(12);
  });

  it("revises a weight, which is the correction that used to do nothing", () => {
    // A revise carrying a portion could not move a weighed item: grams won, so
    // the delta applied and changed no quantity anyone could see.
    const revision = mealRevisionSchema.parse({
      add: [],
      revise: [
        {
          index: 1,
          label: "boiled egg",
          grams: 100,
          per_100g: { protein: 12.6, fat: 10.6, carbohydrate: 1.1, kcal: 155, sodium_mg: 124 },
          preparation: ["boiled"],
        },
      ],
      remove: [],
      notes: null,
    });
    expect(revision.revise[0]?.grams).toBe(100);
  });

  it("refuses a revision that moves a food without restating its figures", () => {
    // Stored numbers plus editable rows can desync. A row renamed from
    // "chicken" to "fried chicken" whose composition stayed behind is worse
    // than an uncorrected one, because it looks corrected.
    expect(() =>
      mealRevisionSchema.parse({
        add: [],
        revise: [{ index: 1, label: "fried chicken", grams: 180, preparation: ["deep_fried"] }],
        remove: [],
        notes: null,
      }),
    ).toThrow();
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

  it("accepts a meal that is only words", () => {
    const input = recognitionRequestSchema.parse({
      said: "leftover lentil soup, big bowl",
    });
    expect(input.said).toBe("leftover lentil soup, big bowl");
    expect(input.photoHash).toBeUndefined();
  });

  it("accepts a photo with a caption and a note both", () => {
    const input = recognitionRequestSchema.parse({
      photoHash: "a".repeat(64),
      mimeType: "image/jpeg",
      imageBase64: "a".repeat(16),
      said: "2 of this at 11 am",
      note: "fried in butter",
    });
    expect(input.said).toBe("2 of this at 11 am");
    expect(input.note).toBe("fried in butter");
  });

  it("rejects a request carrying neither photograph nor message", () => {
    // An empty message must be a loud 400, not a model call about nothing.
    expect(() => recognitionRequestSchema.parse({})).toThrow();
    expect(() => recognitionRequestSchema.parse({ said: "   " })).toThrow();
    expect(() => recognitionRequestSchema.parse({ note: "fried in butter" })).toThrow();
  });

  it("rejects part of an image rather than reading it as text-only", () => {
    expect(() =>
      recognitionRequestSchema.parse({
        photoHash: "a".repeat(64),
        said: "soup",
      }),
    ).toThrow();
    expect(() =>
      recognitionRequestSchema.parse({
        mimeType: "image/jpeg",
        imageBase64: "a".repeat(16),
        said: "soup",
      }),
    ).toThrow();
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
                  kind: "beef",
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
                    kind: "poultry",
                    portion: "medium",
                    label: "minced meat",
                    modelAlternatives: [{ label: "beef mince", kind: "beef" }],
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

  it("accepts a meal logged in words, linked to its chat bubble", () => {
    // `mealEventDataSchema` is strict, so a field the app writes and this
    // schema does not name 400s every sync from that build — the same failure
    // grams, servings and dish once had. `text` and `messageID` arrive with
    // chat-first logging and must be named here before a device sends one.
    const request = ingestEventsRequestSchema.parse({
      deviceId: "iphone-owner",
      events: [
        {
          id: "0198f222-aadb-7e00-8000-000000000004",
          occurredAt: 1_754_300_000_000,
          recordedAt: 1_754_300_001_000,
          payload: {
            kind: "meal_logged",
            data: {
              id: "0198f222-aadb-7e00-8000-000000000005",
              eatenAt: 1_754_300_000_000,
              items: [
                {
                  id: "0198f222-aadb-7e00-8000-000000000006",
                  kind: "legume",
                  portion: "medium",
                  label: "lentil soup",
                  grams: 400,
                },
              ],
              source: "text",
              messageID: "0198f222-aadb-7e00-8000-000000000007",
              wasCorrected: false,
            },
          },
        },
      ],
    });
    expect(request.events).toHaveLength(1);
  });

  it("accepts every field the Swift meal log currently writes", () => {
    const request = ingestEventsRequestSchema.parse({
      deviceId: "iphone-owner",
      events: [
        {
          id: "0198f222-aadb-7e00-8000-000000000008",
          occurredAt: 1_754_300_000_000,
          recordedAt: 1_754_300_001_000,
          payload: {
            kind: "meal_logged",
            data: {
              id: "0198f222-aadb-7e00-8000-000000000009",
              eatenAt: 1_754_300_000_000,
              items: [
                {
                  id: "0198f222-aadb-7e00-8000-000000000010",
                  kind: "fruit",
                  portion: "medium",
                  dish: "Fruit plate",
                  grams: 80,
                },
              ],
              source: "recipe",
              share: "taste",
              recipeID: "0198f222-aadb-7e00-8000-000000000011",
              storedDishes: [
                {
                  id: "0198f222-aadb-7e00-8000-000000000012",
                  name: "",
                  count: 1,
                  size: "medium",
                  panel: { protein: 1, net_g: 80 },
                  items: [
                    {
                      id: "0198f222-aadb-7e00-8000-000000000010",
                      kind: "fruit",
                      portion: "medium",
                      grams: 80,
                    },
                  ],
                },
              ],
              wasCorrected: false,
            },
          },
        },
      ],
    });
    expect(request.events[0]?.payload.data.share).toBe("taste");
  });

  it("accepts the rest of the append-only log, not only meals", () => {
    for (const kind of ["message_sent", "message_deleted"]) {
      expect(
        ingestEventsRequestSchema.safeParse({
          deviceId: "iphone-owner",
          events: [
            {
              id: "0198f222-aadb-7e00-8000-000000000013",
              occurredAt: 1,
              recordedAt: 2,
              payload: { kind, data: {} },
            },
          ],
        }).success,
      ).toBe(true);
    }
  });

  it("rejects retired settings events", () => {
    for (const kind of ["habits_updated", "diet_saved", "diet_selected"]) {
      expect(
        ingestEventsRequestSchema.safeParse({
          deviceId: "iphone-owner",
          events: [
            {
              id: "0198f222-aadb-7e00-8000-000000000013",
              occurredAt: 1,
              recordedAt: 2,
              payload: { kind, data: {} },
            },
          ],
        }).success,
      ).toBe(false);
    }
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

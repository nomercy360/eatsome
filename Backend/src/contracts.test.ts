import { describe, expect, it } from "vitest";
import {
  ATWATER_TOLERANCE,
  atwaterDelta,
  atwaterFailures,
  compositionSchema,
  ENERGY_PER_GRAM,
  eventKinds,
  eventPullQuerySchema,
  ingestEventsRequestSchema,
  MEAL_SCHEMA_VERSION,
  mealEventDataSchema,
  mealRecognitionJsonSchema,
  mealRecognitionSchema,
  mealRevisionSchema,
  normalizePanels,
  nutritionPanelSchema,
  panelBases,
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
  alcohol: 0,
  caffeine_mg: 0,
};

/** A pint of lager, per 100 g: almost all of its energy is ethanol. */
const lager = {
  protein: 0.5,
  fat: 0,
  carbohydrate: 3.6,
  kcal: 43,
  sodium_mg: 4,
  alcohol: 3.9,
  caffeine_mg: 0,
};

/**
 * A meal exactly as `JSONEncoder` writes `MealEntry` in EatsomeCore.
 *
 * Every detail here is load-bearing and none of it is a stylistic choice:
 *
 *  - **Upper-case UUIDs.** Swift's `UUID` encodes that way, and a validator
 *    that only accepted lower case would reject every real meal.
 *  - **`per_100g`, `sodium_mg`, `caffeine_mg`.** The `CodingKeys` on `MealItem`
 *    and `Nutrients` spell them so.
 *  - **`provenance.sodium`, not `sodium_mg`.** `NutrientProvenance` uses the
 *    default keys — it names a figure, not a unit.
 *  - **No nil fields.** Swift omits an optional that is nil rather than writing
 *    null, so `brand`, `note`, `share` and the rest are simply absent here.
 *  - **`sizes` and `alternatives` present but with no `basis`.** The stored
 *    `FoodSize` has no `basis`: that is a fact about the model's answer, and it
 *    is dropped on the way into storage. The stored alternative and size both
 *    carry an `id`, which the wire forms do not.
 *
 * If this drifts from Swift, `projectMealMedia` throws and sync 400s — which is
 * the point. The failure it replaced was silent: no `meal_media` row, and the
 * orphan sweep deleting the photograph a day later.
 */
function swiftMeal(overrides: Record<string, unknown> = {}) {
  return {
    id: "0198F222-AADB-7E00-8000-000000000021",
    schemaVersion: 1,
    eatenAt: 1_754_300_000_000,
    dishes: [
      {
        id: "0198F222-AADB-7E00-8000-000000000022",
        name: "Italian B.M.T.",
        count: 2,
        share: "part",
        panel: { kcal: 480, protein: 20, salt: 2.1 },
        items: [
          {
            id: "0198F222-AADB-7E00-8000-000000000023",
            label: "Italian B.M.T.",
            preparation: [],
            grams: 400,
            per_100g: composition,
            provenance: {
              protein: "model",
              fat: "model",
              carbohydrate: "model",
              kcal: "model",
              sodium: "model",
              alcohol: "model",
              caffeine: "model",
            },
            alternatives: [
              {
                id: "0198F222-AADB-7E00-8000-000000000024",
                label: "Roast Beef",
                grams: 420,
                per_100g: composition,
              },
            ],
            brand: "Subway",
            sizes: [
              {
                id: "0198F222-AADB-7E00-8000-000000000025",
                label: "15cm Regular",
                grams: 200,
                per_100g: composition,
              },
              {
                id: "0198F222-AADB-7E00-8000-000000000026",
                label: "30cm Footlong",
                grams: 400,
                per_100g: composition,
              },
            ],
          },
        ],
      },
    ],
    source: "text",
    wasCorrected: true,
    ...overrides,
  };
}

describe("the stored meal is the Swift type, mirrored", () => {
  it("accepts a meal exactly as EatsomeCore encodes one", () => {
    const parsed = mealEventDataSchema.parse(swiftMeal());
    expect(parsed.schemaVersion).toBe(MEAL_SCHEMA_VERSION);
    expect(parsed.dishes[0]?.share).toBe("part");
    expect(parsed.dishes[0]?.panel?.kcal).toBe(480);
    expect(parsed.dishes[0]?.items[0]?.sizes).toHaveLength(2);
    expect(parsed.dishes[0]?.items[0]?.alternatives[0]?.grams).toBe(420);
  });

  it("accepts the fields the encoder only sometimes writes", () => {
    const parsed = mealEventDataSchema.parse(
      swiftMeal({
        source: "photo",
        photoHash: "a".repeat(64),
        note: "fried in butter",
        personalNote: "worth ordering again",
        share: "whole",
        messageID: "0198F222-AADB-7E00-8000-000000000027",
        nutritionOverride: {
          protein: 30,
          fat: 20,
          carbohydrate: 60,
          kcal: 540,
          sodium_mg: 900,
          alcohol: 0,
          caffeine_mg: 0,
        },
      }),
    );
    expect(parsed.personalNote).toBe("worth ordering again");
    expect(parsed.nutritionOverride?.sodium_mg).toBe(900);
  });

  it("refuses a meal with no schema version, and one from another version", () => {
    // The failure this exists to prevent is a reader guessing. An unversioned
    // meal decoded as whatever the current shape happens to be is how a
    // sandwich came out at 62 kcal instead of as an error somebody could see.
    const { schemaVersion: _omitted, ...unversioned } = swiftMeal();
    expect(mealEventDataSchema.safeParse(unversioned).success).toBe(false);
    expect(mealEventDataSchema.safeParse(swiftMeal({ schemaVersion: 21 })).success).toBe(false);
    expect(mealEventDataSchema.safeParse(swiftMeal({ schemaVersion: "1" })).success).toBe(false);
  });

  it("refuses a field the Swift type does not write", () => {
    // Strict, so drift is a 400 on the batch rather than a skipped projection.
    // Every one of these was a real field once; none of them is written now,
    // and a build still sending one is a build that predates the rewrite.
    for (const stale of [
      "recognitionEvidence",
      "recognitionRating",
      "recognitionID",
      "recipeID",
      "items",
      "storedDishes",
    ]) {
      expect(mealEventDataSchema.safeParse(swiftMeal({ [stale]: null })).success).toBe(false);
    }
  });

  it("refuses a retired source and a retired provenance", () => {
    expect(mealEventDataSchema.safeParse(swiftMeal({ source: "recipe" })).success).toBe(false);
    const meal = swiftMeal() as never as {
      dishes: [{ items: [{ provenance: Record<string, string> }] }];
    };
    // `published` had a `SourceRef` and no writer: grounded recognition returns
    // better numbers than a fetched page and returns them with no URL.
    meal.dishes[0].items[0].provenance.kcal = "published";
    expect(mealEventDataSchema.safeParse(meal).success).toBe(false);
  });

  it("takes a UUID in either case, because Swift only ever sends one of them", () => {
    // `JSONEncoder` writes `UUID` in upper case. A validator that only accepted
    // the lower-case spelling would reject every meal the app has ever written,
    // and would do it as a 400 on sync rather than anywhere a reader looks.
    const id = "0198F222-AADB-7E00-8000-000000000021";
    expect(mealEventDataSchema.safeParse(swiftMeal({ id })).success).toBe(true);
    expect(mealEventDataSchema.safeParse(swiftMeal({ id: id.toLowerCase() })).success).toBe(true);
    expect(mealEventDataSchema.safeParse(swiftMeal({ id: "not-a-uuid" })).success).toBe(false);
  });
});

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
              brand: null,
              sizes: [],
              alternatives: [{ label: "beef mince", grams: 140, per_100g: composition }],
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

  it("carries a menu item's brand and the sizes its chain sells", () => {
    // The two axes a chain's product is corrected on. Weight is the control for
    // a bowl of rice and a meaningless one for a Big Mac — nobody ate 217 g of
    // Big Mac — so a branded row is corrected by item, size or count instead.
    const parsed = mealRecognitionSchema.parse({
      dishes: [
        {
          name: "Italian B.M.T.",
          count: 1,
          panel: null,
          ingredients: [
            {
              grams: 229,
              label: "Italian B.M.T.",
              per_100g: composition,
              preparation: [],
              brand: "Subway",
              sizes: [
                { label: "15cm Regular", grams: 229, per_100g: composition, basis: "published" },
                // A Footlong is nowhere printed: Subway publishes the Regular
                // and everyone doubles it, which is why the basis is stored.
                { label: "30cm Footlong", grams: 458, per_100g: composition, basis: "derived" },
              ],
              alternatives: [{ label: "Spicy Italian", grams: 224, per_100g: composition }],
            },
          ],
        },
      ],
    });

    const item = parsed.dishes[0]?.ingredients[0];
    expect(item?.brand).toBe("Subway");
    expect(item?.sizes.map((size) => size.basis)).toEqual(["published", "derived"]);
    // A rival carries its own weight, so a swap does not price a tuna sub at
    // whatever the turkey sub happened to weigh.
    expect(item?.alternatives[0]?.grams).toBe(224);
  });

  it("rejects an ingredient with no weight", () => {
    // While `grams` was nullable behind a `portion` fallback, the production
    // Gemini schema omitted the field entirely and every answer still parsed —
    // the failure was silent for a month.
    expect(() =>
      mealRecognitionSchema.parse({
        dishes: [
          {
            name: "beer",
            count: 1,
            panel: null,
            ingredients: [
              {
                label: "beer",
                per_100g: composition,
                preparation: [],
                brand: null,
                sizes: [],
                alternatives: [],
              },
            ],
          },
        ],
      }),
    ).toThrow();
  });

  it("rejects an ingredient with no composition", () => {
    // The counterpart of the rule above, for the same reason: with nothing to
    // fall back to, a missing figure has to be loud. There is no table behind
    // this — a silently absent `per_100g` would be a meal worth zero calories.
    expect(() =>
      mealRecognitionSchema.parse({
        dishes: [
          {
            name: "beer",
            count: 1,
            panel: null,
            ingredients: [
              {
                label: "beer",
                grams: 500,
                preparation: [],
                brand: null,
                sizes: [],
                alternatives: [],
              },
            ],
          },
        ],
      }),
    ).toThrow();
  });

  it("keeps the macronutrients consistent with the energy figure", () => {
    // The only check available with no table to compare against, and the
    // replacement for the unresolved-grams signal that used to make a bad
    // answer visible.
    expect(atwaterDelta(composition)).toBeLessThan(ATWATER_TOLERANCE);
    expect(atwaterDelta({ ...composition, kcal: 400 })).toBeGreaterThan(ATWATER_TOLERANCE);
    expect(atwaterDelta({ ...composition, kcal: 0 })).toBeNull();
  });

  it("names which foods in an answer disagree with themselves", () => {
    // What the recognition path logs on. It was a test-only check until then:
    // stated in the prompt, asserted against fixtures, and never once looked at
    // for a real answer.
    const answer = mealRecognitionSchema.parse({
      dishes: [
        {
          name: "lunch",
          count: 1,
          panel: null,
          ingredients: [
            {
              grams: 100,
              label: "rice",
              per_100g: composition,
              preparation: [],
              brand: null,
              sizes: [],
              alternatives: [],
            },
            {
              grams: 100,
              label: "mystery sauce",
              per_100g: { ...composition, kcal: 400 },
              preparation: [],
              brand: null,
              sizes: [],
              alternatives: [],
            },
          ],
        },
      ],
    });
    const failures = atwaterFailures(answer);
    expect(failures).toHaveLength(1);
    expect(failures[0]?.label).toBe("mystery sauce");
    expect(failures[0]?.dish).toBe("lunch");
    expect(atwaterFailures({ dishes: [] })).toEqual([]);
  });

  it("counts ethanol at 7 kcal/g, which is what stopped the check firing on every beer", () => {
    // Without the alcohol column, protein × 4 + carbohydrate × 4 + fat × 9 on a
    // lager is 16 kcal against a stated 43 — a 63% delta, and the self-check
    // called every drink garbled. With it the same figures reconcile.
    expect(atwaterDelta(lager)).toBeLessThan(ATWATER_TOLERANCE);
    expect(atwaterDelta({ ...lager, alcohol: 0 })).toBeGreaterThan(0.5);
    // Mirrors `Nutrients.energyPerGram` in EatsomeCore, figure for figure.
    expect(ENERGY_PER_GRAM).toEqual({ protein: 4, carbohydrate: 4, fat: 9, alcohol: 7 });
  });

  it("requires all seven composition figures, so zero is a statement and not a default", () => {
    const { alcohol: _a, ...withoutAlcohol } = composition;
    const { caffeine_mg: _c, ...withoutCaffeine } = composition;
    expect(compositionSchema.safeParse(withoutAlcohol).success).toBe(false);
    expect(compositionSchema.safeParse(withoutCaffeine).success).toBe(false);
    expect(compositionSchema.safeParse(composition).success).toBe(true);
    const jsonSchema = JSON.stringify(mealRecognitionJsonSchema());
    expect(jsonSchema).toContain('"alcohol"');
    expect(jsonSchema).toContain('"caffeine_mg"');
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
              brand: null,
              sizes: [],
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
      dishes: [{ name: "chicken salad", count: 1, item_indices: [1, 2] }],
      note: "fried in butter",
    });
    expect(request.current).toHaveLength(2);
    expect(
      mealRevisionSchema.parse({
        add: [
          {
            label: "butter",
            grams: 12,
            per_100g: {
              protein: 0.9,
              fat: 81.1,
              carbohydrate: 0.1,
              kcal: 717,
              sodium_mg: 11,
              alcohol: 0,
              caffeine_mg: 0,
            },
            preparation: [],
            alternatives: [],
          },
        ],
        revise: [],
        dish_counts: [],
        dish_names: [],
        remove: [],
        notes: null,
      }).add[0]?.grams,
    ).toBe(12);
  });

  it("requires the dish list, which is what a count correction refers to", () => {
    // It was optional "for older clients". There are none, and an absent dish
    // list means "4 of these" has nothing to point at.
    expect(
      refinementRequestSchema.safeParse({
        current: [{ label: "chicken", grams: 160 }],
        note: "fried in butter",
      }).success,
    ).toBe(false);
  });

  it("weighs an added item's alternatives as well as pricing them", () => {
    // One alternative shape across recognition, correction and storage. The
    // correction's used to carry a label and a composition and no weight, so a
    // rival could only ever be applied at the weight of the food it replaced —
    // the same rename-cannot-re-price failure, one level down.
    const withGrams = {
      label: "maple syrup",
      grams: 20,
      per_100g: { ...composition, kcal: 260, carbohydrate: 67 },
    };
    const revision = (alternatives: unknown[]) => ({
      add: [
        {
          label: "honey",
          grams: 20,
          per_100g: { ...composition, kcal: 304, carbohydrate: 82 },
          preparation: [],
          alternatives,
        },
      ],
      revise: [],
      dish_counts: [],
      dish_names: [],
      remove: [],
      notes: null,
    });
    expect(mealRevisionSchema.parse(revision([withGrams])).add[0]?.alternatives[0]?.grams).toBe(20);
    const { grams: _dropped, ...noGrams } = withGrams;
    expect(mealRevisionSchema.safeParse(revision([noGrams])).success).toBe(false);
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
          per_100g: {
            protein: 12.6,
            fat: 10.6,
            carbohydrate: 1.1,
            kcal: 155,
            sodium_mg: 124,
            alcohol: 0,
            caffeine_mg: 0,
          },
          preparation: ["boiled"],
        },
      ],
      dish_counts: [],
      dish_names: [],
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
        dish_counts: [],
        dish_names: [],
        remove: [],
        notes: null,
      }),
    ).toThrow();
  });

  it("carries structured dish counts for phrases such as four of these", () => {
    const request = refinementRequestSchema.parse({
      current: [{ label: "SAVAS milk protein drink", grams: 200 }],
      dishes: [{ name: "SAVAS milk protein drink", count: 1, item_indices: [1] }],
      note: "4 of these",
    });
    expect(request.dishes[0]?.count).toBe(1);

    const revision = mealRevisionSchema.parse({
      add: [],
      revise: [],
      dish_counts: [{ index: 1, count: 4 }],
      dish_names: [],
      remove: [],
      notes: null,
    });
    expect(revision.dish_counts[0]).toEqual({ index: 1, count: 4 });
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
      recognitionRequestSchema.parse({ photoHash: "a".repeat(64), said: "soup" }),
    ).toThrow();
    expect(() =>
      recognitionRequestSchema.parse({
        mimeType: "image/jpeg",
        imageBase64: "a".repeat(16),
        said: "soup",
      }),
    ).toThrow();
  });

  it("names no provider, because there is one", () => {
    // The field let a device run its own comparison through the proxy while
    // five providers were wired up. One remains, so a request naming one is
    // either stale or wrong, and either way should say so.
    expect(recognitionRequestSchema.safeParse({ said: "soup", provider: "gemini" }).success).toBe(
      false,
    );
  });
});

describe("event sync contract", () => {
  const envelope = (kind: string, data: unknown) => ({
    deviceId: "iphone-owner",
    events: [
      {
        id: "0198F222-AADB-7E00-8000-000000000003",
        occurredAt: 1_754_300_000_000,
        recordedAt: 1_754_300_001_000,
        payload: { kind, data },
      },
    ],
  });

  it("defaults a pull to a bounded page and refuses an unbounded one", () => {
    // Sync is two-way and merges by id — the phone pulls pages rather than
    // declaring which ids it holds and having the server delete the rest. That
    // reconcile made the last device to sync the definition of the account's
    // history, and deleted the other phone's meals to get there.
    expect(eventPullQuerySchema.parse({}).limit).toBe(100);
    expect(eventPullQuerySchema.parse({ limit: "250" }).limit).toBe(250);
    expect(eventPullQuerySchema.safeParse({ limit: "501" }).success).toBe(false);
    expect(eventPullQuerySchema.safeParse({ limit: "0" }).success).toBe(false);
  });

  it("carries a whole meal through the envelope", () => {
    const request = ingestEventsRequestSchema.parse(envelope("meal_logged", swiftMeal()));
    expect(mealEventDataSchema.parse(request.events[0]?.payload.data).dishes).toHaveLength(1);
  });

  it("accepts the rest of the append-only log, not only meals", () => {
    for (const kind of eventKinds) {
      expect(ingestEventsRequestSchema.safeParse(envelope(kind, {})).success).toBe(true);
    }
  });

  it("keeps an event kind it has never heard of, because the mirror hands it back", () => {
    // A phone keeps an event from a newer build byte for byte and uploads it
    // whole; the pull endpoint hands the same bytes to the account's other
    // phones. Refusing an unknown kind here would 400 the batch containing it,
    // so a phone that had not updated would stop syncing the moment any phone
    // did — and `id` would no longer be what makes two logs converge.
    for (const kind of ["mood_noted", "period_logged"]) {
      expect(
        ingestEventsRequestSchema.safeParse(envelope(kind, { anything: [1, "x"] })).success,
      ).toBe(true);
    }
    // A name that is not a name is still refused.
    for (const notAName of ["", "Meal Logged", "meal-logged", "1st", "x".repeat(65)]) {
      expect(ingestEventsRequestSchema.safeParse(envelope(notAName, {})).success).toBe(false);
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
    alcohol: null,
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

  it("has no estimated basis any more: a panel is transcription, and caffeine is composition", () => {
    // `estimated_serving` let an unlabelled coffee carry a caffeine estimate in
    // the field reserved for read figures. Now that `caffeine_mg` sits on
    // `per_100g` there is nowhere on a panel for an estimate to hide, and a
    // client stamping `panel` provenance on whatever arrives here is right to.
    expect(panelBases).not.toContain("estimated_serving");
    expect(nutritionPanelSchema.safeParse({ ...monster, basis: "estimated_serving" }).success).toBe(
      false,
    );
  });

  it("refuses to guess the volume it was not given", () => {
    // Inventing the missing 355ml is the one thing worse than a number that
    // still carries the unit it was printed in.
    const noVolume = { ...monster, net_ml: null };
    expect(panelPerContainer(noVolume)?.caffeine).toBe(40);
    expect(panelPerContainer(noVolume)?.basis).toBe("per_100ml");
  });
});

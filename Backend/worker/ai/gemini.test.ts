import { describe, expect, it, vi } from "vitest";
import { mealRecognitionJsonSchema } from "../../src/contracts";
import type { Env } from "../env";
import { askGemini, geminiResponseSchema } from "./gemini";
import { revisionSpec } from "./revision";
import { hasImage } from "./types";

const env = {
  GEMINI_API_KEY: "gm-test",
  GEMINI_RECOGNITION_MODEL: "gemini-3.7-flash",
} as unknown as Env;

const CORRECTION = {
  current: [{ label: "chicken", grams: 200 }],
  dishes: [{ name: "chicken", count: 1, item_indices: [1] }],
  note: "fried",
};

const COMPOSITION_FIGURES = [
  "protein",
  "fat",
  "carbohydrate",
  "kcal",
  "sodium_mg",
  "alcohol",
  "caffeine_mg",
];

/** Walks to the one place both schemas describe an ingredient. */
function ingredientOf(schema: Record<string, unknown>) {
  const properties = schema.properties as Record<string, Record<string, unknown>>;
  const dish = (properties.dishes as { items: Record<string, unknown> }).items;
  const dishProperties = dish.properties as Record<string, Record<string, unknown>>;
  const item = (dishProperties.ingredients as { items: Record<string, unknown> }).items;
  return {
    dish,
    dishProperties,
    item,
    fields: item.properties as Record<string, Record<string, unknown>>,
  };
}

describe("the hand-written revision schema", () => {
  // The recognition schema has been guarded since v16 shipped a weighing prompt
  // that returned no weights. This one was not, and went a whole version asking
  // for `kind` and `composition_hints` after both were deleted — the identical
  // failure, one file over. Gemini emits exactly the properties a schema names.
  const spec = revisionSpec(CORRECTION);

  it("requires the figures a correction moves", () => {
    const schema = spec.responseSchema as Record<string, Record<string, never>>;
    const properties = schema.properties as unknown as Record<string, Record<string, unknown>>;
    for (const key of ["add", "revise"]) {
      const block = (properties[key] as { items: Record<string, unknown> }).items;
      expect(block.required).toContain("per_100g");
      expect(block.required).toContain("label");
      const fields = block.properties as Record<string, Record<string, unknown>>;
      expect(fields.per_100g.required).toEqual(COMPOSITION_FIGURES);
    }
  });

  it("weighs an added item's alternatives as well as pricing them", () => {
    // The stored `FoodAlternative` in EatsomeCore requires `grams`, so an
    // alternative that arrives without one either fails to decode or gets
    // applied at the weight of the food it is replacing. Same shape as
    // recognition's alternatives, same reason.
    const properties = spec.responseSchema.properties as Record<string, Record<string, unknown>>;
    const add = (properties.add as { items: Record<string, unknown> }).items;
    const alternative = (add.properties as Record<string, Record<string, unknown>>).alternatives
      .items as { required: string[]; properties: Record<string, Record<string, unknown>> };
    expect(alternative.required).toEqual(["label", "grams", "per_100g"]);
    expect(alternative.properties.grams.type).toBe("NUMBER");
    expect(alternative.properties.per_100g.required).toEqual(COMPOSITION_FIGURES);
  });

  it("carries nothing from the retired taxonomy", () => {
    const json = JSON.stringify(spec.responseSchema);
    expect(json).not.toContain("composition_hints");
    expect(json).not.toContain('"kind"');
    // Rejected outright by Gemini rather than ignored.
    expect(json).not.toContain("additionalProperties");
  });

  it("shows the model dish identity, count, and item membership", () => {
    const counted = revisionSpec({
      current: [{ label: "SAVAS milk protein drink", grams: 200 }],
      dishes: [{ name: "SAVAS milk protein drink", count: 1, item_indices: [1] }],
      note: "4 of these",
    });
    expect(counted.userPrompt).toContain("count 1, items 1");
    expect(counted.userPrompt).toContain("4 of these");
    expect(JSON.stringify(counted.responseSchema)).toContain("dish_counts");
  });
});

describe("search on the recognition call", () => {
  const spec = revisionSpec(CORRECTION);
  const empty = {
    add: [],
    revise: [],
    dish_counts: [],
    dish_names: [],
    remove: [],
    notes: null,
  };

  function captureBody(recognitionSearch: string) {
    const sent: { body?: Record<string, never> } = {};
    vi.stubGlobal("fetch", async (_url: string, init: { body: string }) => {
      sent.body = JSON.parse(init.body);
      return new Response(
        JSON.stringify({
          candidates: [{ content: { parts: [{ text: JSON.stringify(empty) }] } }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    });
    return { sent, env: { ...env, RECOGNITION_SEARCH: recognitionSearch } as Env };
  }

  it("offers search as a tool without demanding it", async () => {
    // Available, never forced. The model reaches for it on a branded product
    // and skips it on food nobody published, which is what makes it free on an
    // ordinary meal — there is no tool_choice here on purpose.
    const { sent, env: on } = captureBody("on");
    await askGemini(on, { said: "a subway footlong" }, spec);
    const body = sent.body as never as { tools?: unknown[]; generationConfig: object };
    expect(body.tools).toEqual([{ googleSearch: {} }]);
    expect(JSON.stringify(body.generationConfig)).not.toContain("tool_choice");
    vi.unstubAllGlobals();
  });

  it("sends no tools at all when the deployment has not asked for it", async () => {
    const { sent, env: off } = captureBody("");
    await askGemini(off, { said: "a subway footlong" }, spec);
    expect((sent.body as never as { tools?: unknown[] }).tools).toBeUndefined();
    vi.unstubAllGlobals();
  });
});

describe("a correction with no photograph", () => {
  const spec = revisionSpec({
    current: [{ label: "grilled cod", grams: 120 }],
    dishes: [{ name: "grilled cod", count: 1, item_indices: [1] }],
    note: "there were two eggs in it",
  });
  const answer = { add: [], revise: [], dish_counts: [], dish_names: [], remove: [], notes: null };

  /** Captures the body Gemini would have received. */
  function captureRequest() {
    const sent: { body?: Record<string, never> } = {};
    vi.stubGlobal("fetch", async (_url: string, init: { body: string }) => {
      sent.body = JSON.parse(init.body);
      return new Response(
        JSON.stringify({
          candidates: [{ content: { parts: [{ text: JSON.stringify(answer) }] } }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    });
    return sent;
  }

  it("omits the image part rather than sending an empty one", async () => {
    const sent = captureRequest();
    await askGemini(env, { note: "there were two eggs in it" }, spec);
    const parts = (sent.body as never as { contents: [{ parts: unknown[] }] }).contents[0].parts;
    // A zero-length image is a decode error at the vendor, not an absent image.
    expect(parts).toHaveLength(1);
    expect(JSON.stringify(parts)).not.toContain("inlineData");
    vi.unstubAllGlobals();
  });

  it("still sends the photograph when there is one", async () => {
    const sent = captureRequest();
    await askGemini(env, { mimeType: "image/jpeg", imageBase64: "abc", note: "x" }, spec);
    const parts = (sent.body as never as { contents: [{ parts: unknown[] }] }).contents[0].parts;
    expect(parts).toHaveLength(2);
    expect(JSON.stringify(parts)).toContain("inlineData");
    vi.unstubAllGlobals();
  });

  it("treats half an image as no image", () => {
    expect(hasImage({ imageBase64: "abc", mimeType: "image/jpeg" })).toBe(true);
    expect(hasImage({ imageBase64: "abc" })).toBe(false);
    expect(hasImage({ mimeType: "image/jpeg" })).toBe(false);
    expect(hasImage({})).toBe(false);
  });

  it("parses with the call's own parser rather than a shared one", async () => {
    // Recognition and correction are two contracts, and the call carries which
    // one it is. The indirection this replaced switched on a schema *name*.
    captureRequest();
    const result = await askGemini(env, {}, spec);
    expect(result.value).toEqual(answer);
    vi.unstubAllGlobals();
  });
});

describe("gemini response schema", () => {
  const schema = geminiResponseSchema();

  it("stays inside Gemini's OpenAPI subset", () => {
    const json = JSON.stringify(schema);
    // Rejected outright rather than ignored.
    expect(json).not.toContain("additionalProperties");
    expect(json).not.toContain("$schema");
    expect(schema.type).toBe("OBJECT");
  });

  it("carries the same fields as the rest of the app", () => {
    const { dish, fields, item } = ingredientOf(schema);
    expect(dish.required).toEqual(["name", "count", "panel", "ingredients"]);

    expect(item.required).toEqual([
      "label",
      "grams",
      "per_100g",
      "preparation",
      "brand",
      "forks",
      "alternatives",
    ]);
    expect(fields.label.nullable).toBeUndefined();

    // An alternative is priced and weighed with the same blocks as the
    // ingredient. If it were not, choosing one in the client would swap the
    // name and leave the old numbers — the exact desync `per_100g` on a
    // revision exists to stop.
    const alternative = fields.alternatives.items as {
      required: string[];
      properties: Record<string, Record<string, unknown>>;
    };
    expect(alternative.required).toEqual(["label", "grams", "per_100g"]);
    expect(alternative.properties.per_100g.required).toEqual(COMPOSITION_FIGURES);
  });

  it("asks for composition on every ingredient", () => {
    // The v16 regression generalised. This schema is hand-written while the Zod
    // contract is derived, so it is the one that can quietly fall behind — and
    // it did once, for `grams`. With no table behind the app, a silently
    // missing `per_100g` would be a meal worth zero calories.
    const { fields } = ingredientOf(schema);
    expect(fields.per_100g.type).toBe("OBJECT");
    expect(fields.per_100g.required).toEqual(COMPOSITION_FIGURES);

    const contract = mealRecognitionJsonSchema() as {
      properties: {
        dishes: {
          items: {
            properties: {
              ingredients: { items: { properties: { per_100g: { required: string[] } } } };
            };
          };
        };
      };
    };
    expect(fields.per_100g.required).toEqual(
      contract.properties.dishes.items.properties.ingredients.items.properties.per_100g.required,
    );
  });

  it("asks which menu a branded row came off, and which choices were left open", () => {
    // Both are what a correction screen needs before it can decide what to
    // offer: chips and a stepper for something a menu lists, a weight for
    // anything else. A field Gemini is not told to emit is a field it drops.
    const { fields } = ingredientOf(schema);
    expect(fields.brand.nullable).toBe(true);
    const fork = fields.forks.items as {
      required: string[];
      properties: Record<string, Record<string, unknown>>;
    };
    expect(fork.required).toEqual(["axis", "chosen_from", "options"]);
    // The gate the app asks on. Without it the model offered sizes on "grande
    // oat milk latte" in three runs of four; with it, it said `stated`.
    expect(fork.properties.chosen_from.enum).toEqual(["stated", "seen", "assumed"]);
    const option = fork.properties.options.items as { required: string[] };
    expect(option.required).toEqual(["label", "grams", "per_100g", "basis", "chosen"]);
    // Gemini 400s when both this array and its options carry maxItems, and
    // accepts either alone; the inner bound lives in the prompt and in Zod.
    expect(fields.forks.maxItems).toBe(3);
    expect(fork.properties.options.maxItems).toBeUndefined();
  });

  it("asks for a weight on every ingredient", () => {
    // The v16 regression, as a test: the prompt asked for grams, the eval
    // schema had a slot for them, and this one did not, so Gemini emitted none
    // and the app interpreted a month of meals on the old ladder.
    const { fields, item } = ingredientOf(schema);
    expect(fields.grams.type).toBe("NUMBER");
    // Not nullable, and required: Gemini returns exactly the properties named
    // here, so anything optional is a field that can come back missing.
    expect(fields.grams.nullable).toBeUndefined();
    expect(item.required).toContain("grams");
  });

  it("names the same dish fields as the contract", () => {
    const contract = mealRecognitionJsonSchema() as {
      properties: { dishes: { items: { properties: object } } };
    };
    const { dish } = ingredientOf(schema);
    expect(Object.keys(dish.properties as object).sort()).toEqual(
      Object.keys(contract.properties.dishes.items.properties).sort(),
    );
  });

  it("names the same top-level fields as the contract", () => {
    // One property, and it is the whole response: `dishes`. There is no
    // discriminator — an empty list is a message that described no food, which
    // is what the "Couldn't read it" screen reads.
    const contract = mealRecognitionJsonSchema() as { properties: object; required: string[] };
    expect(Object.keys(schema.properties as object)).toEqual(Object.keys(contract.properties));
    expect(schema.propertyOrdering).toEqual(["dishes"]);
    expect(schema.required).toEqual(["dishes"]);
    expect(JSON.stringify(schema)).not.toContain("activit");
  });

  it("names the same panel fields as the contract, with no estimated basis left", () => {
    const contract = mealRecognitionJsonSchema() as {
      properties: {
        dishes: { items: { properties: { panel: { anyOf: Array<{ properties?: object }> } } } };
      };
    };
    const contractPanel = contract.properties.dishes.items.properties.panel.anyOf.find(
      (branch) => branch.properties,
    ) as { properties: object };
    const { dishProperties } = ingredientOf(schema);
    const panel = dishProperties.panel as { properties: Record<string, Record<string, unknown>> };
    expect(Object.keys(panel.properties).sort()).toEqual(
      Object.keys(contractPanel.properties).sort(),
    );
    expect(panel.properties.basis.enum).not.toContain("estimated_serving");
  });

  it("names the same ingredient fields as the contract", () => {
    // The drift guard, and now the only thing keeping
    // `mealRecognitionJsonSchema()` alive: no provider is handed the derived
    // schema any more, so its whole job is to be the copy this one is compared
    // against. Delete it and a field added to the Zod contract and forgotten
    // here becomes a silent month again.
    const contract = mealRecognitionJsonSchema() as {
      properties: {
        dishes: { items: { properties: { ingredients: { items: { properties: object } } } } };
      };
    };
    const contractFields = Object.keys(
      contract.properties.dishes.items.properties.ingredients.items.properties,
    ).sort();
    const { item } = ingredientOf(schema);
    expect(Object.keys(item.properties as object).sort()).toEqual(contractFields);
  });
});

import { describe, expect, it, vi } from "vitest";
import { mealRecognitionJsonSchema } from "../../src/contracts";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { geminiResponseSchema, requestGeminiRecognition } from "./gemini";
import { apiKeyFor, modelFor, resolveProvider } from "./recognize";
import { revisionSpec } from "./revision";
import { hasImage } from "./types";

const env = {
  OPENAI_API_KEY: "sk-test",
  GEMINI_API_KEY: "",
  ANTHROPIC_API_KEY: "",
  QWEN_API_KEY: "",
  ANTHROPIC_RECOGNITION_MODEL: "claude-haiku-4-5-20251001",
  QWEN_RECOGNITION_MODEL: "qwen3.7-flash",
  OPENAI_RECOGNITION_MODEL: "gpt-5.6-luna",
  GEMINI_RECOGNITION_MODEL: "gemini-3.6-flash",
  RECOGNITION_PROVIDER: "openai",
} as unknown as Env;

describe("provider selection", () => {
  it("takes the request's choice over the deployment default", () => {
    expect(resolveProvider(env)).toBe("openai");
    expect(resolveProvider(env, "gemini")).toBe("gemini");
    expect(resolveProvider({ ...env, RECOGNITION_PROVIDER: "gemini" } as Env)).toBe("gemini");
  });

  it("falls back to openai when the deployment names nothing", () => {
    expect(resolveProvider({ ...env, RECOGNITION_PROVIDER: undefined } as unknown as Env)).toBe(
      "openai",
    );
  });

  it("rejects a provider it does not have", () => {
    expect(() => resolveProvider(env, "mistral" as never)).toThrow(HttpError);
  });

  it("keeps each provider's model and key apart, which is what keeps the cache honest", () => {
    expect(modelFor(env, "openai")).toBe("gpt-5.6-luna");
    expect(modelFor(env, "gemini")).toBe("gemini-3.6-flash");
    expect(modelFor(env, "anthropic")).toBe("claude-haiku-4-5-20251001");
    expect(modelFor(env, "qwen")).toBe("qwen3.7-flash");
    expect(apiKeyFor(env, "openai")).toBe("sk-test");
    expect(apiKeyFor(env, "gemini")).toBe("");
  });
});

describe("the hand-written revision schema", () => {
  // The recognition schema has been guarded since v16 shipped a weighing prompt
  // that returned no weights. This one was not, and went a whole version asking
  // for `kind` and `composition_hints` after both were deleted — the identical
  // failure, one file over. Gemini emits exactly the properties a schema names.
  const spec = revisionSpec({ current: [{ label: "chicken", grams: 200 }], note: "fried" });

  it("requires the figures a correction moves", () => {
    const schema = spec.geminiSchema as Record<string, Record<string, never>>;
    const properties = schema.properties as unknown as Record<string, Record<string, unknown>>;
    for (const key of ["add", "revise"]) {
      const block = (properties[key] as { items: Record<string, unknown> }).items;
      expect(block.required).toContain("per_100g");
      expect(block.required).toContain("label");
      const fields = block.properties as Record<string, Record<string, unknown>>;
      expect(fields.per_100g.required).toEqual([
        "protein",
        "fat",
        "carbohydrate",
        "kcal",
        "sodium_mg",
      ]);
    }
  });

  it("carries nothing from the retired taxonomy", () => {
    const json = JSON.stringify(spec.geminiSchema);
    expect(json).not.toContain("composition_hints");
    expect(json).not.toContain('"kind"');
    // Rejected outright by Gemini rather than ignored.
    expect(json).not.toContain("additionalProperties");
  });
});

describe("search on the recognition call", () => {
  const spec = revisionSpec({ current: [{ label: "x", grams: 1 }], note: "y" });

  function captureBody(recognitionSearch: string) {
    const sent: { body?: Record<string, never> } = {};
    vi.stubGlobal("fetch", async (_url: string, init: { body: string }) => {
      sent.body = JSON.parse(init.body);
      return new Response(
        JSON.stringify({
          candidates: [
            {
              content: {
                parts: [{ text: JSON.stringify({ add: [], revise: [], remove: [], notes: null }) }],
              },
            },
          ],
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
    await requestGeminiRecognition(on, { said: "a subway footlong" }, spec);
    const body = sent.body as never as { tools?: unknown[]; generationConfig: object };
    expect(body.tools).toEqual([{ googleSearch: {} }]);
    expect(JSON.stringify(body.generationConfig)).not.toContain("tool_choice");
    vi.unstubAllGlobals();
  });

  it("sends no tools at all when the deployment has not asked for it", async () => {
    const { sent, env: off } = captureBody("");
    await requestGeminiRecognition(off, { said: "a subway footlong" }, spec);
    expect((sent.body as never as { tools?: unknown[] }).tools).toBeUndefined();
    vi.unstubAllGlobals();
  });
});

describe("a correction with no photograph", () => {
  const spec = revisionSpec({
    current: [{ label: "grilled cod", grams: 120 }],
    note: "there were two eggs in it",
  });
  const answer = { add: [], revise: [], remove: [], notes: null };

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
    await requestGeminiRecognition(env, { note: "there were two eggs in it" }, spec);
    const parts = (sent.body as never as { contents: [{ parts: unknown[] }] }).contents[0].parts;
    // A zero-length image is a decode error at the vendor, not an absent image.
    expect(parts).toHaveLength(1);
    expect(JSON.stringify(parts)).not.toContain("inlineData");
    vi.unstubAllGlobals();
  });

  it("still sends the photograph when there is one", async () => {
    const sent = captureRequest();
    await requestGeminiRecognition(
      env,
      { mimeType: "image/jpeg", imageBase64: "abc", note: "x" },
      spec,
    );
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
    const properties = schema.properties as Record<string, Record<string, unknown>>;
    const dish = (properties.dishes as { items: Record<string, unknown> }).items;
    const dishProperties = dish.properties as Record<string, Record<string, unknown>>;
    expect(dish.required).toEqual(["name", "count", "panel", "ingredients"]);
    const item = (dishProperties.ingredients as { items: Record<string, unknown> }).items;
    const itemProperties = item.properties as Record<string, Record<string, unknown>>;

    expect(item.required).toEqual([
      "label",
      "grams",
      "per_100g",
      "preparation",
      "brand",
      "sizes",
      "alternatives",
    ]);
    expect(itemProperties.label.nullable).toBeUndefined();

    // An alternative is priced with the same block as the ingredient. If it
    // were not, choosing one in the client would swap the name and leave the
    // old numbers — the exact desync `per_100g` on a revision exists to stop.
    const alternative = itemProperties.alternatives.items as {
      required: string[];
      properties: Record<string, Record<string, unknown>>;
    };
    expect(alternative.required).toEqual(["label", "grams", "per_100g"]);
    expect(alternative.properties.per_100g.required).toEqual([
      "protein",
      "fat",
      "carbohydrate",
      "kcal",
      "sodium_mg",
    ]);
  });

  it("asks for composition on every ingredient", () => {
    // The v16 regression generalised. This schema is hand-written while every
    // other provider derives theirs from the Zod contract, so it is the one
    // that can quietly fall behind — and it did once, for `grams`. With no
    // table behind the app any more, a silently missing `per_100g` would be a
    // meal worth zero calories rather than a meal on the old ladder.
    const properties = schema.properties as Record<string, Record<string, unknown>>;
    const dish = (properties.dishes as { items: Record<string, unknown> }).items;
    const dishProperties = dish.properties as Record<string, Record<string, unknown>>;
    const item = (dishProperties.ingredients as { items: Record<string, unknown> }).items;
    const itemProperties = item.properties as Record<string, Record<string, unknown>>;
    expect(itemProperties.per_100g.type).toBe("OBJECT");
    expect(itemProperties.per_100g.required).toEqual([
      "protein",
      "fat",
      "carbohydrate",
      "kcal",
      "sodium_mg",
    ]);
  });

  it("asks which menu a branded row came off, and in what sizes", () => {
    // Both are what a correction screen needs before it can decide what to
    // offer: chips and a stepper for something a menu lists, a weight for
    // anything else. A field Gemini is not told to emit is a field it drops.
    const properties = schema.properties as Record<string, Record<string, unknown>>;
    const dish = (properties.dishes as { items: Record<string, unknown> }).items;
    const dishProperties = dish.properties as Record<string, Record<string, unknown>>;
    const item = (dishProperties.ingredients as { items: Record<string, unknown> }).items;
    const fields = item.properties as Record<string, Record<string, unknown>>;

    expect(fields.brand.nullable).toBe(true);
    const size = fields.sizes.items as { required: string[] };
    expect(size.required).toEqual(["label", "grams", "per_100g", "basis"]);
    // Six, because Yoshinoya sells a gyudon in six.
    expect(fields.sizes.maxItems).toBe(6);
  });

  it("asks for a weight on every ingredient", () => {
    // The v16 regression, as a test. This schema is hand-written while every
    // other provider derives theirs from the Zod contract, so it is the one
    // that can quietly fall behind — and it did: the prompt asked for grams,
    // the eval schema had a slot for them, and this one did not, so Gemini
    // emitted none and the app interpreted a month of meals on the old ladder.
    const properties = schema.properties as Record<string, Record<string, unknown>>;
    const dish = (properties.dishes as { items: Record<string, unknown> }).items;
    const dishProperties = dish.properties as Record<string, Record<string, unknown>>;
    const item = (dishProperties.ingredients as { items: Record<string, unknown> }).items;
    const itemProperties = item.properties as Record<string, Record<string, unknown>>;

    expect(itemProperties.grams.type).toBe("NUMBER");
    // Not nullable, and required: Gemini returns exactly the properties named
    // here, so anything optional is a field that can come back missing.
    expect(itemProperties.grams.nullable).toBeUndefined();
    expect(item.required).toContain("grams");
  });

  it("names the same dish fields as the contract every other provider gets", () => {
    const contract = mealRecognitionJsonSchema() as {
      properties: { dishes: { items: { properties: object } } };
    };
    const properties = schema.properties as Record<string, Record<string, unknown>>;
    const dish = (properties.dishes as { items: Record<string, unknown> }).items;

    expect(Object.keys(dish.properties as object).sort()).toEqual(
      Object.keys(contract.properties.dishes.items.properties).sort(),
    );
  });

  it("names the same ingredient fields as the contract every other provider gets", () => {
    // The drift guard. OpenAI, Anthropic, Qwen and OpenRouter are all handed
    // `mealRecognitionJsonSchema()`; only Gemini gets the copy above. Comparing
    // the two is what turns "someone forgot to add the field here as well" from
    // a silent month into a failing test.
    const contract = mealRecognitionJsonSchema() as {
      properties: {
        dishes: { items: { properties: { ingredients: { items: { properties: object } } } } };
      };
    };
    const contractFields = Object.keys(
      contract.properties.dishes.items.properties.ingredients.items.properties,
    ).sort();

    const properties = schema.properties as Record<string, Record<string, unknown>>;
    const dish = (properties.dishes as { items: Record<string, unknown> }).items;
    const dishProperties = dish.properties as Record<string, Record<string, unknown>>;
    const item = (dishProperties.ingredients as { items: Record<string, unknown> }).items;

    expect(Object.keys(item.properties as object).sort()).toEqual(contractFields);
  });
});

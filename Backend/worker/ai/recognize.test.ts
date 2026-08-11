import { describe, expect, it, vi } from "vitest";
import { foodGroups, mealRecognitionJsonSchema } from "../../src/contracts";
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

describe("a correction with no photograph", () => {
  const spec = revisionSpec({
    current: [{ group: "fish", grams: 120, label: null }],
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

  it("carries the same food groups as the rest of the app", () => {
    const properties = schema.properties as Record<string, Record<string, unknown>>;
    const dish = (properties.dishes as { items: Record<string, unknown> }).items;
    const dishProperties = dish.properties as Record<string, Record<string, unknown>>;
    expect(dish.required).toEqual(["name", "count", "panel", "ingredients"]);
    const item = (dishProperties.ingredients as { items: Record<string, unknown> }).items;
    const itemProperties = item.properties as Record<string, Record<string, unknown>>;

    expect(itemProperties.group.enum).toEqual([...foodGroups]);
    expect((itemProperties.alternatives.items as { enum: string[] }).enum).toEqual([...foodGroups]);
    expect(item.required).toEqual(["group", "grams", "label", "alternatives"]);
    // Nullability is a flag here, not a union type.
    expect(itemProperties.label.nullable).toBe(true);
    expect(properties.notes.nullable).toBe(true);
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

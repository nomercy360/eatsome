import { describe, expect, it } from "vitest";
import { foodGroups, portions } from "../../src/contracts";
import type { Env } from "../env";
import { HttpError } from "../lib/http-error";
import { geminiResponseSchema } from "./gemini";
import { apiKeyFor, modelFor, resolveProvider } from "./recognize";

const env = {
  OPENAI_API_KEY: "sk-test",
  GEMINI_API_KEY: "",
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
    expect(() => resolveProvider(env, "anthropic" as never)).toThrow(HttpError);
  });

  it("keeps each provider's model and key apart, which is what keeps the cache honest", () => {
    expect(modelFor(env, "openai")).toBe("gpt-5.6-luna");
    expect(modelFor(env, "gemini")).toBe("gemini-3.6-flash");
    expect(apiKeyFor(env, "openai")).toBe("sk-test");
    expect(apiKeyFor(env, "gemini")).toBe("");
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
    const item = (properties.items as { items: Record<string, unknown> }).items;
    const itemProperties = item.properties as Record<string, Record<string, unknown>>;

    expect(itemProperties.group.enum).toEqual([...foodGroups]);
    expect(itemProperties.portion.enum).toEqual([...portions]);
    expect((itemProperties.alternatives.items as { enum: string[] }).enum).toEqual([...foodGroups]);
    expect(item.required).toEqual(["group", "portion", "label", "alternatives"]);
    // Nullability is a flag here, not a union type.
    expect(itemProperties.label.nullable).toBe(true);
    expect(properties.notes.nullable).toBe(true);
  });
});

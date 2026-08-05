import { createHash } from "node:crypto";
import { readFileSync as read, readFileSync } from "node:fs";
import { join } from "node:path";
import type { RecognitionProvider } from "../src/contracts";
import { recognitionProviders } from "../src/contracts";
import { modelFor, requestMealRecognition } from "../worker/ai/recognize";
import type { RecognitionSpec } from "../worker/ai/spec";
import type { Env } from "../worker/env";
import { evalGeminiSchema, evalJsonSchema, SCHEMA_VERSION } from "./schema";

/**
 * The eval calls the same functions the proxy calls.
 *
 * That is the whole point of this file. The three providers structure output in
 * three different ways — strict `json_schema`, `responseSchema`, a forced tool
 * call — and a harness with its own request builder would measure its own
 * request builder. Anything that runs the models goes through here, including
 * the promptfoo config, so there is exactly one way a photo reaches a model.
 */
export type RunRecord = {
  caseId: string;
  /** The models.json entry, which is what reports and flips are keyed on. */
  modelId: string;
  tier: "candidate" | "ceiling";
  provider: RecognitionProvider;
  model: string;
  promptVersion: string;
  schemaVersion: string;
  /** What the reasoning budget was, because it is not comparable across
   *  vendors and a run without it recorded cannot be interpreted later. */
  reasoning?: string;
  /** The note sent with the photo, if this was a note-track run. */
  note?: string | null;
  run: number;
  ok: boolean;
  error?: string;
  /** The raw model JSON, so scoring can be rewritten without paying again. */
  raw?: string;
  latencyMs?: number;
  inputTokens?: number;
  outputTokens?: number;
};

const evalRoot = import.meta.dirname;

/**
 * The candidate contract, asked for by name.
 *
 * The app still ships the narrower one; the dataset is ahead of it on purpose
 * while the app is being built, and whatever survives these runs is what the
 * app schema should become. The prompt version and the schema version both
 * travel on every row, because a run under one contract is not comparable with
 * a run under the other.
 */
export const EVAL_PROMPT_FILE = "meal-v6.md";
export const EVAL_PROMPT_VERSION = "meal-v6-2026-08-05";

export function evalSpec(): RecognitionSpec {
  return {
    systemPrompt: read(join(evalRoot, "..", "..", "prompts", EVAL_PROMPT_FILE), "utf8").trimEnd(),
    userPrompt: "Classify this meal.",
    jsonSchema: evalJsonSchema(),
    geminiSchema: evalGeminiSchema(),
    schemaName: "meal_recognition_eval",
  };
}

export { SCHEMA_VERSION };

export function photoPath(photo: string): string {
  return join(evalRoot, "photos", photo);
}

/**
 * The bytes the app would send.
 *
 * `MealCaptureView` re-encodes the picked image as JPEG at quality 0.82 and does
 * not resize; `detail: low` and Gemini's default media resolution do the
 * downsampling server-side. This harness sends the file as it is, so keep the
 * photos in `photos/` at the size the phone produced them. Evaluating
 * full-resolution originals against a pipeline that ships compressed ones
 * measures a different task.
 */
export function readPhoto(photo: string): { base64: string; mimeType: string; hash: string } {
  const bytes = readFileSync(photoPath(photo));
  const mimeType = photo.toLowerCase().endsWith(".png")
    ? "image/png"
    : photo.toLowerCase().endsWith(".webp")
      ? "image/webp"
      : "image/jpeg";
  return {
    base64: bytes.toString("base64"),
    mimeType,
    hash: createHash("sha256").update(bytes).digest("hex"),
  };
}

export type EvalModel = {
  id: string;
  provider: RecognitionProvider;
  model: string;
  /** `candidate` could ship and is what the gate acts on. `ceiling` answers
   *  whether there is headroom worth chasing and never fails a build — at a
   *  two-dollar subscription, a Sonnet-class default is half the revenue. */
  tier: "candidate" | "ceiling";
  usdPerMillionInput: number;
  usdPerMillionOutput: number;
};

export function loadModels(): EvalModel[] {
  const file = JSON.parse(readFileSync(join(evalRoot, "models.json"), "utf8")) as {
    models: EvalModel[];
  };
  return file.models;
}

export function envFor(provider: RecognitionProvider, model?: string): Env {
  const env = {
    OPENAI_API_KEY: process.env.OPENAI_API_KEY ?? "",
    GEMINI_API_KEY: process.env.GEMINI_API_KEY ?? "",
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY ?? "",
    OPENAI_RECOGNITION_MODEL: process.env.OPENAI_RECOGNITION_MODEL ?? "gpt-5.6-luna",
    GEMINI_RECOGNITION_MODEL: process.env.GEMINI_RECOGNITION_MODEL ?? "gemini-3.6-flash",
    ANTHROPIC_RECOGNITION_MODEL:
      process.env.ANTHROPIC_RECOGNITION_MODEL ?? "claude-haiku-4-5-20251001",
    QWEN_API_KEY: process.env.QWEN_API_KEY ?? "",
    QWEN_RECOGNITION_MODEL: process.env.QWEN_RECOGNITION_MODEL ?? "qwen3.7-flash",
    QWEN_BASE_URL: process.env.QWEN_BASE_URL ?? "",
    OPENAI_REASONING_EFFORT: process.env.OPENAI_REASONING_EFFORT ?? "",
    GEMINI_THINKING_LEVEL: process.env.GEMINI_THINKING_LEVEL ?? "",
    ANTHROPIC_THINKING_BUDGET: process.env.ANTHROPIC_THINKING_BUDGET ?? "",
    QWEN_ENABLE_THINKING: process.env.QWEN_ENABLE_THINKING ?? "",
    RECOGNITION_PROVIDER: provider,
  } as unknown as Env;
  if (model) {
    // The matrix compares models, not vendors, so the entry overrides whatever
    // the deployment would have used.
    const key = {
      openai: "OPENAI_RECOGNITION_MODEL",
      gemini: "GEMINI_RECOGNITION_MODEL",
      anthropic: "ANTHROPIC_RECOGNITION_MODEL",
      qwen: "QWEN_RECOGNITION_MODEL",
    }[provider];
    (env as unknown as Record<string, string>)[key] = model;
  }
  return env;
}

const keyVariable: Record<RecognitionProvider, string> = {
  openai: "OPENAI_API_KEY",
  gemini: "GEMINI_API_KEY",
  anthropic: "ANTHROPIC_API_KEY",
  qwen: "QWEN_API_KEY",
};

export function isConfigured(provider: RecognitionProvider): boolean {
  return Boolean(process.env[keyVariable[provider]]);
}

export function configuredProviders(): RecognitionProvider[] {
  return recognitionProviders.filter(isConfigured);
}

/**
 * The note the person would have typed.
 *
 * Built from the golden's `hidden` items, which is what a real user does: they
 * type what the camera cannot see because they cooked it. Without this track
 * nothing tests the rule that treats the note as ground truth, and the two
 * hidden items in the dataset are unreachable by construction.
 */
export function noteFor(hidden: { name: string }[]): string | undefined {
  if (hidden.length === 0) return undefined;
  return `Also in this, not visible in the photo: ${hidden.map((one) => one.name).join(", ")}.`;
}

export async function recognizeOnce(
  provider: RecognitionProvider,
  photo: string,
  model?: string,
  note?: string,
): Promise<{ raw: string; latencyMs: number; inputTokens: number; outputTokens: number }> {
  const env = envFor(provider, model);
  const { base64, mimeType, hash } = readPhoto(photo);
  const spec = evalSpec();
  const result = await requestMealRecognition(
    env,
    { photoHash: hash, mimeType, imageBase64: base64 } as never,
    provider,
    note ? { ...spec, userPrompt: `${spec.userPrompt}\n\n${note}` } : spec,
  );
  return {
    raw: result.rawModelJson,
    latencyMs: result.latencyMs,
    inputTokens: result.inputTokens,
    outputTokens: result.outputTokens,
  };
}

export function modelName(provider: RecognitionProvider): string {
  return modelFor(envFor(provider), provider);
}

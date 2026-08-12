import type { RecognitionProvider, RecognitionRequest } from "../../src/contracts";
import { mealRecognitionJsonSchema, mealRecognitionSchema } from "../../src/contracts";
import {
  MEAL_RECOGNITION_SYSTEM_PROMPT,
  MEAL_RECOGNITION_TEXT_USER_PROMPT,
  MEAL_RECOGNITION_USER_PROMPT,
} from "./prompt";
import { hasImage, type ProviderInput } from "./types";

/**
 * What to ask for, separately from how to ask it.
 *
 * Production always uses the defaults. The eval passes a candidate — the
 * dataset's richer taxonomy and its count measure — through the same request
 * builders, so a comparison measures the model and the contract rather than a
 * second implementation of the transport. The rows carry `schemaVersion` because
 * two runs under different contracts are not comparable and nothing else would
 * say so.
 */
export type RecognitionSpec = {
  systemPrompt: string;
  userPrompt: string;
  /** JSON Schema for OpenAI-shaped strict mode and Anthropic tool input. */
  jsonSchema: Record<string, unknown>;
  /** Gemini's OpenAPI subset, which differs enough to need its own. */
  geminiSchema?: Record<string, unknown>;
  schemaName: string;
};

export function productionSpec(input: ProviderInput = {}): RecognitionSpec {
  const said = input.said?.trim();
  const note = input.note?.trim();
  // The opening line names what the model is reading. What the person said and
  // what they noted are fenced separately because they are different kinds of
  // evidence: `said` is the person describing the meal, the note is the person
  // annotating a photograph they expect the model to read for itself.
  const sections = [
    hasImage(input) ? MEAL_RECOGNITION_USER_PROMPT : MEAL_RECOGNITION_TEXT_USER_PROMPT,
  ];
  if (said) sections.push(`From the person who ate it:\n"""\n${said}\n"""`);
  if (note) {
    sections.push(
      hasImage(input)
        ? `What the photo cannot show, from the person who ate it:\n"""\n${note}\n"""`
        : `Added by the person afterwards:\n"""\n${note}\n"""`,
    );
  }
  // Where the request came from, and it is worth as much as the whole rest of
  // this on branded food. A Subway American Clubhouse footlong is 698 kcal in
  // Japan; asked without a country the model answered 1216, because the US
  // All-American Club really is about that. The person typing "subway
  // footlong" in Tokyo has not withheld the market — nobody names their own
  // country — so the request's own country is offered as what it is: the
  // weakest evidence there is, ranked below anything the photograph or the
  // words actually show.
  if (input.market) {
    sections.push(
      `Where this was bought, from the phone's network rather than from the person — ` +
        `ISO country ${input.market}. Weak evidence: anything the photograph or their own words ` +
        `show about the country outranks it. Use it to price the right market's version of a ` +
        `branded product, never to override what you can see.`,
    );
  }
  return {
    systemPrompt: MEAL_RECOGNITION_SYSTEM_PROMPT,
    userPrompt: sections.join("\n\n"),
    jsonSchema: mealRecognitionJsonSchema(),
    schemaName: "meal_recognition",
  };
}

/** Parsing is the caller's business when a candidate schema is in play. */
export type RawAnswer = {
  rawModelJson: string;
  requestId: string | null;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
};

/**
 * A candidate schema is validated by whoever defined it; only the production
 * contract is parsed here.
 */
export function parseFor(spec: RecognitionSpec) {
  return (value: unknown) =>
    spec.schemaName === "meal_recognition" ? mealRecognitionSchema.parse(value) : (value as never);
}

export type ProviderCall = (
  env: import("../env").Env,
  input: RecognitionRequest,
  spec: RecognitionSpec,
) => Promise<RawAnswer>;

export type { RecognitionProvider };

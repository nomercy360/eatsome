import type { MealRecognition } from "../../src/contracts";
import { mealRecognitionSchema } from "../../src/contracts";
import { geminiResponseSchema } from "./gemini";
import {
  MEAL_RECOGNITION_SYSTEM_PROMPT,
  MEAL_RECOGNITION_TEXT_USER_PROMPT,
  MEAL_RECOGNITION_USER_PROMPT,
} from "./prompt";
import { hasImage, type ModelCall, type ProviderInput } from "./types";

/**
 * The recognition question, assembled from whatever the request carried.
 *
 * The opening line names what the model is reading. What the person said and
 * what they noted are fenced separately because they are different kinds of
 * evidence: `said` is the person describing the meal, the note is the person
 * annotating a photograph they expect the model to read for itself.
 */
export function recognitionSpec(input: ProviderInput = {}): ModelCall<MealRecognition> {
  const said = input.said?.trim();
  const note = input.note?.trim();
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
    responseSchema: geminiResponseSchema(),
    parse: (value) => mealRecognitionSchema.parse(value),
  };
}

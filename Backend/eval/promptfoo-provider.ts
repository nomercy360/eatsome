import { loadModels, recognizeOnce } from "./harness";

/**
 * promptfoo talks to the models through the code that ships.
 *
 * Without this, an eval measures promptfoo's request shaping rather than the
 * proxy's — and the three providers differ exactly where it matters: strict
 * `json_schema`, `responseSchema`, and a forced tool call. Referenced from
 * promptfooconfig.yaml as `file://eval/promptfoo-provider.ts:openai` and so on.
 */
const models = loadModels();

class EatsomeProvider {
  private readonly entry = (id: string) => {
    const found = models.find((one) => one.id === id);
    if (!found) throw new Error(`models.json has no entry called ${id}`);
    return found;
  };

  constructor(private readonly modelId: string) {}

  id() {
    return `eatsome:${this.modelId}`;
  }

  async callApi(_prompt: string, context?: { vars?: Record<string, unknown> }) {
    const photo = String(context?.vars?.photo ?? "");
    if (!photo) return { error: "test case has no `photo` var" };
    try {
      const entry = this.entry(this.modelId);
      const note = String(context?.vars?.note ?? "").trim() || undefined;
      const result = await recognizeOnce(entry.provider, photo, entry.model, note);
      return {
        output: result.raw,
        tokenUsage: { prompt: result.inputTokens, completion: result.outputTokens },
        cached: false,
      };
    } catch (error) {
      return { error: error instanceof Error ? error.message : String(error) };
    }
  }
}

// One export per models.json entry, referenced from promptfooconfig.yaml.
export const qwen = new EatsomeProvider("qwen-3.7-flash");
export const luna = new EatsomeProvider("gpt-5.6-luna");
export const geminiFlash = new EatsomeProvider("gemini-3.6-flash");
export const grok = new EatsomeProvider("grok-4.5");
export const sonnet = new EatsomeProvider("claude-sonnet-5");
export default luna;

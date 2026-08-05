import { recognizeOnce } from "./eval/harness.ts";
async function main() {
  const bases = [
    ["workspace (your QWEN_BASE_URL)", process.env.QWEN_BASE_URL ?? ""],
    ["public dashscope-intl", "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"],
  ];
  for (const [label, base] of bases) {
    process.env.QWEN_BASE_URL = base;
    try {
      const r = await recognizeOnce("qwen", "TG_95823.jpeg", "qwen3.8-max");
      const items = JSON.parse(r.raw).items ?? [];
      console.log(`qwen3.8-max @ ${label.padEnd(32)} OK   in=${r.inputTokens} out=${r.outputTokens} ${r.latencyMs}ms  ${items.map((i: any) => i.group).join(", ")}`);
    } catch (e: any) {
      console.log(`qwen3.8-max @ ${label.padEnd(32)} FAIL ${(e?.message ?? e).toString().slice(0, 150)}`);
    }
  }
}
main();

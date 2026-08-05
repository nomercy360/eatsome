import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    coverage: {
      provider: "v8",
      reporter: ["text", "html"],
    },
    // eval too: a parity gap between golden and schema is a defect that makes
    // every model fail identically, which reads as a model problem.
    include: ["src/**/*.test.ts", "worker/**/*.test.ts", "eval/**/*.test.ts"],
  },
});

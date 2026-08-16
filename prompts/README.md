# Prompts

One file per version, and the file is the source. `scripts/sync-prompt.mjs`
generates the Worker's TypeScript constants from it; a test fails if the
generated copy has drifted from the file.

That machinery exists because the drift already happened. The prompt lived as a
string literal in `MealRecognition.swift` and a second one in
`Backend/worker/ai/prompt.ts`, and within a day the proxy was missing two rules
the app had — so the backend and the app were asking different questions while
appearing to share a prompt version. An eval harness reading a third copy would
have measured a fourth thing.

## Rules

- **Versions are immutable.** `meal-v5.md` is never edited once a build has used
  it. Fixing a rule means `meal-v6.md` and a CHANGELOG line saying which failure
  it addresses. Editing in place makes two weeks of eval reports incomparable
  and nothing in the data will tell you.
- **The version travels with the answer.** `promptVersion` is stamped on every
  recognition, on every eval row, and on the recognition cache key.
- **Regenerate after editing:** `node scripts/sync-prompt.mjs`.
- **One reader.** The Worker is the only thing that holds a prompt; the phone
  sends a photograph and words and gets an answer back with `promptVersion` on
  it. `scripts/sync-prompt.mjs` writes `Backend/worker/ai/prompt.generated.ts`
  and `revision.generated.ts` and nothing else.

## Adding a version

1. `cp prompts/meal-v5.md prompts/meal-v6.md`, edit the copy.
2. Set `activeVersion` in `scripts/sync-prompt.mjs`.
3. `node scripts/sync-prompt.mjs`
4. Run the eval against both versions before keeping it. A version that loses
   recall on a case the previous one passed is not an improvement, whatever the
   average says.

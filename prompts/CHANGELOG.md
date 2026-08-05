# Prompt changelog

Newest first. Every entry names the failure the change is meant to fix, so a
version that does not fix anything is visibly a version that does not fix
anything.

## meal-v5-2026-08-05

No rule changes. v4's text lifted out of the Swift string literal into
`meal-v5.md`, which the app, the proxy and the eval harness now all read.
Whitespace normalised in the process, which is why it gets a version rather than
being called the same prompt: the bytes differ, and a recognition cached under
v4 was produced by different bytes.

## meal-v4-2026-08-05

- **Sauces were skipped entirely.** A kebab with visible garlic and chilli sauce
  produced no sauce item, and dressings are the main carrier of fat in street
  food. Added an explicit checklist plus routing: mayonnaise and cream-based
  dressings as `butter`, oil-based as `olive_oil`, cooked tomato-and-onion as
  `sofrito`, yoghurt sauces as `dairy`.
- **Avocado came back as `fruit` with `vegetables` as the alternative** — both
  wrong, and scoring it as fruit credits a serving never eaten while hiding the
  fat. Added `healthy_fats` and a rule sending avocado, olives, seeds and tahini
  there.
- **Hedging in the label**: "sliced melon or pineapple". The label now names one
  food and forks go in `alternatives`.
- **`pastry` offered for home cooking.** It now needs visible evidence of a
  manufactured item.
- **Alcohol-free beer** scored as nothing by luck rather than by rule.
- **The note slot**: what the photograph cannot show, treated as ground truth
  about ingredients, plus the exception that lifts the closest-tray restriction
  when the person says the rest is theirs.

## meal-v3-2026-08-05

- **Self-reported confidence was uncalibrated** — the same 0.56 on white rice and
  on unidentifiable meat, which made the low-confidence threshold flag every row
  and mean nothing. Replaced with `alternatives`: a shortlist of rival groups,
  empty when the group is obvious.
- **`group` was being left empty** for the user to fill in, which is the opposite
  of recognition. It is now always the model's best answer.

## meal-v2-2026-08-04

- Multiple trays in frame were merged into one meal. Added the closest-tray rule
  and `other_meals_visible`.
- Soups and side bowls were read as background. Added the rule that decomposes
  them — miso soup contains legumes.

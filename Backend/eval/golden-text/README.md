# Text track — parked, not deleted

15 meals described in words rather than photographed, with human goldens. The
dataset is kept; the code that scored it is gone.

It graded the same thing the photo track did — which food groups the model named
and how many servings of each — and v21 removed the taxonomy those names came
from. The scorers (`run-text.ts`, `score-text.ts`, `golden-text.ts`) imported a
harness built entirely on it and could not be salvaged into something that
grades a macro figure.

The cases themselves are still worth something: they are real descriptions of
real meals, and weight-from-words is a different claim than weight-from-a-photo
with different honest tolerances. Reviving them means the same admission
standard the photo golden now uses — a case is ground truth only if somebody
published the figures — so most of these need a published number attached before
they can be scored again, and the ones that cannot get one are notes rather than
tests.

See `../golden/DATASET.md`.

#!/usr/bin/env python3
"""Protein, fat, carbohydrate, energy and sodium per 100 g, from food
composition tables, into `shaman-config.json`.

    python3 scripts/build-food-table.py [--sources DIR] [--check]

Why this exists
---------------
Protein was derived from a 26-row table keyed by food group, and one row cannot
be right for rice and pasta and bread at once. Measured against two labelled
meals it ran +23% on a sauced-meat bowl and -42% on a mentaiko pasta — the
weights were fine both times and the conversion was not.

So a food-level table sits in front of the group table. It does not replace it:
a label that does not resolve falls back to the group, which is exactly today's
behaviour, so a miss costs nothing it did not already cost.

Why it now carries five figures
-------------------------------
The same lookup that answers "how much protein is in 180 g of salmon" answers
the other four from the same source row, at no extra call and no extra guess.
Nothing here is estimated from a photograph: recognition still reports weight
and only weight, and every nutrient is a published figure for a named food
multiplied by that weight.

That is the whole argument for totalling them. A calorie figure invented by a
model from the look of a plate is not data; a calorie figure that is
`grams x kcal/100 g` from SR Legacy is the same arithmetic already trusted for
protein. The number is only ever as good as the weight and the label, which is
what `pnpm eval:nutrients` measures and what the golden set measures.

Coverage is the thing to watch rather than precision. A total built from the
fraction of a plate that resolved is worse than no total, so every food group
has a representative row (`GROUP_REPRESENTATIVE`) standing behind the food
table, and a miss lands on a sourced group figure rather than on zero.

What this script guarantees
---------------------------
Every number it emits came out of a source file. The curation list below names
a source row id, and a row that cannot be resolved is a hard error rather than
a default — nothing here can invent a plausible figure, which is the whole
reason the app is allowed to total protein at all.

The editorial judgement is in the *choice* of row, not the number: "chicken"
could reasonably resolve to breast, thigh or fried, and those differ by 8 g.
That choice is recorded per row so it can be argued with.

Sources, pinned
---------------
USDA FoodData Central, SR Legacy (2018-04). Public domain, and frozen — its
final release, which is a feature here: a frozen table cannot silently rewrite
a history of derived figures.

MEXT Standard Tables of Food Composition in Japan, 8th revision supplemented
2023. Free to use with attribution. Column `PROT-` — protein from nitrogen x a
food-specific factor — NOT `PROTCAA`, the amino-acid-composition column the 8th
revision introduced. PROTCAA runs 5-15% lower (mentaiko 18.4 against 21.0), and
SR Legacy is nitrogen-based, so taking PROTCAA for the Japanese half would put
a silent step between the two halves of the same tray.

Every MEXT column is chosen the same way — for the one that means what the SR
Legacy column means, not for the one the 8th revision considers most modern:

    PROT-     nitrogen x factor      SR 1003  Protein
    FAT-      total lipid            SR 1004  Total lipid (fat)
    CHOCDF-   carbohydrate by diff.  SR 1005  Carbohydrate, by difference
    ENERC_KCAL                       SR 1008  Energy (kcal)
    NA        sodium, mg             SR 1093  Sodium, Na

`FATNLEA` (triacylglycerol equivalents) and `CHOAVL` (available carbohydrate)
are the modern columns and both are wrong here for the same reason PROTCAA is:
they are a different basis from the American half of the table, and a tray with
rice from one and mentaiko from the other would be internally inconsistent in a
way no eval would show.

Salt is not read. Labels print salt, tables print sodium, and salt equivalent is
sodium x 58.44/22.99 — a unit conversion, not a measurement, so it is done once
on read in `Nutrients.saltGrams` rather than baked into 358 rows here.

Cooked rows only. Dry spaghetti is 12.9 g/100 g and boiled is 5.8; the app
weighs food on a plate, so the dry row is wrong by 2.2x. This is a bigger error
than the choice of database.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "Core/Sources/ShamanCore/Resources/shaman-config.json"

SR_URL = "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip"
MEXT_URL = "https://www.mext.go.jp/content/20260327-mxt_kagsei-mext-000029402_02.xlsx"
SR_VERSION = "sr-legacy-2018-04"
MEXT_VERSION = "mext-8th-suppl-2023"

# The five figures, and where each source keeps them. `sodium` is milligrams;
# everything else is grams except `kcal`. Salt is derived on read, never stored.
SR_NUTRIENTS = {
    "1003": "protein",
    "1004": "fat",
    "1005": "carbohydrate",
    "1008": "kcal",
    "1093": "sodium",
    # Read for `atwater_disagreement` and never emitted. Fibre is not one of the
    # figures this app reports; it is here because carbohydrate by difference
    # includes it, and the energy cross-check is wrong on fibrous food without
    # it. Loading it costs one more pass over a file already being read.
    "1079": "fibre",
}
MEXT_NUTRIENTS = {
    "PROT-": "protein",
    "FAT-": "fat",
    "CHOCDF-": "carbohydrate",
    "ENERC_KCAL": "kcal",
    "NA": "sodium",
    "FIB-": "fibre",
}
# All five travel together, and a row missing any of them is dropped rather
# than zero-filled: a zero-filled row is a real number that is wrong, where a
# dropped row falls back to the group representative and is merely coarse.
#
# Sodium is in here despite being the one column with gaps, because requiring it
# costs a single row — `Groundcherries, raw` — and buys a non-optional figure
# through the whole client. A salt total that is sometimes absent per ingredient
# is the partial-total problem in miniature, and it is not worth one cape
# gooseberry. Fibre is loaded but not required; it only feeds the Atwater check.
REQUIRED = ("protein", "fat", "carbohydrate", "kcal", "sodium")

# `FoodGroup.allCases`, as raw values. Every group named anywhere in this file
# is checked against it, because a group that is not a case produces a key no
# lookup can ever match: `potatoes|potatoes` shipped that way and sat in the
# config as dead weight, unreachable and indistinguishable from a working row.
# A typo here is now a build failure.
# What two of the groups above were called before the taxonomy audit, and why
# the table still answers to both.
#
# This file is fetched at launch from one URL by builds of every age. A build
# that has never heard of `cooked_tomato_sauce` looks its rows up under
# `sofrito`, finds nothing, and falls back — silently, to a 100 g serving and no
# energy figure at all. That is the same failure class as the month the Gemini
# schema quietly stopped emitting weights: everything still parses, and every
# number is wrong.
#
# So the generated table carries both spellings for as long as a build that
# knows only the old one might still fetch it. It costs seven duplicated rows in
# a file nobody reads by hand, and it is the reason the rename can happen at all
# without a flag day.
LEGACY_GROUP_NAMES: dict[str, tuple[str, ...]] = {
    "cooked_tomato_sauce": ("sofrito",),
    "plant_fats": ("healthy_fats",),
}

SOURCE_GROUPS = {
    "olive_oil", "vegetable_oil", "vegetables", "fruit", "legumes", "fish", "nuts",
    "plant_fats", "whole_grains", "refined_grains", "white_meat", "red_meat",
    "processed_meat", "dairy", "egg", "sweets", "pastry", "sugary_drinks", "coffee",
    "tea", "juice", "plant_milk", "smoothie", "butter", "alcohol",
    "cooked_tomato_sauce", "sauce", "other",
}

FOOD_KINDS = {
    "rice", "pasta_noodles", "bread_flatbread", "cereal_porridge", "potato",
    "other_starchy_vegetable", "vegetable", "mushroom_seaweed", "fruit",
    "avocado_olive", "legume", "soy_product", "nuts_seeds", "beef", "pork",
    "lamb_game", "poultry", "processed_meat", "organ_meat", "fish", "shellfish",
    "egg", "milk", "yogurt", "cheese", "cream", "plant_milk", "oil",
    "butter_margarine", "mayonnaise_dressing", "sauce_condiment", "soup_broth",
    "sugar_honey_syrup", "chocolate_candy", "cake_cookie", "pastry",
    "frozen_dessert", "savory_snack", "nutrition_bar", "water", "coffee", "tea",
    "juice", "smoothie", "soft_sports_energy_drink", "beer", "wine",
    "spirit_cocktail", "supplement", "meal_replacement", "unknown",
}


def food_kind(alias: str, source_group: str) -> str:
    """Map the old MEDAS curation bucket to the composition-oriented kind.

    The old value remains useful only while generating the already-reviewed
    source-row curation. It is never emitted. Splits use the normalised food
    name, so rice, pasta and bread no longer share one nutrient lookup guard.
    """
    name = normalise(alias)
    contains = lambda *words: any(word in name for word in words)

    if source_group in {"olive_oil", "vegetable_oil"}: return "oil"
    if source_group == "vegetables":
        if contains("potato", "yam"): return "potato"
        if contains("mushroom", "seaweed", "nori", "kelp", "wakame"): return "mushroom_seaweed"
        return "vegetable"
    if source_group == "fruit": return "fruit"
    if source_group == "legumes":
        return "soy_product" if contains("soy", "tofu", "miso", "natto", "tempeh", "edamame") else "legume"
    if source_group == "nuts": return "nuts_seeds"
    if source_group == "plant_fats":
        return "nuts_seeds" if contains("seed", "sesame", "nut") else "avocado_olive"
    if source_group in {"whole_grains", "refined_grains"}:
        if contains("rice"): return "rice"
        if contains("pasta", "noodle", "spaghetti", "udon", "macaroni"): return "pasta_noodles"
        if contains("bread", "bun", "roll", "pita", "tortilla", "flatbread"): return "bread_flatbread"
        return "cereal_porridge"
    if source_group == "white_meat": return "poultry"
    if source_group == "red_meat":
        if contains("pork"): return "pork"
        if contains("lamb", "veal", "game", "venison", "goat"): return "lamb_game"
        return "beef"
    if source_group == "processed_meat": return "processed_meat"
    if source_group == "fish":
        return "shellfish" if contains("shrimp", "prawn", "crab", "lobster", "clam", "oyster", "mussel", "scallop", "squid", "octopus") else "fish"
    if source_group == "dairy":
        if contains("yogurt", "yoghurt"): return "yogurt"
        if contains("cheese"): return "cheese"
        if contains("cream"): return "cream"
        if contains("egg"): return "egg"
        return "milk"
    if source_group == "egg": return "egg"
    if source_group == "butter":
        if contains("mayonnaise", "dressing"): return "mayonnaise_dressing"
        if contains("cream"): return "cream"
        return "butter_margarine"
    if source_group == "sweets":
        if contains("ice cream", "sorbet", "frozen"): return "frozen_dessert"
        if contains("chocolate", "candy", "candies"): return "chocolate_candy"
        if contains("sugar", "honey", "syrup", "jam"): return "sugar_honey_syrup"
        return "cake_cookie"
    if source_group == "pastry": return "pastry"
    if source_group == "sugary_drinks": return "soft_sports_energy_drink"
    if source_group in {"coffee", "tea", "juice", "plant_milk", "smoothie"}: return source_group
    if source_group == "alcohol":
        if contains("beer", "ale", "lager"): return "beer"
        if contains("wine"): return "wine"
        return "spirit_cocktail"
    if source_group in {"cooked_tomato_sauce", "sauce"}: return "sauce_condiment"
    return "unknown"

# `alias` is what a model writes in `label`, normalised the way the client
# normalises it: lower case, no punctuation, collapsed whitespace. `group` is
# the APP's FoodGroup, assigned here rather than read from the source — the
# source taxonomies are organised by commodity and do not map onto MEDAS.
#
# It is a guard, not a lookup key into the data: a label whose group disagrees
# with the row is rejected and falls back, so "cream" under `dairy` cannot pick
# up the `butter` row.
CURATION: list[tuple[str, str, str, str]] = [
    # (alias, app food group, source, source row id)
    # --- grains -----------------------------------------------------------
    ("white rice", "refined_grains", "sr", "168878"),
    ("cooked white rice", "refined_grains", "sr", "168878"),
    ("rice", "refined_grains", "sr", "168878"),
    ("sushi rice", "refined_grains", "sr", "168878"),
    ("basmati rice", "refined_grains", "sr", "168878"),
    ("spaghetti", "refined_grains", "sr", "169737"),
    ("pasta", "refined_grains", "sr", "169737"),
    ("noodles", "refined_grains", "sr", "169737"),
    ("udon noodles", "refined_grains", "sr", "169737"),
    ("bread", "refined_grains", "sr", "174925"),
    ("white bread", "refined_grains", "sr", "174925"),
    ("toast bread", "refined_grains", "sr", "174925"),
    ("bun", "refined_grains", "sr", "174925"),
    ("burger bun", "refined_grains", "sr", "174925"),
    # --- protein ----------------------------------------------------------
    ("chicken", "white_meat", "sr", "171450"),
    ("fried chicken", "white_meat", "sr", "171448"),
    ("chicken breast", "white_meat", "sr", "171477"),
    ("beef", "red_meat", "sr", "174035"),
    ("beef patty", "red_meat", "sr", "174032"),
    ("prosciutto", "processed_meat", "sr", "173863"),
    ("ham", "processed_meat", "sr", "173863"),
    ("shrimp", "fish", "sr", "175180"),
    ("prawns", "fish", "sr", "175180"),
    ("egg", "egg", "sr", "173424"),
    ("boiled egg", "egg", "sr", "173424"),
    ("chickpeas", "legumes", "sr", "173799"),
    # --- dairy and fats ---------------------------------------------------
    ("milk", "dairy", "sr", "171265"),
    ("cheese", "dairy", "sr", "170899"),
    ("cream cheese", "dairy", "sr", "173418"),
    ("yogurt", "dairy", "sr", "171284"),
    ("yoghurt", "dairy", "sr", "171284"),
    ("butter", "butter", "sr", "173410"),
    ("mayonnaise", "butter", "sr", "171009"),
    ("olive oil", "olive_oil", "sr", "171413"),
    # "cooking oil" is the label a model writes when it can see a sheen and
    # cannot see the bottle. It used to resolve to olive oil, which was the
    # taxonomy answering a question it had not been asked; with a seed-oil group
    # in the table the honest home for an unnamed frying oil is the generic one.
    ("cooking oil", "vegetable_oil", "sr", "171411"),
    ("vegetable oil", "vegetable_oil", "sr", "171411"),
    ("sunflower oil", "vegetable_oil", "sr", "171025"),
    ("rapeseed oil", "vegetable_oil", "sr", "172336"),
    ("canola oil", "vegetable_oil", "sr", "172336"),
    ("soybean oil", "vegetable_oil", "sr", "171411"),
    ("seed oil", "vegetable_oil", "sr", "171411"),
    ("frying oil", "vegetable_oil", "sr", "171411"),
    ("sesame oil", "vegetable_oil", "sr", "171015"),
    ("avocado", "plant_fats", "sr", "171705"),
    ("olives", "plant_fats", "sr", "169094"),
    ("sesame seeds", "plant_fats", "sr", "170150"),
    ("almonds", "nuts", "sr", "170567"),
    # --- produce ----------------------------------------------------------
    ("cucumber", "vegetables", "sr", "168409"),
    ("tomato", "vegetables", "sr", "170457"),
    ("tomatoes", "vegetables", "sr", "170457"),
    ("arugula", "vegetables", "sr", "169387"),
    ("rocket", "vegetables", "sr", "169387"),
    ("lettuce", "vegetables", "sr", "169248"),
    # `vegetables`, because there is no `potatoes` case in `FoodGroup` — this
    # row was filed under one until the group check below caught it, and the
    # model can only ever say `vegetables` for a potato anyway, since both
    # response schemas generate their enum from `FoodGroup.allCases`.
    ("potatoes", "vegetables", "sr", "170440"),
    ("mashed potato", "vegetables", "sr", "168555"),
    ("mashed potatoes", "vegetables", "sr", "168555"),
    ("banana", "fruit", "sr", "173944"),
    ("blueberries", "fruit", "sr", "171711"),
    ("cherries", "fruit", "sr", "171719"),
    ("mango", "fruit", "sr", "169910"),
    ("melon", "fruit", "sr", "169092"),
    ("apricots", "fruit", "sr", "171697"),
    # --- drinks -----------------------------------------------------------
    ("coffee", "coffee", "sr", "171890"),
    ("beer", "alcohol", "sr", "168746"),
    ("white wine", "alcohol", "sr", "174837"),
    # --- Japanese, where SR Legacy has nothing usable ---------------------
    ("mentaiko", "fish", "mext", "10204"),
    ("natto", "legumes", "mext", "04046"),
    ("miso", "legumes", "mext", "17044"),
    ("miso paste", "legumes", "mext", "17044"),
    ("miso broth", "legumes", "mext", "17044"),
    ("nori", "vegetables", "mext", "09004"),
    ("nori seaweed", "vegetables", "mext", "09004"),
    ("tofu", "legumes", "mext", "04032"),
    # --- the head of real traffic ----------------------------------------
    # Added by measuring, not by guessing: these are the labels the four models
    # wrote most often in the v17 baseline that the generated tail did not
    # reach. The generated rows are the long tail and moved coverage by four
    # rows in two thousand; this section is what actually moves it, because
    # labels are Zipf-distributed and the head is exactly where the ambiguity
    # that defeats mechanical resolution lives.
    ("tomato sauce", "cooked_tomato_sauce", "sr", "170054"),
    ("soy sauce", "sauce", "sr", "174277"),
    ("shoyu", "sauce", "sr", "174277"),
    ("teriyaki sauce", "sauce", "sr", "171167"),
    ("tomato onion curry", "cooked_tomato_sauce", "sr", "170056"),
    ("flatbread", "refined_grains", "sr", "167535"),
    ("flour tortilla", "refined_grains", "sr", "167535"),
    ("tortilla", "refined_grains", "sr", "167535"),
    ("pizza crust", "refined_grains", "sr", "170317"),
    ("pizza dough", "refined_grains", "sr", "170317"),
    ("bagel", "refined_grains", "sr", "174899"),
    ("croutons", "refined_grains", "sr", "172751"),
    ("breadcrumbs", "refined_grains", "sr", "174924"),
    ("pancakes", "refined_grains", "sr", "175009"),
    ("oladyi pancakes", "refined_grains", "sr", "175009"),
    ("dark bread", "whole_grains", "sr", "172688"),
    ("rye bread", "whole_grains", "sr", "172688"),
    ("whole grain bread", "whole_grains", "sr", "172688"),
    ("cooked oats", "whole_grains", "sr", "173905"),
    ("grain porridge", "whole_grains", "sr", "173905"),
    ("fried egg", "egg", "sr", "173423"),
    ("fried eggs", "egg", "sr", "173423"),
    ("mixed vegetables", "vegetables", "sr", "170142"),
    ("vegetables", "vegetables", "sr", "170142"),
    ("herbs", "vegetables", "sr", "170416"),
    ("parsley", "vegetables", "sr", "170416"),
    ("carrot", "vegetables", "sr", "170393"),
    ("onion", "vegetables", "sr", "170000"),
    ("cabbage", "vegetables", "sr", "169975"),
    ("shredded cabbage", "vegetables", "sr", "169975"),
    ("shredded lettuce", "vegetables", "sr", "169248"),
    ("leafy greens", "vegetables", "sr", "169248"),
    ("mixed salad greens", "vegetables", "sr", "169248"),
    ("salad leaves", "vegetables", "sr", "169248"),
    ("corn", "vegetables", "sr", "169998"),
    ("sweetcorn", "vegetables", "sr", "169998"),
    ("cherry tomato", "vegetables", "sr", "170457"),
    ("eggplant", "vegetables", "sr", "169229"),
    ("guacamole", "plant_fats", "sr", "171706"),
    ("raspberries", "fruit", "sr", "167755"),
    ("grapes", "fruit", "sr", "174683"),
    ("sour cream", "dairy", "sr", "171257"),
    ("sliced cheese", "dairy", "sr", "170899"),
    ("shredded cheese", "dairy", "sr", "170899"),
    ("grated cheese", "dairy", "sr", "170899"),
    ("feta", "dairy", "sr", "173420"),
    ("feta cheese", "dairy", "sr", "173420"),
    ("mozzarella", "dairy", "sr", "170845"),
    ("ice cream", "dairy", "sr", "167575"),
    ("sausage", "processed_meat", "sr", "171632"),
    # Cooked rows on purpose: raw mussel is 11.9 against 23.8 boiled, and raw
    # squid 15.6 against 17.9 fried. Half the seafood in this dataset is served
    # cooked and the raw row is the default the description sort would pick.
    ("mussels", "fish", "sr", "174217"),
    ("squid", "fish", "sr", "171982"),
    ("salmon", "fish", "sr", "172000"),
    ("tuna", "fish", "sr", "173706"),
    ("ketchup", "cooked_tomato_sauce", "sr", "168556"),
    ("jam", "sweets", "sr", "169641"),
    ("berry jam", "sweets", "sr", "169641"),
    ("fruit jam", "sweets", "sr", "169641"),
    ("blueberry jam", "sweets", "sr", "169641"),
    ("syrup", "sweets", "sr", "169578"),
    ("chocolate sauce", "sweets", "sr", "168834"),
    ("brownie", "sweets", "sr", "172713"),
    ("caesar dressing", "butter", "sr", "169055"),
    ("creamy dressing", "butter", "sr", "169055"),
    ("cooking fat", "butter", "sr", "173410"),
    ("olive oil dressing", "olive_oil", "sr", "171413"),
    ("espresso", "coffee", "sr", "171891"),
    ("peanuts", "nuts", "sr", "173806"),
    # Champagne has no row of its own; table wine is the closest published
    # figure and protein in any wine rounds to nothing, so the choice is inert.
    ("champagne", "alcohol", "sr", "173185"),
    ("wine", "alcohol", "sr", "173185"),
    ("red wine", "alcohol", "sr", "173190"),
    ("lager", "alcohol", "sr", "168746"),
    ("lager beer", "alcohol", "sr", "168746"),
    # --- meat and fish, where the protein is ------------------------------
    # Unresolved rows are 41% of the count but carry 46% of the protein on the
    # plate, and 31 of those points sit in white_meat, red_meat and fish alone.
    # These labels are worth more than the whole generated tail.
    #
    # `separable lean and fat` over `separable lean only` wherever both exist:
    # people eat the fat, and the lean-only rows read every fatty cut 10-20%
    # high. That preference is the single most consequential choice in this
    # block, and `pnpm eval:nutrients` is what checks it.
    ("pork", "red_meat", "sr", "167844"),
    ("pork belly", "red_meat", "sr", "167844"),
    ("minced meat", "red_meat", "sr", "174035"),
    ("ground beef", "red_meat", "sr", "174035"),
    ("minced meat topping", "red_meat", "sr", "174035"),
    ("steak", "red_meat", "sr", "168731"),
    ("beef steak", "red_meat", "sr", "168731"),
    ("grilled beef", "red_meat", "sr", "168731"),
    ("grilled beef steak", "red_meat", "sr", "168731"),
    ("raw beef steak", "red_meat", "sr", "168731"),
    ("lamb", "red_meat", "sr", "172495"),
    ("chicken thigh", "white_meat", "sr", "173625"),
    ("chicken leg", "white_meat", "sr", "173617"),
    ("chicken piece", "white_meat", "sr", "171448"),
    ("fried chicken piece", "white_meat", "sr", "171448"),
    ("karaage", "white_meat", "sr", "171448"),
    ("chicken nugget", "white_meat", "sr", "171448"),
    ("chicken schnitzel", "white_meat", "sr", "171448"),
    ("battered chicken", "white_meat", "sr", "171448"),
    ("chicken roll", "white_meat", "sr", "171450"),
    ("kebab meat", "white_meat", "sr", "173625"),
    ("turkey", "white_meat", "sr", "171479"),
    ("duck", "white_meat", "sr", "172409"),
    ("cod", "fish", "sr", "171956"),
    ("white fish", "fish", "sr", "171956"),
    ("sea bream", "fish", "sr", "171956"),
    ("sardines", "fish", "sr", "175139"),
    ("grilled sardines", "fish", "sr", "175139"),
    ("mackerel", "fish", "sr", "173674"),
    ("crab", "fish", "sr", "172008"),
    ("scallops", "fish", "sr", "167742"),
    ("octopus", "fish", "sr", "174249"),
    ("eel", "fish", "sr", "174194"),
    ("escargot", "fish", "sr", "174249"),
    ("snail meat", "fish", "sr", "174249"),
    ("seafood", "fish", "sr", "175180"),
    ("fish topping", "fish", "sr", "173706"),
    ("salami", "processed_meat", "sr", "174603"),
    ("pepperoni", "processed_meat", "sr", "174575"),
    ("bologna", "processed_meat", "sr", "173856"),
    ("bacon", "processed_meat", "sr", "167914"),
    ("cured duck breast", "processed_meat", "sr", "173863"),
    ("dry cured duck breast", "processed_meat", "sr", "173863"),
]


# --- what stands behind a miss ---------------------------------------------
#
# One sourced row per food group, used when the food table has never heard of a
# label. Protein could get away without this — a miss fell through to
# `Protein.defaultGramsPerServing`, a hand-calibrated table that covers every
# group — but energy cannot, because there is no such table for it and a miss
# would otherwise read zero.
#
# That distinction is the whole reason this block exists. A protein total built
# from the two thirds of a plate that resolved is 30% low and looks it. A
# calorie total built the same way is 700 kcal low and looks exactly like a
# calorie total, which is the failure this app spent three years refusing to
# ship. Every group answers, or the number is not shown.
#
# Chosen the way CURATION is chosen: a row id, so the figure can be argued with
# the institution that published it. Where the group already has an obvious
# archetype in CURATION the same row is used, so that naming a food cannot move
# the answer discontinuously — an unrecognised vegetable and one labelled
# "vegetables" have to land on the same number.
GROUP_REPRESENTATIVE: list[tuple[str, str, str]] = [
    # (app food group, source, source row id)
    ("olive_oil", "sr", "171413"),        # Oil, olive, salad or cooking
    # Soybean, because it is the highest-volume vegetable oil in the world and
    # the one behind most food fried by somebody else. Every oil in this group
    # is within a rounding error of 884 kcal and 100 g of fat per 100 g, so the
    # choice of row is close to inert — which is the point: the group exists to
    # be countable, not to be precise about which seed it came from.
    ("vegetable_oil", "sr", "171411"),    # Oil, soybean, salad or cooking
    ("butter", "sr", "173410"),           # Butter, salted
    ("vegetables", "sr", "170142"),       # Vegetables, mixed, frozen, cooked, boiled
    ("fruit", "sr", "171688"),            # Apples, raw, with skin
    ("legumes", "sr", "173799"),          # Chickpeas, mature seeds, cooked, boiled
    ("nuts", "sr", "170567"),             # Nuts, almonds
    ("plant_fats", "sr", "171705"),     # Avocados, raw, all commercial varieties
    ("whole_grains", "sr", "172688"),     # Bread, whole-wheat, commercially prepared
    ("refined_grains", "sr", "168878"),   # Rice, white, long-grain, cooked
    # Cod rather than salmon: the fish group is mostly white fish by weight, and
    # salmon's 13 g of fat would read every plate of it three times too fatty.
    ("fish", "sr", "171956"),             # Fish, cod, Atlantic, cooked, dry heat
    ("white_meat", "sr", "171450"),       # Chicken, meat and skin, cooked, roasted
    ("red_meat", "sr", "174035"),         # Beef, ground, 85% lean, cooked
    ("processed_meat", "sr", "173863"),   # Ham, sliced, pre-packaged
    ("dairy", "sr", "171265"),            # Milk, whole, 3.25% milkfat
    ("egg", "sr", "173424"),              # Egg, whole, cooked, hard-boiled
    # Milk chocolate over sugar: `sweets` catches chocolate, biscuits and
    # puddings far more often than it catches a spoon of granulated sugar, and
    # sugar's zero fat would read a brownie as half its energy.
    ("sweets", "sr", "167587"),           # Candies, milk chocolate
    ("pastry", "sr", "172755"),           # Danish pastry, fruit, enriched
    ("sugary_drinks", "sr", "174852"),    # Beverages, carbonated, cola, regular
    ("coffee", "sr", "171890"),           # Beverages, coffee, brewed
    ("tea", "sr", "171917"),              # Beverages, tea, green, brewed, regular
    ("juice", "sr", "169100"),            # Orange juice, chilled
    ("plant_milk", "sr", "175218"),       # SILK Plain, soymilk
    ("smoothie", "sr", "167795"),         # Fruit juice smoothie, MIGHTY MANGO
    ("cooked_tomato_sauce", "sr", "170054"),  # Tomato products, canned, sauce
    # Beer, for the same reason `ServingWeight` weighs a beer: it is what people
    # photograph. It is also the row where the Atwater check has to be skipped,
    # because 43 kcal of beer is mostly ethanol and ethanol is in none of the
    # four columns.
    ("alcohol", "sr", "168746"),          # Alcoholic beverage, beer, regular
    # `other` is deliberately absent, and that absence is load-bearing. It is
    # the bucket for food that was not recognised, so a figure here is invented
    # rather than estimated — the same argument that put 0 in the protein table
    # after a black coffee came to be worth 2 g. An unrecognised food therefore
    # contributes nothing and marks the day's total as incomplete, which is a
    # thing the person can fix by naming it.
]

# --- the mechanical tail ---------------------------------------------------
#
# 7,793 SR Legacy rows collapse into 731 head terms, because a description like
# "Chicken, broilers or fryers, meat and skin, cooked, roasted" is not a label
# any model writes — the head term before the first comma is. Of those, ~315
# name exactly one row and need no judgement at all; the rest collide, and
# `beef` alone spans 960 rows across raw/cooked, cut and fat content.
#
# So: generate the terms that resolve uniquely, curate the ones that do not.
# The curation list above is the second half, and it wins on any collision.
#
# A wrong group here is inert rather than wrong: the lookup only fires when the
# model's own group agrees, so a misfiled row is dead weight. A wrong *row* is
# the real risk, which is what COOKED_ONLY exists for.
CATEGORY_GROUPS: dict[str, str] = {
    "5": "white_meat",       # Poultry Products
    "7": "processed_meat",   # Sausages and Luncheon Meats
    "10": "red_meat",        # Pork Products — red meat in MEDAS terms
    "13": "red_meat",        # Beef Products
    "17": "red_meat",        # Lamb, Veal, and Game
    "15": "fish",            # Finfish and Shellfish
    "16": "legumes",         # Legumes and Legume Products
    "11": "vegetables",      # Vegetables and Vegetable Products
    "9": "fruit",            # Fruits and Fruit Juices
    "12": "nuts",            # Nut and Seed Products
    "19": "sweets",          # Sweets
    "28": "alcohol",         # Alcoholic Beverages
    "1": "dairy",            # Dairy and Egg Products
    "20": "refined_grains",  # Cereal Grains and Pasta
}

# Categories deliberately left out, because the app's group cannot be read off
# the category and guessing would put a real number under the wrong food:
#   2 Spices and Herbs      weights are rounding error
#   3 Baby Foods            not this diet
#   4 Fats and Oils         splits across olive_oil and butter by name alone
#   6 Soups/Sauces          a sauce is scored as what it is made of
#   8 Breakfast Cereals     refined or whole depends on the product
#   14 Beverages            coffee, tea, juice and sugary_drinks in one bucket
#   18 Baked Products       bread is refined_grains, cake is sweets or pastry
#   21/22/25 composed meals dish-level, not ingredient-level
#   23 Snacks, 24, 26, 27   no home, or not food

# A raw row under a cooked food is the biggest single error available here:
# dry spaghetti is 12.9 g/100 g against 5.8 boiled, and raw chicken breast
# reads 30% under its roasted weight for the opposite reason. For these groups
# a row has to say it was cooked.
COOKED_ONLY = {"white_meat", "red_meat", "fish", "legumes", "refined_grains"}
RAW_MARKERS = ("raw", "uncooked", "dry", "dried", "frozen, unprepared")
COOKED_MARKERS = ("cooked", "boiled", "roasted", "grilled", "baked", "braised", "steamed")

# Excluded from every group, not just the cooked ones. A dehydrated form is the
# same food at four times the concentration, and the app weighs what is on the
# plate: `gelatins, dry powder` reads 85.6 g/100 g and would have been the
# single worst row in this table. Caught by a range check on the first run,
# which is why that check now runs on every build.
DRY_FORMS = ("dry powder", "powder", "flour", "dried", "dehydrated", "concentrate", "freeze-dried")

# Names that are a category of food rather than a food, and would match a label
# meaning something much more specific.
TOO_GENERIC = {
    "beef", "pork", "lamb", "chicken", "turkey", "fish", "veal", "game meat",
    "cheese", "bread", "rice", "pasta", "milk", "yogurt", "oil", "nuts",
    "seeds", "beans", "soup", "snacks", "candies", "cereals", "beverages",
    "babyfood", "restaurant", "fast foods", "meat", "poultry",
}


# What a food in this group can plausibly weigh in protein, per 100 g as
# served. Not a second opinion on the number — the sources are right — but a
# check that the ROW is the right one: a figure outside these bounds means a
# dry, powdered or concentrated form got through the filters above.
PLAUSIBLE: dict[str, tuple[float, float]] = {
    "vegetables": (0, 12), "fruit": (0, 8), "fish": (5, 45), "white_meat": (10, 45),
    "red_meat": (10, 45), "legumes": (1, 30), "refined_grains": (1, 20),
    "dairy": (0, 40), "sweets": (0, 25), "alcohol": (0, 3), "nuts": (5, 40),
    "processed_meat": (5, 45), "egg": (5, 20), "plant_fats": (0, 30),
    "butter": (0, 10), "olive_oil": (0, 2), "vegetable_oil": (0, 2),
}

# The same idea for energy, and group-independent because the physics is. Pure
# fat is 884 kcal/100 g and nothing served on a plate exceeds it; anything at or
# near it that is not an oil is a dry or rendered form. The floor catches the
# other direction — a row whose energy column failed to parse and read 0 would
# otherwise quietly subtract a food from the day.
PLAUSIBLE_KCAL = (0.0, 900.0)


def atwater_disagreement(values: dict[str, float]) -> float | None:
    """How far the energy column is from its own macros, as a fraction.

    4 kcal a gram of protein and carbohydrate, 9 a gram of fat. This is the one
    check that catches a row whose columns came from different foods, which is
    the failure mode no per-nutrient range can see: `gelatins, dry powder` is
    85.6 g of protein and 335 kcal, and both are plausible on their own.

    Fibre is subtracted out at 2 kcal a gram rather than 4. Carbohydrate here is
    by difference, so it sweeps in fibre the body does not fully get, and
    ignoring that does not spread the error evenly — it lands entirely on
    high-fibre, low-energy food. Uncorrected, this check threw out lemons,
    limes, alfalfa sprouts and cooked oat bran, all of them correct rows,
    because a 29 kcal lemon is 53% fibre accounting. Where the source publishes
    no fibre the term is zero, which is the old behaviour for that row.

    Returns None where the comparison does not apply. Ethanol is 7 kcal a gram
    and appears in none of the four columns, so every alcoholic row fails by
    construction — beer is 43 kcal against an Atwater 16. Near-zero rows are
    excluded too: brewed tea is 0-1 kcal and the ratio is all rounding.
    """
    kcal = values["kcal"]
    if kcal < 20:
        return None
    fibre = min(values.get("fibre", 0.0), values["carbohydrate"])
    implied = (
        4 * values["protein"]
        + 4 * (values["carbohydrate"] - fibre)
        + 2 * fibre
        + 9 * values["fat"]
    )
    return abs(implied - kcal) / kcal


# Sugar alcohols and USDA's per-food specific factors still sit between the
# corrected figure and the published one, so a tolerance remains. At 0.30, with
# fibre accounted for, what it rejects is rows whose columns disagree about what
# food they describe rather than rows that are merely fibrous.
#
# Six generated rows are rejected at this setting, and they are worth knowing
# because four of them are the check being wrong:
#
#   chicken spread   158 kcal against an implied 246, where the fat alone is
#                    158. The columns do not describe the same food. Caught.
#   gums (guar)      77.3 g of carbohydrate, all of it fibre, published at 332
#                    kcal as though none of it were. Caught, and a bad row for
#                    a label to hit anyway.
#   lemons, limes,   citric acid lands in carbohydrate by difference and yields
#   lemon juice      almost no energy. Specific factors, not a bad row.
#   oat bran, cooked same, and 84% water besides.
#
# The four false positives fall back to their group representative — a lemon
# reads as an apple — which on garnish weights is a rounding difference. Widening
# the tolerance to keep them would also let `chicken spread` through, and a row
# whose columns disagree is the thing this check exists for.
ATWATER_TOLERANCE = 0.30
ATWATER_EXEMPT = {"alcohol"}


def proposals(sr: dict, categories: dict[str, str]) -> list[tuple[str, str, str, str]]:
    """Head terms that name exactly one usable row, after filtering."""
    by_head: dict[tuple[str, str], list[str]] = {}
    for row_id, (name, _values, _basis) in sr.items():
        group = CATEGORY_GROUPS.get(categories.get(row_id, ""))
        if group is None:
            continue
        head = normalise(name.split(",")[0])
        if not head or len(head.split()) > 2 or head in TOO_GENERIC:
            continue
        low = name.lower()
        if any(marker in low for marker in DRY_FORMS):
            continue
        if group in COOKED_ONLY:
            if not any(marker in low for marker in COOKED_MARKERS):
                continue
            if any(marker in low for marker in RAW_MARKERS):
                continue
        by_head.setdefault((group, head), []).append(row_id)

    # Exactly one surviving row, or the term is ambiguous and belongs in the
    # hand-written list where somebody chooses on purpose.
    return [
        (head, group, "sr", rows[0])
        for (group, head), rows in sorted(by_head.items())
        if len(rows) == 1
    ]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_sr(sources: Path) -> tuple[dict, dict[str, str]]:
    """fdc_id -> (description, {nutrient: value}, basis).

    Every SR Legacy row carries all four of protein, fat, carbohydrate and
    energy; sodium is on 7,709 of 7,793. A row missing any of the five is
    dropped rather than zero-filled, because a zero-filled row is a real number
    that is wrong, where a dropped row falls back to the group and is merely
    coarse.
    """
    root = next(sources.glob("FoodData_Central_sr_legacy_food_csv*"), None)
    if root is None:
        archive = sources / "sr_legacy.zip"
        if not archive.exists():
            sys.exit(f"missing SR Legacy. Download {SR_URL} to {archive}")
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(sources)
        root = next(sources.glob("FoodData_Central_sr_legacy_food_csv*"))

    names, categories = {}, {}
    for r in csv.DictReader((root / "food.csv").open()):
        names[r["fdc_id"]] = r["description"]
        categories[r["fdc_id"]] = r["food_category_id"]

    gathered: dict[str, dict[str, float]] = {}
    for row in csv.DictReader((root / "food_nutrient.csv").open()):
        key = SR_NUTRIENTS.get(row["nutrient_id"])
        if key and row["amount"] and row["fdc_id"] in names:
            gathered.setdefault(row["fdc_id"], {})[key] = float(row["amount"])

    out = {}
    for row_id, values in gathered.items():
        if any(key not in values for key in REQUIRED):
            continue
        out[row_id] = (names[row_id], values, "analysed")
    return out, categories


def load_mext(sources: Path) -> dict[str, tuple[str, dict[str, float], str]]:
    """食品番号 -> (name, {nutrient: value}, basis), per 100 g of edible portion.

    The basis is the worst of the five: a row whose energy was analysed and
    whose sodium was estimated is an estimated row, because the figures are used
    together and provenance that only describes the best column is not
    provenance.
    """
    try:
        import openpyxl
    except ImportError:
        sys.exit("needs openpyxl: pip3 install --user openpyxl")

    path = sources / "mext.xlsx"
    if not path.exists():
        sys.exit(f"missing MEXT table. Download {MEXT_URL} to {path}")

    sheet = openpyxl.load_workbook(path, read_only=True, data_only=True)["表全体"]
    rows = list(sheet.iter_rows(min_row=1, max_row=2700, max_col=70, values_only=True))
    # Row 12 is 成分識別子, the machine-readable column key. Reading the column
    # by position instead would break on any revision that inserts a column,
    # and would do it silently.
    header = {value: index for index, value in enumerate(rows[11]) if value}
    missing = [column for column in MEXT_NUTRIENTS if column not in header]
    if missing:
        sys.exit(f"MEXT sheet has no {', '.join(missing)} column; the layout changed")

    out = {}
    for row in rows[12:]:
        number, name = row[1], row[3]
        if not number or not name:
            continue
        values: dict[str, float] = {}
        basis = "analysed"
        for column, key in MEXT_NUTRIENTS.items():
            parsed = parse_mext_value(row[header[column]])
            if parsed is None:
                continue
            values[key], column_basis = parsed
            if column_basis == "estimated":
                basis = "estimated"
        if any(key not in values for key in REQUIRED):
            continue
        out[str(number)] = (str(name).replace("　", " ").strip(), values, basis)
    return out


def parse_mext_value(value) -> tuple[float, str] | None:
    """One MEXT cell to (value, basis), or None when there is no figure.

    Three quarters of this column is text, not numbers, and the kinds mean
    different things:

      `21.0`   analysed. Note this is a *string* for 577 of 2538 rows — reading
               only the float cells silently drops a quarter of the table,
               including からしめんたいこ, the food that prompted this whole
               exercise.
      `(9.7)`  推計値: estimated from a similar food rather than analysed.
               Published and usable, but not a measurement, so it is kept and
               labelled — the same distinction `weight_source` draws in the
               golden set.
      `Tr`     微量: measured, and below the limit of quantitation. That is a
               figure — it says "effectively none" — and reading it as 0 is
               what the table means. Dropping it instead used to discard whole
               rows over a trace of sodium in tofu.
      `-` `*`  未測定: not measured. No figure, so the row falls back to the
               food group rather than reading zero.
    """
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return (float(value), "analysed")
    text = str(value).strip()
    basis = "analysed"
    if text.startswith("(") and text.endswith(")"):
        text, basis = text[1:-1].strip(), "estimated"
    if text in ("Tr", "tr"):
        return (0.0, basis)
    if text in ("-", "*", ""):
        return None
    try:
        return (float(text), basis)
    except ValueError:
        return None


def normalise(label: str) -> str:
    """Must agree with `FoodLabel.normalised` in Core, or the client will miss
    rows this script believes it published."""
    kept = [c.lower() if c.isalnum() or c.isspace() else " " for c in label]
    return " ".join("".join(kept).split())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", default=str(ROOT / "build" / "food-sources"))
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail instead of writing when the config is out of date",
    )
    args = parser.parse_args()
    sources = Path(args.sources)
    sources.mkdir(parents=True, exist_ok=True)

    sr, categories = load_sr(sources)
    mext = load_mext(sources)
    tables = {"sr": (sr, SR_VERSION), "mext": (mext, MEXT_VERSION)}

    foods: dict[str, dict] = {}
    groups: dict[str, dict] = {}
    missing: list[str] = []

    def resolve(source: str, row_id: str, group: str, what: str, chosen: bool) -> dict | None:
        """One source row to an emitted entry, or None with `missing` appended.

        `chosen` marks a row a person picked — curated, or a group
        representative — and changes what a failed check means rather than
        which checks run. A generated row that fails is the long tail and is
        dropped in silence, because 315 more stand behind it and the group
        table is already there. A chosen row that fails is somebody's decision
        going wrong and stops the build.

        The one exception is the per-group protein range, which is skipped for
        a chosen row entirely. It is a heuristic for spotting a dry form in the
        generated tail, and choosing a row on purpose is exactly the act of
        overriding it: toasted nori is genuinely 41.4 g of protein per 100 g
        against a `vegetables` ceiling of 12, and it is still the right row for
        a sheet of nori.
        """
        if group not in SOURCE_GROUPS:
            missing.append(f"{what}: {group!r} is not a known curation bucket")
            return None
        table, _ = tables[source]
        if row_id not in table:
            missing.append(f"{what}: no {source} row {row_id}")
            return None
        name, values, basis = table[row_id]

        def reject(reason: str) -> None:
            if chosen:
                missing.append(f"{what}: {reason} ({name})")

        low, high = PLAUSIBLE.get(group, (0.0, 100.0))
        if not chosen and not (low <= values["protein"] <= high):
            return None
        if not (PLAUSIBLE_KCAL[0] <= values["kcal"] <= PLAUSIBLE_KCAL[1]):
            reject(f"energy {values['kcal']} kcal/100 g outside {PLAUSIBLE_KCAL}")
            return None
        if group not in ATWATER_EXEMPT:
            off = atwater_disagreement(values)
            if off is not None and off > ATWATER_TOLERANCE:
                reject(f"energy disagrees with its own macros by {off:.0%}")
                return None

        per100g = {key: round(values[key], 2) for key in REQUIRED}
        return {
            "per100g": per100g,
            "source": f"{source}:{row_id}",
            "basis": basis,
            "name": name,
        }

    for group, source, row_id in GROUP_REPRESENTATIVE:
        entry = resolve(source, row_id, group, f"group {group}", chosen=True)
        if entry is not None:
            kind = food_kind(entry["name"], group)
            if kind not in FOOD_KINDS:
                missing.append(f"group {group} mapped to unknown FoodKind {kind!r}")
            else:
                groups[kind] = entry

    generated = proposals(sr, categories)
    curated_keys = {(alias, group, source, row_id) for alias, group, source, row_id in CURATION}
    # Curated last: a hand-picked row is a decision somebody made on purpose and
    # must survive a generated one that happens to share its key.
    for alias, group, source, row_id in generated + CURATION:
        curated = (alias, group, source, row_id) in curated_keys
        entry = resolve(source, row_id, group, f"{alias!r}", chosen=curated)
        if entry is None:
            continue
        kind = food_kind(alias, group)
        if kind not in FOOD_KINDS:
            missing.append(f"{alias!r} mapped to unknown FoodKind {kind!r}")
            continue
        key = f"{kind}|{normalise(alias)}"
        if key in foods and not curated and foods[key]["per100g"] != entry["per100g"]:
            missing.append(f"duplicate alias {key} disagrees")
        foods[key] = {**entry, "curated": curated}

    if missing:
        # Hard failure. A row that silently defaults is how a table stops being
        # a measurement and starts being an opinion.
        sys.exit("unresolved rows:\n  " + "\n  ".join(missing))

    config = json.loads(CONFIG.read_text())
    columns = "protein, fat, carbohydrate, energy, sodium — per 100 g of edible portion"
    table = {
        "version": f"{SR_VERSION}+{MEXT_VERSION}",
        "sources": {
            SR_VERSION: {"url": SR_URL, "column": f"nutrients 1003/1004/1005/1008/1093 ({columns})"},
            MEXT_VERSION: {"url": MEXT_URL, "column": f"PROT-/FAT-/CHOCDF-/ENERC_KCAL/NA ({columns})"},
        },
        "groups": dict(sorted(groups.items())),
        "foods": dict(sorted(foods.items())),
    }
    if args.check:
        if config.get("nutrientsPerGram") != table:
            sys.exit("shaman-config.json is out of date: re-run scripts/build-food-table.py")
        print(f"up to date: {len(foods)} foods, {len(groups)} groups")
        return

    config.pop("proteinPerGram", None)
    # The MEDAS/olive rating is retired. Do not preserve the legacy block just
    # because this generator starts from the last bundled config.
    config.pop("olives", None)
    config["nutrientsPerGram"] = table
    CONFIG.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")

    for name, path in (("sr_legacy.zip", sources / "sr_legacy.zip"), ("mext.xlsx", sources / "mext.xlsx")):
        if path.exists():
            print(f"{name} sha256 {sha256(path)}")
    hand = sum(1 for f in foods.values() if f["curated"])
    print(f"wrote {len(foods)} foods to {CONFIG.relative_to(ROOT)} "
          f"({hand} curated, {len(foods) - hand} generated) "
          f"and {len(groups)} group representatives")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Cut the bundled Sora statics out of the upstream variable font.

The identity is Sora, and it ships in the bundle. What ships is *not* the
upstream `Sora[wght].ttf`: iOS registers a variable font at its default
instance only, and there is no supported way to ask `UIFont(name:)` for another
one. A bundled variable file therefore renders every weight in the app at 400
while every lookup still succeeds — the same silent-and-wrong failure shape as
a missing resource, with nothing to catch it.

So the five weights the design actually uses are pinned here into five static
files, each with its own PostScript name, and `WellieTheme.fontsAreInstalled`
checks for all five at launch.

    pip install fonttools
    python3 scripts/build-fonts.py

Fetches the variable original from google/fonts and writes into
App/Resources/Fonts. The licence is fetched with it — OFL requires it ship
alongside.
"""

import os
import sys
import urllib.request

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

SOURCE = "https://github.com/google/fonts/raw/main/ofl/sora/Sora%5Bwght%5D.ttf"
LICENCE = "https://raw.githubusercontent.com/google/fonts/main/ofl/sora/OFL.txt"
DESTINATION = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "App", "Resources", "Fonts",
)

# The weights `WellieTheme.postScriptName(for:)` maps onto. 500 and 800 are not
# named instances in the upstream STAT table, which is why the name records are
# written by hand below rather than by `updateFontNames`.
CUTS = [(400, "Regular"), (500, "Medium"), (600, "SemiBold"), (700, "Bold"), (800, "ExtraBold")]

WINDOWS, MACINTOSH = (3, 1, 0x409), (1, 0, 0)


def main() -> int:
    os.makedirs(DESTINATION, exist_ok=True)
    variable, _ = urllib.request.urlretrieve(SOURCE)
    urllib.request.urlretrieve(LICENCE, os.path.join(DESTINATION, "Sora-OFL.txt"))

    for weight, style in CUTS:
        font = TTFont(variable)
        instancer.instantiateVariableFont(font, {"wght": weight}, inplace=True)

        postscript = f"Sora-{style}"
        names = font["name"]
        for identifier, value in (
            (1, "Sora"), (2, style), (3, f"1.000;{postscript}"),
            (4, f"Sora {style}"), (6, postscript), (16, "Sora"), (17, style),
        ):
            names.setName(value, identifier, *WINDOWS)
            names.setName(value, identifier, *MACINTOSH)

        font["OS/2"].usWeightClass = weight
        # Every cut is an upright regular face of its own weight. Leaving the
        # bold bit set on the 700 and 800 files invites the system to synthesise
        # a second bold on top of the one that is already drawn.
        font["OS/2"].fsSelection = (font["OS/2"].fsSelection & ~(1 << 5)) | (1 << 6)
        font["head"].macStyle &= ~1

        # Both describe the variable original, and neither survives pinning as
        # anything but a wrong answer about a font that no longer varies.
        for table in ("STAT", "DSIG"):
            if table in font:
                del font[table]

        path = os.path.join(DESTINATION, f"{postscript}.ttf")
        font.save(path)
        print(f"{postscript}.ttf  {os.path.getsize(path):,} bytes")

    return 0


if __name__ == "__main__":
    sys.exit(main())

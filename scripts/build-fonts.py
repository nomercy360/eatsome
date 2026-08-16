#!/usr/bin/env python3
"""Fetch the two bundled typefaces into App/Resources/Fonts.

The identity is General Sans for words and Space Grotesk for figures, and both
ship in the bundle. What ships is *static* cuts, one file per weight: iOS
registers a variable font at its default instance only, and there is no
supported way to ask `UIFont(name:)` for another one. A bundled variable file
therefore renders every weight in the app at 400 while every lookup still
succeeds — the same silent-and-wrong failure shape as a missing resource, with
nothing to catch it.

General Sans is distributed as statics already (Fontshare, ITF's free-font
EULA — apps are a permitted medium; redistribution is not, which is why this
script fetches rather than the repository vendoring a copy from elsewhere).
Space Grotesk's release ships Regular/Medium/Bold statics and a variable file;
the 600 the design uses for a figure inside a sentence is pinned from the
variable here. Both licences are written beside the files.

    pip install fonttools
    python3 scripts/build-fonts.py

`WellieTheme.fontsAreInstalled` checks every PostScript name below at launch.
"""

import io
import os
import zipfile
import urllib.request

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

GENERAL_SANS = "https://api.fontshare.com/v2/fonts/download/general-sans"
SPACE_GROTESK = (
    "https://github.com/floriankarsten/space-grotesk/releases/download/2.0.0/"
    "SpaceGrotesk-2.0.0.zip"
)
DESTINATION = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "App", "Resources", "Fonts",
)

# What `WellieTheme` asks for by PostScript name.
GENERAL_SANS_CUTS = ["Regular", "Medium", "Semibold", "Bold"]
SPACE_GROTESK_CUTS = ["Regular", "Medium", "Bold"]
SPACE_GROTESK_PINNED = [(600, "SemiBold")]


def fetch(url):
    print(f"fetching {url}")
    with urllib.request.urlopen(url) as response:
        return zipfile.ZipFile(io.BytesIO(response.read()))


def member(archive, suffix):
    matches = [n for n in archive.namelist() if n.endswith(suffix) and "__MACOSX" not in n]
    if len(matches) != 1:
        raise SystemExit(f"expected one {suffix} in the archive, found {matches}")
    return matches[0]


def write(name, data):
    path = os.path.join(DESTINATION, name)
    with open(path, "wb") as f:
        f.write(data)
    print(f"wrote {os.path.relpath(path)}")


def pin(variable, weight, style, family):
    """Cut one static instance with its own PostScript name."""
    font = instancer.instantiateVariableFont(variable, {"wght": weight}, inplace=False)
    compact = family.replace(" ", "")
    for record in font["name"].names:
        if record.nameID == 1:
            record.string = family
        elif record.nameID == 2:
            record.string = style
        elif record.nameID == 4:
            record.string = f"{family} {style}"
        elif record.nameID == 6:
            record.string = f"{compact}-{style}"
        elif record.nameID in (16, 17):
            record.string = family if record.nameID == 16 else style
    font["OS/2"].usWeightClass = weight
    out = io.BytesIO()
    font.save(out)
    return out.getvalue()


def main():
    os.makedirs(DESTINATION, exist_ok=True)

    gs = fetch(GENERAL_SANS)
    for cut in GENERAL_SANS_CUTS:
        write(f"GeneralSans-{cut}.otf", gs.read(member(gs, f"OTF/GeneralSans-{cut}.otf")))
    write("GeneralSans-FFL.txt", gs.read(member(gs, "License/FFL.txt")))

    sg = fetch(SPACE_GROTESK)
    for cut in SPACE_GROTESK_CUTS:
        write(f"SpaceGrotesk-{cut}.otf", sg.read(member(sg, f"otf/SpaceGrotesk-{cut}.otf")))
    variable = TTFont(io.BytesIO(sg.read(member(sg, "ttf/SpaceGrotesk[wght].ttf"))))
    for weight, style in SPACE_GROTESK_PINNED:
        write(f"SpaceGrotesk-{style}.ttf", pin(variable, weight, style, "Space Grotesk"))
    write("SpaceGrotesk-OFL.txt", sg.read(member(sg, "OFL.txt")))


if __name__ == "__main__":
    main()

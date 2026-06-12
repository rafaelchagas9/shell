#!/usr/bin/env python3

# Generate a dynamic colour scheme from an image (e.g. media album art) like
# `caelestia wallpaper -p`, but force the light/dark *mode* to the user's
# current preference instead of deriving it from the image's brightness.
#
# Upstream's "smart scheme" picks the mode from the art's average tone
# (light if tone > 60, else dark), so a mostly-white cover flips the whole
# system into light mode. Here we keep the smart *variant* selection from the
# art but pin the *mode*, so the colours are regenerated to match what the
# user actually wants.
#
# usage: print-scheme-for-art.py <image-path> [mode]
#   mode: "light" or "dark" (defaults to the persisted scheme's mode)

import json
import sys
from pathlib import Path

from PIL import Image

from caelestia.utils.colourfulness import get_variant
from caelestia.utils.material import get_colours_for_image
from caelestia.utils.paths import compute_hash, wallpapers_cache_dir
from caelestia.utils.scheme import Scheme, get_scheme, get_scheme_modes
from caelestia.utils.wallpaper import convert_gif, get_thumb


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: print-scheme-for-art.py <image-path> [mode]", file=sys.stderr)
        return 1

    wall = Path(sys.argv[1])
    persisted = get_scheme()

    # Mode preference: explicit arg wins, otherwise fall back to the user's
    # currently persisted mode. Guard against an invalid value.
    mode = sys.argv[2] if len(sys.argv) > 2 else persisted.mode
    if mode not in get_scheme_modes("dynamic", persisted.flavour):
        mode = persisted.mode

    cache = wallpapers_cache_dir / compute_hash(wall)

    if wall.suffix.lower() == ".gif":
        wall = convert_gif(wall)

    thumb = get_thumb(wall, cache)

    # Keep the smart *variant* chosen from the art, but pin the *mode*.
    with Image.open(thumb) as img:
        variant = get_variant(img)

    scheme = Scheme(
        {
            "name": "dynamic",
            "flavour": persisted.flavour,
            "mode": mode,
            "variant": variant,
            "colours": persisted.colours,
        }
    )

    print(
        json.dumps(
            {
                "name": "dynamic",
                "flavour": scheme.flavour,
                "mode": scheme.mode,
                "variant": scheme.variant,
                "colours": get_colours_for_image(thumb, scheme),
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

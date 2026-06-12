#!/usr/bin/env python3

import json
import sys
from pathlib import Path

from caelestia.utils.scheme import get_scheme
from caelestia.utils.theme import apply_colours


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: apply-scheme-json.py <scheme-json-path>", file=sys.stderr)
        return 1

    scheme_json = json.loads(Path(sys.argv[1]).read_text())
    scheme = get_scheme()

    # Apply the generated colours exactly as produced by `caelestia wallpaper -p`
    # without recomputing them from the persisted wallpaper thumbnail.
    scheme._name = scheme_json["name"]
    scheme._flavour = scheme_json["flavour"]
    scheme._mode = scheme_json["mode"]
    scheme._variant = scheme_json["variant"]
    scheme._colours = scheme_json["colours"]
    scheme.save()

    apply_colours(scheme.colours, scheme.mode)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

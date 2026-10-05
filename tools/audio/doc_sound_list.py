#!/usr/bin/env python3
"""Regenerate the sound list section of docs/design/audio.md from assets/audio/catalog.json.

The section between ``<!-- BEGIN SOUND LIST -->`` and ``<!-- END SOUND LIST -->`` is
replaced, so the design document always matches the generated catalogue.
"""

from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
CATALOG = os.path.join(REPO, "assets", "audio", "catalog.json")
DOC = os.path.join(REPO, "docs", "design", "audio.md")
BEGIN, END = "<!-- BEGIN SOUND LIST -->", "<!-- END SOUND LIST -->"

ORDER = ["engines", "tracks", "turret", "guns", "reload", "shells", "impacts", "armor", "damage", "destruction",
         "ui", "cues", "radio", "ambience", "weather", "hangar"]
TITLES = {
    "engines": "Engines", "tracks": "Tracks", "turret": "Turret and gun laying", "guns": "Gun firing",
    "reload": "Reload", "shells": "Shell flight", "impacts": "Shell ground impacts", "armor": "Armor results",
    "damage": "Damage", "destruction": "Environment destruction", "ui": "UI", "cues": "Battle information cues",
    "radio": "Radio / Voice", "ambience": "Ambience beds and spots", "weather": "Weather", "hangar": "Hangar / garage",
}


def table() -> str:
    with open(CATALOG, encoding="utf-8") as fh:
        cat = json.load(fh)["sounds"]
    out = [f"_Generated from `assets/audio/catalog.json` by `tools/audio/doc_sound_list.py` - {len(cat)} keys, "
           f"{sum(len(e['variants']) or 1 for e in cat.values())} files._", ""]
    for c in ORDER:
        keys = sorted(k for k, e in cat.items() if e["category"] == c)
        if not keys:
            continue
        out.append(f"#### {TITLES[c]} ({len(keys)})")
        out.append("")
        out.append("| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |")
        out.append("|---|---|---|---|---|---|---|---|")
        for k in keys:
            e = cat[k]
            var = len(e["variants"]) or 1
            kind = f"loop {e['durationS']:.0f}s" if e["loop"] else "one-shot"
            dv = e["suggested"]["distanceVariant"]
            if dv:
                kind += f" / {dv}"
            ev = e["event"].replace("|", "/")
            out.append(f"| `{k}` | {var} | {e['bus']} | {kind} | {e['durationS']:.2f} | {e['channels']} | "
                       f"{e['suggested']['priority']} | {ev} |")
        out.append("")
    return "\n".join(out)


def main() -> int:
    with open(DOC, encoding="utf-8") as fh:
        doc = fh.read()
    if BEGIN not in doc or END not in doc:
        print("markers not found", file=sys.stderr)
        return 1
    a = doc.index(BEGIN) + len(BEGIN)
    b = doc.index(END)
    doc = doc[:a] + "\n" + table() + "\n" + doc[b:]
    with open(DOC, "w", encoding="utf-8") as fh:
        fh.write(doc)
    print(f"updated {DOC}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

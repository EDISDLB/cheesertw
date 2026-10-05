#!/usr/bin/env python3
"""Regenerate the generated tables of docs/design/audio.md from the catalogues.

* ``<!-- BEGIN SOUND LIST -->`` ... ``<!-- END SOUND LIST -->`` from ``assets/audio/catalog.json``
* ``<!-- BEGIN MUSIC LIST -->`` ... ``<!-- END MUSIC LIST -->`` from ``assets/music/catalog.json``

so the design document always matches the generated assets.
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
MUSIC_CATALOG = os.path.join(REPO, "assets", "music", "catalog.json")
M_BEGIN, M_END = "<!-- BEGIN MUSIC LIST -->", "<!-- END MUSIC LIST -->"

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


def music_table() -> str:
    with open(MUSIC_CATALOG, encoding="utf-8") as fh:
        cat = json.load(fh)
    cues = cat["cues"]
    order = ["main_theme", "garage_theme", "loading_theme", "battle_base", "battle_mid", "battle_high", "battle_endgame",
             "victory", "defeat", "draw", "results_theme"] + sorted(k for k in cues if k.startswith("map_"))
    banked = {k: e["bankRegion"]["bank"] for k, e in cues.items() if e.get("bankRegion")}
    out = [f"_Generated from `assets/music/catalog.json` by `tools/audio/doc_sound_list.py` - {len(cues)} files, "
           f"{len(cat.get('banks', {}))} stinger banks._", "",
           "| Key | State | Type | Len s | Tempo / meter | Key | Bar 1 at | LUFS | Vol | Motif | Upload as |",
           "|---|---|---|---|---|---|---|---|---|---|---|"]
    for k in [k for k in order if k in cues]:
        e = cues[k]
        if e["kind"] == "loop":
            kind = "loop" + (f" ({e['stem']} stem)" if e.get("stem") else "")
            at = f"{e['loop']['gridOffsetSamples']} smp"
        else:
            kind = "stinger"
            at = f"{e['stinger']['leadS'] * 1000:.0f} ms"
        forms = sorted({m["form"].replace("motif_", "").replace("motif", "full") for m in e["motif"]})
        motif = f"{len(e['motif'])}x ({', '.join(forms)})" if e["motif"] else "-"
        up = f"`{banked[k]}`" if k in banked else f"`{e['file']}`"
        out.append(f"| `{k}` | {e['state']} | {kind} | {e['durationS']:.2f} | {e['bpm']:g} BPM {e['meter']} | {e['key']} | "
                   f"{at} | {e['loudnessLufs']:.1f} | {e['suggested']['volume']} | {motif} | {up} |")
    return "\n".join(out)


def replace_between(doc: str, begin: str, end: str, body: str) -> str:
    a = doc.index(begin) + len(begin)
    b = doc.index(end)
    return doc[:a] + "\n" + body + "\n" + doc[b:]


def main() -> int:
    with open(DOC, encoding="utf-8") as fh:
        doc = fh.read()
    if BEGIN not in doc or END not in doc:
        print("markers not found", file=sys.stderr)
        return 1
    doc = replace_between(doc, BEGIN, END, table())
    if M_BEGIN in doc and M_END in doc and os.path.exists(MUSIC_CATALOG):
        doc = replace_between(doc, M_BEGIN, M_END, music_table())
    with open(DOC, "w", encoding="utf-8") as fh:
        fh.write(doc)
    print(f"updated {DOC}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Render spectrogram review sheets (PNG) for generated audio.

Sheets go to ``build/audio_review/<sheet>.png``; each panel shows a waveform strip and a
log-frequency spectrogram with peak and spectral-centroid annotations, so distinctness of
gameplay-critical sounds can be checked visually.

    python3 tools/audio/review_audio.py                  # all predefined sheets
    python3 tools/audio/review_audio.py --sheet armor_results
    python3 tools/audio/review_audio.py --keys engine_heavy_diesel_mid,engine_turbine_mid --name adhoc
"""

from __future__ import annotations

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from synth import io  # noqa: E402
from synth.analysis import render_panels  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
AUDIO = os.path.join(REPO, "assets", "audio")
OUT = os.path.join(REPO, "build", "audio_review")

# name -> (title, [(label, file-or-key[, variant])...], duration or None, columns)
SHEETS = {
    "armor_results": ("Armor results - must be instantly distinguishable", [
        ("PENETRATION", "armor_penetration", "a"), ("RICOCHET", "armor_ricochet", "a"),
        ("BLOCKED (non-pen)", "armor_blocked", "a"), ("CRITICAL MODULE", "armor_critical", "a"),
        ("HIT TAKEN (inside, pen)", "armor_hit_taken_pen", "a"), ("HIT TAKEN (inside, blocked)", "armor_hit_taken_blocked", "a"),
    ], 1.6, 2),
    "engine_families": ("Engine families - mid RPM layer (2 s excerpt)", [
        ("heavy_diesel mid", "engine_heavy_diesel_mid", None), ("medium_diesel mid", "engine_medium_diesel_mid", None),
        ("light_highrpm mid", "engine_light_highrpm_mid", None), ("large_v12 mid", "engine_large_v12_mid", None),
        ("small_engine mid", "engine_small_engine_mid", None), ("turbine mid", "engine_turbine_mid", None),
    ], 2.0, 2),
    "engine_layers": ("Heavy diesel RPM layers + damaged/overload (1.5 s excerpt)", [
        ("idle", "engine_heavy_diesel_idle", None), ("low", "engine_heavy_diesel_low", None),
        ("mid", "engine_heavy_diesel_mid", None), ("high", "engine_heavy_diesel_high", None),
        ("damaged", "engine_heavy_diesel_damaged", None), ("overload", "engine_heavy_diesel_overload", None),
    ], 1.5, 2),
    "engine_start_stop": ("Start-up / shut-down one-shots", [
        ("heavy_diesel start", "engine_heavy_diesel_start", None), ("heavy_diesel stop", "engine_heavy_diesel_stop", None),
        ("turbine start", "engine_turbine_start", None), ("turbine stop", "engine_turbine_stop", None),
    ], 6.5, 2),
    "guns_close": ("Gun classes - close variant", [
        ("small 20-45mm", "gun_small_20_45mm_close", "a"), ("medium 50-85mm", "gun_medium_50_85mm_close", "a"),
        ("large 88-122mm", "gun_large_88_122mm_close", "a"), ("huge 130-183mm", "gun_huge_130_183mm_close", "a"),
        ("autocannon burst", "gun_autocannon_burst_close", "a"), ("artillery howitzer", "gun_artillery_howitzer_close", "a"),
    ], 3.0, 2),
    "guns_distance": ("Large gun - close vs mid vs far", [
        ("close", "gun_large_88_122mm_close", "a"), ("mid", "gun_large_88_122mm_mid", "a"), ("far", "gun_large_88_122mm_far", "a"),
    ], 4.0, 1),
    "shells": ("Shell flybys and ground impacts", [
        ("flyby AP", "shell_flyby_ap", "a"), ("flyby HE", "shell_flyby_he", "a"), ("artillery whistle", "shell_whistle_artillery", "a"),
        ("impact dirt", "impact_dirt", "a"), ("impact water", "impact_water", "a"), ("impact metal building", "impact_metal_building", "a"),
    ], 2.5, 2),
    "tracks": ("Track surfaces (2 s excerpt)", [
        ("dirt", "track_dirt", None), ("gravel", "track_gravel", None), ("concrete", "track_concrete", None),
        ("mud", "track_mud", None), ("snow", "track_snow", None), ("metal", "track_metal", None),
    ], 2.0, 2),
    "battle_cues": ("Battle information cues", [
        ("sixth sense", "cue_sixth_sense", None), ("enemy spotted", "cue_enemy_spotted", None),
        ("reload complete", "cue_reload_complete", None), ("target locked", "cue_target_locked", None),
        ("ally destroyed", "cue_ally_destroyed", None), ("enemy destroyed", "cue_enemy_destroyed", None),
    ], 1.6, 2),
    "ui": ("UI set", [
        ("hover", "ui_hover", None), ("click", "ui_click", None), ("confirm", "ui_confirm", None), ("error", "ui_error", None),
        ("purchase", "ui_purchase", None), ("vehicle unlocked", "ui_vehicle_unlocked", None),
    ], 2.5, 2),
    "damage": ("Damage and destruction", [
        ("fire ignition", "dmg_fire_ignition", None), ("ammo rack detonation close", "dmg_ammo_rack_detonation_close", None),
        ("vehicle destroyed large close", "dmg_vehicle_destroyed_large_close", None), ("crew injured", "dmg_crew_injured", None),
    ], 5.0, 2),
    "ambience": ("Ambience beds (20 s excerpt)", [
        ("temperate valley industrial", "amb_temperate_valley_industrial_bed", None), ("desert", "amb_desert_bed", None),
        ("winter", "amb_winter_bed", None), ("harbor", "amb_harbor_bed", None),
    ], 20.0, 1),
}


def _load_catalog() -> dict:
    with open(os.path.join(AUDIO, "catalog.json"), encoding="utf-8") as fh:
        return json.load(fh)["sounds"]


def _resolve(cat: dict, key: str, variant: str | None) -> str | None:
    e = cat.get(key)
    if e is None:
        return None
    if variant and e.get("variants"):
        for f in e["variants"]:
            if f.endswith(f"_{variant}.ogg"):
                return os.path.join(AUDIO, f)
    return os.path.join(AUDIO, e["file"])


def render_sheet(name: str, title: str, items, duration, columns, cat: dict) -> str | None:
    panels = []
    for label, key, var in items:
        path = _resolve(cat, key, var)
        if path is None or not os.path.exists(path):
            print(f"  skip {key} (not generated)")
            continue
        x, _ = io.read(path)
        panels.append((label, x))
    if not panels:
        return None
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, f"{name}.png")
    width = 820 if columns > 1 else 1500
    render_panels(panels, out, width=width, spec_h=200, wave_h=40, duration=duration, columns=columns, title=title)
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", default="")
    ap.add_argument("--keys", default="")
    ap.add_argument("--name", default="adhoc")
    ap.add_argument("--duration", type=float, default=None)
    ap.add_argument("--columns", type=int, default=2)
    args = ap.parse_args(argv)
    cat = _load_catalog()
    if args.keys:
        items = []
        for k in args.keys.split(","):
            k, _, v = k.strip().partition(":")
            items.append((k + (f" {v}" if v else ""), k, v or None))
        p = render_sheet(args.name, args.name, items, args.duration, args.columns, cat)
        print(p)
        return 0
    names = [args.sheet] if args.sheet else list(SHEETS)
    for nm in names:
        title, items, dur, cols = SHEETS[nm]
        p = render_sheet(nm, title, items, dur, cols, cat)
        print(p or f"{nm}: nothing to render")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

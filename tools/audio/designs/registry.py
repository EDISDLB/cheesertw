"""Sound registry: every asset key, its render function, bus, loudness target and mix hints.

Design modules call :func:`sound` to register entries; ``generate_sfx.py`` renders them.

Loudness targets (``level``) are in LUFS:

* one-shots - *maximum momentary loudness* (400 ms window), which tracks perceived punch;
* loops     - *integrated loudness* of the loop.

A sample-peak ceiling of -1.5 dBFS is applied before encoding; the decoded OGG must stay at
or below -1.0 dBFS (verified after encoding, with automatic gain trim if needed).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

import numpy as np

STUDS_PER_METER = 3.0

BUSES = ("Master", "Music", "Ambience", "Vehicles", "Weapons", "Impacts", "UI", "Voice")

# Default mixing hints per category (overridable per sound).
CATEGORY_DEFAULTS: dict[str, dict] = {
    "engines": dict(bus="Vehicles", channels=1, level=-18.0, volume=0.7, min_m=4, max_m=160, priority=60),
    "tracks": dict(bus="Vehicles", channels=1, level=-20.0, volume=0.6, min_m=3, max_m=110, priority=55),
    "turret": dict(bus="Vehicles", channels=1, level=-24.0, volume=0.5, min_m=2, max_m=30, priority=45),
    "guns": dict(bus="Weapons", channels=1, level=-10.0, volume=1.0, min_m=8, max_m=220, priority=90),
    "reload": dict(bus="Weapons", channels=1, level=-20.0, volume=0.6, min_m=1, max_m=20, priority=60),
    "shells": dict(bus="Weapons", channels=1, level=-14.0, volume=0.9, min_m=5, max_m=80, priority=80),
    "impacts": dict(bus="Impacts", channels=1, level=-13.0, volume=0.85, min_m=8, max_m=400, priority=70),
    "armor": dict(bus="Impacts", channels=1, level=-11.0, volume=1.0, min_m=10, max_m=500, priority=95),
    "damage": dict(bus="Impacts", channels=1, level=-14.0, volume=0.85, min_m=6, max_m=300, priority=80),
    "destruction": dict(bus="Impacts", channels=1, level=-16.0, volume=0.7, min_m=5, max_m=300, priority=50),
    "ui": dict(bus="UI", channels=2, level=-20.0, volume=0.6, min_m=None, max_m=None, priority=70),
    "cues": dict(bus="UI", channels=2, level=-16.0, volume=0.8, min_m=None, max_m=None, priority=90),
    "radio": dict(bus="Voice", channels=2, level=-18.0, volume=0.7, min_m=None, max_m=None, priority=80),
    "ambience": dict(bus="Ambience", channels=2, level=-25.0, volume=0.5, min_m=None, max_m=None, priority=20),
    "weather": dict(bus="Ambience", channels=2, level=-24.0, volume=0.5, min_m=None, max_m=None, priority=25),
    "hangar": dict(bus="Ambience", channels=2, level=-26.0, volume=0.5, min_m=None, max_m=None, priority=20),
}

# Distance bands (metres). Studs = metres * 3.
DISTANCE_BANDS_M = {"close": (0, 120), "mid": (120, 450), "far": (450, 1500)}


@dataclass
class Sound:
    key: str
    category: str
    render: Callable[[np.random.Generator, str], np.ndarray]
    description: str
    event: str
    bus: str
    channels: int
    level: float
    loop: bool = False
    loop_s: float | None = None
    variants: tuple[str, ...] = ()
    volume: float = 0.7
    min_m: float | None = None
    max_m: float | None = None
    distance_variant: str | None = None
    priority: int = 50
    group: str | None = None
    meta: dict = field(default_factory=dict)
    quality: float = 0.65

    @property
    def files(self) -> list[str]:
        if self.variants:
            return [f"{self.category}/{self.key}_{v}.ogg" for v in self.variants]
        return [f"{self.category}/{self.key}.ogg"]

    def suggested(self) -> dict:
        def studs(m):
            return None if m is None else int(round(m * STUDS_PER_METER))

        return {
            "volume": round(self.volume, 3),
            "rollOffMinStuds": studs(self.min_m),
            "rollOffMaxStuds": studs(self.max_m),
            "distanceVariant": self.distance_variant,
            "priority": int(self.priority),
        }


REGISTRY: dict[str, Sound] = {}


def sound(
    key: str,
    category: str,
    render: Callable,
    description: str,
    event: str,
    *,
    loop: bool = False,
    loop_s: float | None = None,
    variants: tuple[str, ...] | str = (),
    **overrides,
) -> Sound:
    """Register a sound. ``overrides`` may set any :class:`Sound` field (bus, level, volume,
    min_m, max_m, distance_variant, priority, group, meta, channels, quality)."""
    if key in REGISTRY:
        raise ValueError(f"duplicate sound key {key}")
    d = dict(CATEGORY_DEFAULTS[category])
    d.update(overrides)
    if isinstance(variants, str):
        variants = tuple(variants)
    s = Sound(
        key=key,
        category=category,
        render=render,
        description=description,
        event=event,
        bus=d["bus"],
        channels=d["channels"],
        level=d["level"],
        loop=loop,
        loop_s=loop_s,
        variants=tuple(variants),
        volume=d["volume"],
        min_m=d["min_m"],
        max_m=d["max_m"],
        distance_variant=d.get("distance_variant"),
        priority=d["priority"],
        group=d.get("group"),
        meta=d.get("meta", {}),
        quality=d.get("quality", 0.65),
    )
    REGISTRY[key] = s
    return s

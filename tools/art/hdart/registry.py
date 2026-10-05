"""Icon registry: every generated icon outside the original brand sets is declared here by the group
modules (ammo, modules, crew, consumables, equipment, ui, battle, achievements, missions, markers).

generate_svgs.py walks REGISTRY to write assets/icons/<group>/<key>.svg and builds
assets/icons/INDEX.md from the same records, so the index can never drift from the files.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

TINT_NOTE = " (white, tint with ImageColor3)"


@dataclass
class Icon:
    group: str  # folder under assets/icons/
    key: str  # file stem and content key
    title: str  # <title> of the SVG
    use: str  # intended use (INDEX.md)
    draw: Callable  # draw(doc) -> None
    w: float = 64
    h: float = 64
    tint: bool = False  # white art meant for ImageColor3 tinting
    subdir: str = ""  # optional sub-folder inside the group (e.g. "examples")

    @property
    def rel(self) -> str:
        parts = ["icons", self.group] + ([self.subdir] if self.subdir else []) + [f"{self.key}.svg"]
        return "/".join(parts)


REGISTRY: list[Icon] = []
GROUP_NOTES: dict[str, str] = {}


def add(group: str, key: str, title: str, use: str, draw: Callable, w: float = 64, h: float = 64,
        tint: bool = False, subdir: str = "") -> Icon:
    if any(i.group == group and i.key == key and i.subdir == subdir for i in REGISTRY):
        raise ValueError(f"duplicate icon {group}/{key}")
    ic = Icon(group, key, title, use, draw, w, h, tint, subdir)
    REGISTRY.append(ic)
    return ic


def note(group: str, text: str):
    """Group-level usage note printed above the group's table in INDEX.md."""
    GROUP_NOTES[group] = text

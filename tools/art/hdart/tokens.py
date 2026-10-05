"""HULLDOWN colour tokens and icon materials.

Single source of truth for every colour used by the art generators. The brand guide
(docs/design/brand-art.md) documents these same values, and generate_svgs.py writes them
to assets/brand/tokens.json so client code can mirror them without retyping hex values.
"""

from __future__ import annotations

# ---------------------------------------------------------------------------
# UI colour tokens (sRGB hex). Names are the token ids used in code and docs.
# ---------------------------------------------------------------------------
UI = {
    # Surfaces: cool gunmetal, darkest first.
    "bg.abyss": "#0A0D10",  # loading / cinematic backdrop, letterbox
    "bg.base": "#0F1418",  # app background behind garage panels
    "bg.panel": "#151C21",  # standard panel
    "bg.raised": "#1C252C",  # cards, list rows, hovered panel
    "bg.inset": "#0C1013",  # wells, input fields, progress tracks
    "bg.selected": "#26323B",  # selected card / active tab body
    "bg.scrim": "#0A0D10CC",  # modal scrim (80 %)
    # Borders and bevel edges.
    "border.subtle": "#25303A",
    "border.strong": "#3A4855",
    "border.bevel_hi": "#56687A",  # 1 px top bevel highlight on raised metal
    "border.bevel_lo": "#070A0C",  # 1 px bottom bevel shadow
    # Text.
    "text.primary": "#EAEFF2",
    "text.secondary": "#A8B5C0",
    "text.tertiary": "#76838F",
    "text.disabled": "#4B5661",
    "text.inverse": "#0C1013",
    "text.brand": "#E9DFC6",  # bone, wordmark & display headings only
    # Brand + accents.
    "brand.bone": "#E9DFC6",
    "brand.khaki": "#B9A77C",
    "brand.olive": "#5E6640",
    "accent.dusk": "#FF7A2F",  # THE accent: ridge line, primary CTA, focus
    "accent.dusk_hi": "#FFA066",
    "accent.dusk_lo": "#C9541A",
    "accent.steel": "#8FA3B5",  # secondary accent: neutral interactive chrome
    # States (always paired with an icon or label; never colour alone).
    "state.success": "#3FCB7A",
    "state.warning": "#F2C230",
    "state.danger": "#EF4747",
    "state.info": "#4AA8F0",
    # Teams (default palette).
    "team.ally": "#47D16C",
    "team.enemy": "#F0443A",
    "team.platoon": "#FFD23F",
    "team.self": "#F4F7F9",
    "team.neutral": "#B3BDC6",  # uncaptured base, neutral objects
    "team.destroyed": "#5D666E",
    # Rarity ladder.
    "rarity.common": "#A9B3BC",
    "rarity.uncommon": "#62C155",
    "rarity.rare": "#3E9BFF",
    "rarity.epic": "#A970FF",
    "rarity.legendary": "#FFB13B",
    "rarity.prototype": "#FF5A7A",
    # Currency signature colours (UI text/number tint for each currency).
    "currency.credits": "#E0955A",
    "currency.bullion": "#F4C653",
    "currency.vehicle_xp": "#5BB1F5",
    "currency.free_xp": "#B08CFF",
    "currency.crew_xp": "#3FD0BE",
    "currency.campaign_token": "#EC6A93",
}

# Colour-blind safe alternates for the four team roles. Selected per user setting; shapes and
# marker silhouettes stay identical, only hues change. Every pair of roles keeps CIEDE2000 >= 20
# for the intended viewer (simulated): verified by tools/art/check_palette.py.
TEAM_CVD = {
    "default": {"ally": "#47D16C", "enemy": "#F0443A", "platoon": "#FFD23F", "self": "#F4F7F9"},
    # Red/green deficiencies separate colours on the blue-yellow axis and by lightness: blue ally,
    # amber/orange enemy, and a deliberately darker rose platoon (reads as a dark tone to
    # protan/deutan viewers, clearly apart from both teams and from the white self marker).
    "deuteranopia": {"ally": "#3F8CFF", "enemy": "#FF8719", "platoon": "#BF1C6D", "self": "#F4F7F9"},
    "protanopia": {"ally": "#3F8CFF", "enemy": "#FFBE19", "platoon": "#BF4C5F", "self": "#F4F7F9"},
    # Blue/yellow deficiency: red enemy stays, ally moves to mid blue, platoon to deep violet.
    "tritanopia": {"ally": "#418CD8", "enemy": "#EF3F34", "platoon": "#7F33CC", "self": "#F4F7F9"},
}

# Faction identity colours: primary (enamel), secondary (metal/trim), and a text-safe tint.
FACTIONS = {
    "iron_union": {"name": "IRON UNION", "primary": "#B8492A", "secondary": "#59616A", "tint": "#E07A55"},
    "crown_industries": {"name": "CROWN INDUSTRIES", "primary": "#5A3D8C", "secondary": "#D6AA4E", "tint": "#B79BE8"},
    "eastern_armor": {"name": "EASTERN ARMOR GROUP", "primary": "#1C8582", "secondary": "#E9DFC6", "tint": "#4FC9C2"},
    "desert_corps": {"name": "DESERT ARMOR CORPS", "primary": "#C8933A", "secondary": "#7A5530", "tint": "#E8B868"},
    "mountain_republic": {"name": "MOUNTAIN REPUBLIC", "primary": "#3C7650", "secondary": "#F2F5F7", "tint": "#74B98A"},
    "northern_federation": {"name": "NORTHERN FEDERATION", "primary": "#4F8FCB", "secondary": "#EEF6FC", "tint": "#8EC3EE"},
}

# ---------------------------------------------------------------------------
# Icon materials: (highlight, base, shade). Two tones + one highlight, by rule.
# 'ink' is the universal keyline / recess colour.
# ---------------------------------------------------------------------------
INK = "#0A0D10"

MATERIALS = {
    "gunmetal": ("#7E8C99", "#38434E", "#1C242B"),
    "steel": ("#E2E9EF", "#9AA7B3", "#596673"),
    "bone": ("#FFFBF0", "#E3D8BC", "#A3936D"),
    "khaki": ("#E6D9B4", "#B4A275", "#6F6141"),
    "olive": ("#8E9862", "#5B6339", "#363C21"),
    "brass": ("#FFE6A0", "#D3A54A", "#86641F"),
    "bronze": ("#F4C49B", "#B5774A", "#6B4227"),
    "silver": ("#FFFFFF", "#C6CED6", "#78848F"),
    "gold": ("#FFF0B0", "#F0BD45", "#A8741A"),
    "obsidian": ("#56626E", "#1B2228", "#0B0F12"),
    "dusk": ("#FFC08F", "#FF7A2F", "#B8460F"),
    "copper": ("#FFD3AD", "#D98A4B", "#8C4E22"),
    "xp_blue": ("#C4E5FF", "#4FA6EE", "#21609B"),
    "xp_violet": ("#E4D6FF", "#A27CF4", "#5B3AA6"),
    "xp_teal": ("#C2FFF5", "#33C3B1", "#167167"),
    "rose": ("#FFD1DF", "#E2577F", "#8E2446"),
    # Faction enamels.
    "f_iron": ("#E98A63", "#B8492A", "#6E2615"),
    "f_crown": ("#A485D6", "#5A3D8C", "#30204F"),
    "f_eastern": ("#7FD8D2", "#1C8582", "#0B4745"),
    "f_desert": ("#F6CF86", "#C8933A", "#7A5420"),
    "f_desert_dark": ("#B48557", "#7A5530", "#463019"),
    "f_mountain": ("#86C49A", "#3C7650", "#1E412A"),
    "f_northern": ("#B5DBF7", "#4F8FCB", "#24527F"),
    "snow": ("#FFFFFF", "#EEF4F8", "#AFC0CE"),
}


def hexrgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def as_json() -> dict:
    return {
        "ui": UI,
        "team_cvd": TEAM_CVD,
        "factions": FACTIONS,
        "materials": {k: {"highlight": v[0], "base": v[1], "shade": v[2]} for k, v in MATERIALS.items()},
        "ink": INK,
    }

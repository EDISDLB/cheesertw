"""HULLDOWN music scores, written as data (tempo, meter, key, progressions, motifs, parts).

:data:`CUES` maps a build name to the function that returns its :class:`synth.music.Cue`.
A cue with several stems (``battle``) produces one file per stem.
"""

from __future__ import annotations

from . import battle, maps, stingers, themes

CUES = {
    "main_theme": themes.main_theme,
    "garage_theme": themes.garage_theme,
    "loading_theme": themes.loading_theme,
    "battle": battle.battle,
    "battle_endgame": battle.battle_endgame,
    "victory": stingers.victory,
    "defeat": stingers.defeat,
    "draw": stingers.draw,
    "results_theme": themes.results_theme,
}
for _fn in maps.MAPS:
    CUES[f"map_{_fn.__name__}"] = _fn

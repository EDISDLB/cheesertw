"""HULLDOWN procedural audio DSP library.

A small numpy/scipy toolkit used to synthesise every HULLDOWN sound effect and music cue from
code - no recorded samples. Modules:

========== ==================================================================
core       sample-rate constants, deterministic RNG, dB helpers, note names
osc        band-limited sine/saw/square/triangle, additive, modal, FM, chirps
noise      white/pink/brown/band noise (periodic), random control curves, dust
env        ADSR, percussive/exponential decays, breakpoints, fades, gates
filters    RBJ biquads (LP/HP/BP/notch/peak/shelf), one-poles, time-varying sweeps,
           Butterworth, resonator banks, combs
mod        LFOs, AM/ring modulation, vibrato, Doppler, loop-safe frequency snapping
fx         saturation/distortion, bitcrush, delay, compressor/limiter, resampling
           pitch shift, variable-speed playback, granular textures
reverb     convolution reverb with synthesised IRs (room, hangar, slapback, valley...)
mix        placement/mixing, panning, loudness (BS.1770), normalisation, loop tools
io         OGG Vorbis / WAV export (byte-reproducible OGG)
analysis   measurements, spectral features, spectrogram PNG rendering; music analysis (chroma,
           key estimate, onset envelope, tempo, beat-grid phase, semitone pitchgrams)
instruments orchestral/folk instrument models for the score (strings, brass, choir, organ,
           winds, reeds, plucks, piano, bells, timpani, taiko, snares, cymbals, ...)
music      music theory (scales, chords, voicing), score data (Note/Part/Cue, text parsers for
           melodies, drum grids, progressions) and the loop-safe cue renderer
========== ==================================================================
"""

from . import analysis, core, env, filters, fx, instruments, io, mix, mod, music, noise, osc, reverb  # noqa: F401
from .core import SR, make_rng, n_of, note_hz, t_of  # noqa: F401

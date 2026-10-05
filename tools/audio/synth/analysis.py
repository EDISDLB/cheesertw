"""Objective analysis and visual review (spectrogram PNGs rendered with Pillow).

Because the pipeline is validated without listening, this module provides the numbers
(peak, loudness, DC, seam quality, spectral shape) and pictures (log-frequency
spectrograms with waveform strips) used by ``validate_audio.py`` and ``review_audio.py``, plus
music analysis (chroma and key estimate, onset envelope, tempo, beat-grid phase, semitone
"pitchgram" images) used by ``validate_music.py``.
"""

from __future__ import annotations

import numpy as np
from scipy.signal import stft

from .core import SR, to_mono
from .mix import dc_offset, loudness_integrated, loudness_momentary_max, peak_db, rms_db, seam_metrics, true_peak_db


def spectral_features(x: np.ndarray, sr: int = SR) -> dict:
    """Spectral centroid, rolloff (85 %), low/mid/high band energy shares, crest factor."""
    m = to_mono(x)
    if m.size < 64:
        return {}
    spec = np.abs(np.fft.rfft(m * np.hanning(m.size))) ** 2
    f = np.fft.rfftfreq(m.size, 1 / sr)
    tot = spec.sum() + 1e-20
    cen = float((f * spec).sum() / tot)
    cum = np.cumsum(spec) / tot
    roll = float(f[min(np.searchsorted(cum, 0.85), f.size - 1)])
    low = float(spec[f < 250].sum() / tot)
    mid = float(spec[(f >= 250) & (f < 2500)].sum() / tot)
    high = float(spec[f >= 2500].sum() / tot)
    rms = np.sqrt(np.mean(m * m))
    crest = float(20 * np.log10(np.max(np.abs(m)) / max(rms, 1e-12)))
    return {"centroidHz": cen, "rolloff85Hz": roll, "lowShare": low, "midShare": mid, "highShare": high, "crestDb": crest}


def measure(x: np.ndarray, sr: int = SR, loop: bool = False) -> dict:
    out = {
        "durationS": x.shape[0] / sr,
        "channels": 1 if x.ndim == 1 else x.shape[1],
        "peakDb": peak_db(x),
        "truePeakDb": true_peak_db(x),
        "rmsDb": rms_db(x),
        "dcOffset": dc_offset(x),
        "lufsIntegrated": loudness_integrated(x, sr),
        "lufsMomentaryMax": loudness_momentary_max(x, sr),
    }
    if loop:
        out["seam"] = seam_metrics(x)
    return out


def log_mel_profile(x: np.ndarray, sr: int = SR, bands: int = 40) -> np.ndarray:
    """Time-averaged log band energies on a mel-like scale (for distinctness checks)."""
    m = to_mono(x)
    f, _, Z = stft(m, sr, nperseg=2048, noverlap=1536)
    p = np.abs(Z) ** 2
    mel = lambda hz: 2595 * np.log10(1 + hz / 700.0)  # noqa: E731
    edges = np.linspace(mel(40), mel(16000), bands + 1)
    hz_edges = 700 * (10 ** (edges / 2595) - 1)
    prof = np.zeros(bands)
    for i in range(bands):
        sel = (f >= hz_edges[i]) & (f < hz_edges[i + 1])
        prof[i] = p[sel].mean() if np.any(sel) else 1e-20
    return 10 * np.log10(prof + 1e-20)


def envelope_profile(x: np.ndarray, sr: int = SR, points: int = 64, span_s: float = 1.0) -> np.ndarray:
    m = np.abs(to_mono(x))
    n = int(span_s * sr)
    m = np.concatenate([m, np.zeros(max(0, n - m.size))])[:n]
    blocks = m.reshape(points, -1).max(axis=1)
    return 20 * np.log10(blocks / max(blocks.max(), 1e-12) + 1e-6)


# --------------------------------------------------------------------------- rendering
_INFERNO = np.array(
    [
        [0, 0, 4], [31, 12, 72], [85, 15, 109], [136, 34, 106], [186, 54, 85],
        [227, 89, 51], [249, 140, 10], [249, 201, 50], [252, 255, 164],
    ],
    dtype=np.float64,
)


def _colormap(v: np.ndarray) -> np.ndarray:
    v = np.clip(v, 0.0, 1.0) * (len(_INFERNO) - 1)
    i = np.clip(np.floor(v).astype(int), 0, len(_INFERNO) - 2)
    f = (v - i)[..., None]
    return (_INFERNO[i] * (1 - f) + _INFERNO[i + 1] * f).astype(np.uint8)


def spectrogram_image(x: np.ndarray, sr: int = SR, width: int = 900, height: int = 260, fmin: float = 30.0,
                      fmax: float = 20000.0, db_range: float = 90.0, duration: float | None = None):
    """Log-frequency spectrogram as a Pillow image (time left->right, low freq at bottom)."""
    from PIL import Image

    m = to_mono(x)
    if duration is not None:
        n = int(duration * sr)
        m = np.concatenate([m, np.zeros(max(0, n - m.size))])[:n]
    nper = 2048
    hop = max(32, int(m.size / width))
    f, _, Z = stft(m, sr, nperseg=nper, noverlap=max(0, nper - hop), boundary="zeros")
    mag = 20 * np.log10(np.abs(Z) + 1e-9)
    top = mag.max()
    norm = (mag - (top - db_range)) / db_range
    # resample to log-frequency rows: interpolate where rows are denser than FFT bins,
    # max-pool where a row spans several bins (so narrow tonal lines are never skipped)
    rows = np.geomspace(fmin, min(fmax, sr / 2), height)
    edges = np.geomspace(fmin, min(fmax, sr / 2), height + 1)
    idx = np.interp(rows, f, np.arange(f.size))
    lo = np.floor(idx).astype(int)
    hi = np.minimum(lo + 1, f.size - 1)
    fr = (idx - lo)[:, None]
    img = norm[lo] * (1 - fr) + norm[hi] * fr
    b_lo = np.searchsorted(f, edges[:-1])
    b_hi = np.searchsorted(f, edges[1:])
    for r in np.nonzero(b_hi - b_lo > 1)[0]:
        img[r] = norm[b_lo[r] : b_hi[r]].max(axis=0)
    # resample columns to width
    cols = np.linspace(0, img.shape[1] - 1, width)
    ci = np.floor(cols).astype(int)
    img = img[:, ci]
    rgb = _colormap(img[::-1])
    return Image.fromarray(rgb, "RGB"), rows


def _waveform_image(x: np.ndarray, sr: int, width: int, height: int, duration: float | None):
    from PIL import Image, ImageDraw

    m = to_mono(x)
    if duration is not None:
        n = int(duration * sr)
        m = np.concatenate([m, np.zeros(max(0, n - m.size))])[:n]
    img = Image.new("RGB", (width, height), (18, 18, 24))
    d = ImageDraw.Draw(img)
    if m.size == 0:
        return img
    edges = np.linspace(0, m.size, width + 1).astype(int)
    mid = height / 2
    for i in range(width):
        seg = m[edges[i] : max(edges[i] + 1, edges[i + 1])]
        lo, hi = float(seg.min()), float(seg.max())
        d.line([(i, mid - hi * mid * 0.95), (i, mid - lo * mid * 0.95)], fill=(120, 200, 255))
    return img


def render_panels(items, path: str, sr: int = SR, width: int = 900, spec_h: int = 240, wave_h: int = 50,
                  duration: float | None = None, columns: int = 1, title: str | None = None) -> None:
    """Render ``[(label, signal), ...]`` as stacked waveform+spectrogram panels into a PNG."""
    from PIL import Image, ImageDraw, ImageFont

    try:
        font = ImageFont.load_default(size=15)
        small = ImageFont.load_default(size=11)
        big = ImageFont.load_default(size=20)
    except TypeError:  # very old Pillow
        font = small = big = ImageFont.load_default()
    label_h = 22
    axis_w = 46
    panel_h = label_h + wave_h + spec_h + 18
    rows = int(np.ceil(len(items) / columns))
    head = 34 if title else 0
    W = columns * (width + axis_w + 10) + 10
    H = head + rows * panel_h + 10
    canvas = Image.new("RGB", (W, H), (10, 10, 14))
    d = ImageDraw.Draw(canvas)
    if title:
        d.text((12, 6), title, fill=(240, 240, 240), font=big)
    for k, (label, sig) in enumerate(items):
        r, c = divmod(k, columns)
        x0 = 10 + c * (width + axis_w + 10)
        y0 = head + r * panel_h
        dur = duration if duration is not None else sig.shape[0] / sr
        feats = spectral_features(sig, sr)
        info = f"{label}   {sig.shape[0] / sr:.2f}s   peak {peak_db(sig):.1f} dBFS   centroid {feats.get('centroidHz', 0):.0f} Hz"
        d.text((x0, y0 + 3), info, fill=(235, 235, 235), font=font)
        wave = _waveform_image(sig, sr, width, wave_h, dur)
        canvas.paste(wave, (x0 + axis_w, y0 + label_h))
        spec, freqs = spectrogram_image(sig, sr, width, spec_h, duration=dur)
        sy = y0 + label_h + wave_h
        canvas.paste(spec, (x0 + axis_w, sy))
        for fz in (50, 100, 200, 500, 1000, 2000, 5000, 10000):
            if fz < freqs[0] or fz > freqs[-1]:
                continue
            frac = np.log(fz / freqs[0]) / np.log(freqs[-1] / freqs[0])
            yy = sy + spec_h - 1 - int(frac * (spec_h - 1))
            d.line([(x0 + axis_w - 5, yy), (x0 + axis_w, yy)], fill=(200, 200, 200))
            d.text((x0, yy - 6), f"{fz // 1000}k" if fz >= 1000 else str(fz), fill=(200, 200, 200), font=small)
        ticks = np.arange(0, dur + 1e-9, 0.5 if dur <= 4 else (2.0 if dur <= 12 else 5.0))
        for tt in ticks:
            xx = x0 + axis_w + int(tt / max(dur, 1e-9) * (width - 1))
            d.line([(xx, sy + spec_h), (xx, sy + spec_h + 4)], fill=(200, 200, 200))
            d.text((xx + 2, sy + spec_h + 2), f"{tt:g}s", fill=(160, 160, 160), font=small)
    canvas.save(path)


# --------------------------------------------------------------------------- music analysis
_KK_MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
_KK_MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
PC_NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]


def chroma(x: np.ndarray, sr: int = SR, fmin: float = 55.0, fmax: float = 2000.0, nperseg: int | None = None) -> np.ndarray:
    """Pitch-class profile (12,) of a signal: STFT energy folded onto equal-tempered pitch classes.

    Each bin is weighted by its distance from the nearest semitone centre (1 at the centre, 0 at
    +-0.5 semitone), and the FFT is long enough that semitones at ``fmin`` span several bins, so low
    notes are not smeared into their neighbours. Frames are log-compressed so sustained bass does
    not dominate."""
    m = to_mono(x)
    if nperseg is None:
        # >= 3 bins per semitone at fmin (semitone width ~ 0.0595 * f)
        nperseg = int(2 ** np.ceil(np.log2(3.0 * sr / (0.0595 * fmin))))
        nperseg = min(nperseg, 1 << 16, max(1024, 1 << int(np.floor(np.log2(max(m.size, 1024))))))
    f, _, Z = stft(m, sr, nperseg=nperseg, noverlap=nperseg * 3 // 4)
    p = np.abs(Z) ** 2
    sel = (f >= fmin) & (f <= fmax)
    midi = 69 + 12 * np.log2(f[sel] / 440.0)
    near = np.round(midi)
    w = np.clip(1.0 - 2.0 * np.abs(midi - near), 0.0, 1.0)
    pcs = np.mod(near, 12).astype(int)
    frames = np.log1p(p[sel] / (np.max(p[sel]) * 1e-4 + 1e-30)) * w[:, None]
    out = np.zeros(12)
    for k in range(12):
        out[k] = frames[pcs == k].sum()
    return out / max(out.sum(), 1e-12)


def estimate_key(ch: np.ndarray) -> dict:
    """Krumhansl-Kessler key estimate from a chroma vector: best tonic/mode and all scores."""
    scores = {}
    for t in range(12):
        for mode, prof in (("major", _KK_MAJOR), ("minor", _KK_MINOR)):
            scores[f"{PC_NAMES[t]} {mode}"] = float(np.corrcoef(ch, np.roll(prof, t))[0, 1])
    best = max(scores, key=scores.get)
    return {"key": best, "r": round(scores[best], 3), "scores": {k: round(v, 3) for k, v in scores.items()}}


def onset_envelope(x: np.ndarray, sr: int = SR, hop: int = 240, nperseg: int = 1024) -> np.ndarray:
    """Spectral-flux onset strength (half-wave rectified log-magnitude increase), one value per hop."""
    m = to_mono(x)
    _, _, Z = stft(m, sr, nperseg=nperseg, noverlap=nperseg - hop, boundary=None, padded=False)
    mag = np.log1p(1000.0 * np.abs(Z))
    flux = np.maximum(np.diff(mag, axis=1), 0.0).sum(axis=0)
    flux = np.concatenate([[0.0], flux])
    flux -= np.convolve(flux, np.ones(41) / 41, mode="same")
    return np.maximum(flux, 0.0)


def estimate_tempo(env: np.ndarray, sr: int = SR, hop: int = 240, lo: float = 50.0, hi: float = 200.0) -> float:
    """Tempo (BPM) from the autocorrelation of an onset envelope."""
    e = env - env.mean()
    ac = np.correlate(e, e, mode="full")[e.size - 1 :]
    lags = np.arange(ac.size) * hop / sr
    sel = (lags >= 60.0 / hi) & (lags <= 60.0 / lo)
    i = np.argmax(ac[sel])
    return float(60.0 / lags[sel][i])


def grid_phase(env: np.ndarray, period_samples: float, hop: int = 240, nperseg: int = 1024) -> tuple[float, float]:
    """Phase (in samples, 0..period) at which onset energy concentrates when folded on a beat grid
    of ``period_samples``, plus a concentration score (0 = uniform, 1 = all onsets in one bin).
    Envelope value ``i`` (from :func:`onset_envelope`) is timed at the centre between frames
    ``i-1`` and ``i``: ``i*hop + nperseg/2 - hop/2``."""
    pos = (np.arange(env.size) * hop + nperseg / 2 - hop / 2) % period_samples
    bins = max(8, int(round(period_samples / hop)))
    hist = np.bincount(np.minimum((pos / period_samples * bins).astype(int), bins - 1), weights=env, minlength=bins)
    k = int(np.argmax(hist))
    conc = float(hist[k] / max(hist.sum(), 1e-12))
    return (k + 0.5) * period_samples / bins, conc


def pitchgram_image(x: np.ndarray, sr: int = SR, width: int = 900, lo_midi: int = 36, hi_midi: int = 96,
                    row_h: int = 4, db_range: float = 60.0, duration: float | None = None):
    """Spectrogram on a semitone axis (one row per MIDI note) for checking melodies and harmony."""
    from PIL import Image

    m = to_mono(x)
    if duration is not None:
        n = int(duration * sr)
        m = np.concatenate([m, np.zeros(max(0, n - m.size))])[:n]
    nper = 8192
    hop = max(64, int(m.size / width))
    f, _, Z = stft(m, sr, nperseg=nper, noverlap=max(0, nper - hop), boundary="zeros")
    mag = np.abs(Z)
    rows = []
    for note in range(hi_midi, lo_midi - 1, -1):
        f_lo = 440.0 * 2 ** ((note - 0.5 - 69) / 12.0)
        f_hi = 440.0 * 2 ** ((note + 0.5 - 69) / 12.0)
        sel = (f >= f_lo) & (f < f_hi)
        if not np.any(sel):
            sel = np.array([np.argmin(np.abs(f - 440.0 * 2 ** ((note - 69) / 12.0)))])
            rows.append(mag[sel].max(axis=0))
        else:
            rows.append(mag[sel].max(axis=0))
    img = 20 * np.log10(np.array(rows) + 1e-9)
    img = (img - (img.max() - db_range)) / db_range
    cols = np.linspace(0, img.shape[1] - 1, width).astype(int)
    img = np.repeat(img[:, cols], row_h, axis=0)
    return Image.fromarray(_colormap(img), "RGB")


def render_pitch_panels(items, path: str, sr: int = SR, width: int = 1100, lo_midi: int = 36, hi_midi: int = 96,
                        row_h: int = 4, title: str | None = None) -> None:
    """``[(label, signal, beats_or_None), ...]`` -> semitone spectrograms with note-name gridlines
    (D and A rows highlighted: the motif's tonic and dominant) and optional beat ticks
    (``beats`` = (first_beat_s, beat_s))."""
    from PIL import Image, ImageDraw, ImageFont

    try:
        font = ImageFont.load_default(size=14)
        small = ImageFont.load_default(size=10)
    except TypeError:
        font = small = ImageFont.load_default()
    names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    rows = hi_midi - lo_midi + 1
    ph = rows * row_h
    axis_w = 40
    head = 30 if title else 0
    panel_h = 22 + ph + 16
    W = width + axis_w + 20
    H = head + panel_h * len(items) + 10
    canvas = Image.new("RGB", (W, H), (10, 10, 14))
    d = ImageDraw.Draw(canvas)
    if title:
        d.text((10, 6), title, fill=(240, 240, 240), font=font)
    for k, (label, sig, beats) in enumerate(items):
        y0 = head + k * panel_h
        dur = sig.shape[0] / sr
        d.text((10, y0 + 3), f"{label}   {dur:.2f}s", fill=(235, 235, 235), font=font)
        img = pitchgram_image(sig, sr, width, lo_midi, hi_midi, row_h)
        sy = y0 + 22
        canvas.paste(img, (axis_w, sy))
        for note in range(lo_midi, hi_midi + 1):
            pc = note % 12
            yy = sy + (hi_midi - note) * row_h + row_h // 2
            if pc in (2, 9):
                d.line([(axis_w - 6, yy), (axis_w - 1, yy)], fill=(255, 210, 120) if pc == 2 else (150, 200, 255))
                d.text((2, yy - 6), f"{names[pc]}{note // 12 - 1}", fill=(255, 210, 120) if pc == 2 else (150, 200, 255),
                       font=small)
        if beats:
            first, beat_s = beats
            t = first
            i = 0
            while t <= dur:
                xx = axis_w + int(t / max(dur, 1e-9) * (width - 1))
                d.line([(xx, sy + ph), (xx, sy + ph + (6 if i % 4 == 0 else 3))], fill=(200, 200, 200))
                t += beat_s
                i += 1
    canvas.save(path)


__all__ = [
    "measure", "spectral_features", "log_mel_profile", "envelope_profile", "spectrogram_image", "render_panels",
    "seam_metrics", "loudness_integrated", "loudness_momentary_max", "chroma", "estimate_key", "onset_envelope",
    "estimate_tempo", "grid_phase", "pitchgram_image", "render_pitch_panels",
]

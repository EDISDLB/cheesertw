"""Audio file I/O via soundfile (OGG Vorbis / WAV) with reproducible OGG bytes.

libsndfile picks a random Ogg bitstream serial number per file, so two renders of the
same audio would differ byte-wise.  :func:`write_ogg` rewrites the serial with a value
derived from the asset key and recomputes the page CRCs, making regenerated assets
byte-identical (clean diffs, cache-friendly uploads).
"""

from __future__ import annotations

import os
import struct

import numpy as np
import soundfile as sf

from .core import SR, seed_of


def _ogg_crc_table() -> list[int]:
    table = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04C11DB7) if (r & 0x80000000) else (r << 1)
        table.append(r & 0xFFFFFFFF)
    return table


_CRC_TABLE = _ogg_crc_table()
_OGG_CHUNK = 32768


def _ogg_crc(data: bytes) -> int:
    crc = 0
    tbl = _CRC_TABLE
    for b in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ tbl[((crc >> 24) & 0xFF) ^ b]
    return crc


def set_ogg_serial(path: str, serial: int) -> None:
    """Rewrite the bitstream serial number of every page and fix the page checksums."""
    with open(path, "rb") as fh:
        data = bytearray(fh.read())
    pos = 0
    serial_bytes = struct.pack("<I", serial & 0xFFFFFFFF)
    while pos < len(data):
        if data[pos : pos + 4] != b"OggS":
            raise ValueError(f"{path}: lost Ogg page sync at byte {pos}")
        nseg = data[pos + 26]
        seg_table = data[pos + 27 : pos + 27 + nseg]
        page_len = 27 + nseg + sum(seg_table)
        data[pos + 14 : pos + 18] = serial_bytes
        data[pos + 22 : pos + 26] = b"\x00\x00\x00\x00"
        crc = _ogg_crc(bytes(data[pos : pos + page_len]))
        data[pos + 22 : pos + 26] = struct.pack("<I", crc)
        pos += page_len
    with open(path, "wb") as fh:
        fh.write(bytes(data))


def write_ogg(path: str, x: np.ndarray, sr: int = SR, quality: float = 0.65, key: str | None = None) -> None:
    """Encode ``x`` (float, mono or stereo) as OGG Vorbis. ``quality`` in [0, 1] (0.65 ~ q6.5)."""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    data = np.asarray(x, dtype=np.float32)
    channels = 1 if data.ndim == 1 else data.shape[1]
    # libsndfile 1.2's Vorbis writer crashes on very large single writes (~>2M frames), so feed
    # the encoder in fixed-size chunks (fixed size keeps the output deterministic).
    with sf.SoundFile(path, "w", sr, channels, format="OGG", subtype="VORBIS",
                      compression_level=float(np.clip(1.0 - quality, 0.0, 1.0))) as fh:
        for start in range(0, data.shape[0], _OGG_CHUNK):
            fh.write(data[start : start + _OGG_CHUNK])
    set_ogg_serial(path, seed_of("ogg-serial", key or os.path.basename(path)) & 0x7FFFFFFF)


def write_wav(path: str, x: np.ndarray, sr: int = SR, subtype: str = "PCM_24") -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    sf.write(path, np.asarray(x, dtype=np.float64), sr, subtype=subtype)


def write_flac(path: str, x: np.ndarray, sr: int = SR) -> None:
    """Lossless 24-bit FLAC (used for intermediate masters)."""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    sf.write(path, np.clip(np.asarray(x, dtype=np.float64), -1.0, 1.0), sr, format="FLAC", subtype="PCM_24")


def read(path: str) -> tuple[np.ndarray, int]:
    data, sr = sf.read(path, dtype="float64", always_2d=False)
    return data, sr


def info(path: str) -> sf._SoundFileInfo:  # type: ignore[name-defined]
    return sf.info(path)

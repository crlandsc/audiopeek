#!/usr/bin/env python3
"""PROTOTYPE: bake waveform envelopes + mel spectrograms for viewer-look.html.

Pass the WAV path as the only argument. The script reads that file as data
and does not play it. The WAV stays outside the repo.
"""

from __future__ import annotations

import base64
import io
import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import soundfile as sf

OUT = Path(__file__).resolve().parent / "viewer-look-data.js"

N_FFT = 2048
HOP = 512
N_MELS = 128
FMIN = 0.0
DB_FLOOR = -80.0
DB_RANGE = 80.0
WAVE_BINS = 1400
SPEC_W = 1100
SPEC_H = 220


def hz_to_mel(f: np.ndarray | float) -> np.ndarray | float:
    return 2595.0 * np.log10(1.0 + np.asarray(f) / 700.0)


def mel_to_hz(m: np.ndarray | float) -> np.ndarray | float:
    return 700.0 * (10.0 ** (np.asarray(m) / 2595.0) - 1.0)


def mel_filterbank(sr: int, n_fft: int, n_mels: int, fmin: float, fmax: float) -> np.ndarray:
    n_freqs = n_fft // 2 + 1
    mels = np.linspace(hz_to_mel(fmin), hz_to_mel(fmax), n_mels + 2)
    hz = mel_to_hz(mels)
    bins = np.floor((n_fft + 1) * hz / sr).astype(int)
    bins = np.clip(bins, 0, n_freqs - 1)
    fb = np.zeros((n_mels, n_freqs), dtype=np.float64)
    for i in range(n_mels):
        left, center, right = bins[i], bins[i + 1], bins[i + 2]
        if center > left:
            fb[i, left:center] = (np.arange(left, center) - left) / (center - left)
        if right > center:
            fb[i, center:right] = (right - np.arange(center, right)) / (right - center)
        fb[i, center] = 1.0
    return fb


def stft_power(y: np.ndarray, n_fft: int, hop: int) -> np.ndarray:
    win = np.hanning(n_fft).astype(np.float64)
    padded = np.pad(y, n_fft // 2, mode="reflect")
    n_frames = 1 + (len(padded) - n_fft) // hop
    frames = np.empty((n_frames, n_fft), dtype=np.float64)
    for i in range(n_frames):
        frames[i] = padded[i * hop : i * hop + n_fft] * win
    spec = np.fft.rfft(frames, axis=-1)
    return np.abs(spec).T ** 2


def envelope(x: np.ndarray, bins: int) -> tuple[list[float], list[float]]:
    edges = np.linspace(0, len(x), bins + 1).astype(int)
    mn = np.zeros(bins, dtype=np.float64)
    mx = np.zeros(bins, dtype=np.float64)
    for i in range(bins):
        sl = x[edges[i] : edges[i + 1]]
        if sl.size:
            mn[i] = float(sl.min())
            mx[i] = float(sl.max())
    return mn.round(5).tolist(), mx.round(5).tolist()


def spec_png(s_db: np.ndarray, cmap: str) -> str:
    buf = io.BytesIO()
    plt.imsave(buf, s_db, cmap=cmap, origin="lower", vmin=DB_FLOOR, vmax=DB_FLOOR + DB_RANGE, format="png")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: build_viewer_look.py PATH.wav", file=sys.stderr)
        raise SystemExit(2)
    src = Path(sys.argv[1])
    y, sr = sf.read(str(src), always_2d=True, dtype="float64")
    n_ch = y.shape[1]
    n = y.shape[0]
    duration = n / sr
    mix = y.mean(axis=1)

    power = stft_power(mix, N_FFT, HOP)
    fb = mel_filterbank(sr, N_FFT, N_MELS, FMIN, sr / 2.0)
    mel = fb @ power
    mel = np.maximum(mel, 1e-12)
    s_db = 10.0 * np.log10(mel)
    s_db = s_db - s_db.max()
    s_db = np.clip(s_db, DB_FLOOR, DB_FLOOR + DB_RANGE)

    waves = {}
    for i, name in enumerate(["L", "R"][:n_ch]):
        mn, mx = envelope(y[:, i], WAVE_BINS)
        waves[name] = {"mn": mn, "mx": mx}

    payload = {
        "file": src.name,
        "format": "WAV",
        "sr": int(sr),
        "channels": int(n_ch),
        "duration": round(float(duration), 5),
        "samples": int(n),
        "bitDepth": 16,
        "analysis": {
            "type": "mel",
            "n_fft": N_FFT,
            "hop": HOP,
            "window": "Hann",
            "n_mels": N_MELS,
            "fmin": FMIN,
            "fmax": int(sr / 2),
            "db": True,
            "dbFloor": DB_FLOOR,
            "dbRange": DB_RANGE,
        },
        "wave": waves,
        "spec": {
            "magma": spec_png(s_db, "magma"),
            "viridis": spec_png(s_db, "viridis"),
            "grey": spec_png(s_db, "gray"),
        },
        "note": "Decoded as data only. No audio is embedded or played.",
    }

    OUT.write_text("window.PROTO = " + json.dumps(payload, separators=(",", ":")) + ";\n", encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")
    print(f"{n_ch}ch {sr} Hz {duration:.3f}s  spec {s_db.shape}")


if __name__ == "__main__":
    main()

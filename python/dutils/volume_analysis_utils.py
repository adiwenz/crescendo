#!/usr/bin/env python3
"""Helpers for checking take-level volume consistency."""

from typing import List, Tuple

import librosa
import numpy as np


def _moving_average(x: np.ndarray, win: int) -> np.ndarray:
    """Apply centered moving average with odd window; returns original if disabled."""
    if win is None or win < 2:
        return x
    win = int(win)
    if win % 2 == 0:
        win += 1
    pad = win // 2
    xp = np.pad(x, (pad, pad), mode="edge")
    kernel = np.ones(win) / float(win)
    return np.convolve(xp, kernel, mode="valid")


def analyze_volume_consistency(
    y: np.ndarray,
    sr: int,
    frame_length: int,
    hop_length: int,
    smoothing_win: int = 5,
    tolerance_db: float = 3.0,
) -> Tuple[dict, List[dict]]:
    """
    Compute RMS over time, smooth it, and summarize how consistent volume is.
    Returns (summary, frames).
    """
    rms = librosa.feature.rms(y=y, frame_length=frame_length, hop_length=hop_length, center=True)[0]
    rms_db = librosa.amplitude_to_db(rms, ref=np.max)
    times = librosa.frames_to_time(np.arange(len(rms_db)), sr=sr, hop_length=hop_length)
    rms_db_smooth = _moving_average(rms_db, smoothing_win)

    mean_db = float(np.mean(rms_db))
    std_db = float(np.std(rms_db))
    deviation = np.abs(rms_db - mean_db)
    pct_within = float(np.mean(deviation <= tolerance_db) * 100.0)

    summary = {
        "mean_db": mean_db,
        "std_db": std_db,
        "pct_within_tolerance": pct_within,
        "tolerance_db": tolerance_db,
    }
    frames = [
        {
            "time": float(t),
            "rms_db": float(v),
            "rms_db_smooth": float(s),
        }
        for t, v, s in zip(times, rms_db, rms_db_smooth)
    ]
    return summary, frames

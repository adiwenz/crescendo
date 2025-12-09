#!/usr/bin/env python3
"""Helpers for analyzing pitch smoothness / tone stability."""

from typing import Iterable, List, Tuple

import librosa
import numpy as np

from vocal_analyzer.analysis_utils import hz_to_midi_safe


def _nan_mean_window(x: np.ndarray, center: int, half_win: int) -> float:
    lo = max(0, center - half_win)
    hi = min(len(x), center + half_win + 1)
    window = x[lo:hi]
    if not window.size:
        return np.nan
    valid = window[~np.isnan(window)]
    return float(np.mean(valid)) if valid.size else np.nan


def analyze_pitch_smoothness(
    f0_hz: np.ndarray,
    times: np.ndarray,
    smoothing_win: int = 5,
    tolerance_cents_per_step: float = 20.0,
) -> Tuple[dict, List[dict]]:
    """
    Compute frame-to-frame pitch deltas (cents) as a proxy for smoothness.
    Lower deltas = smoother tone.
    Returns (summary, frames).
    """
    midi = hz_to_midi_safe(f0_hz)
    half_win = max(0, int(smoothing_win // 2))
    smoothed = np.array(
        [_nan_mean_window(midi, i, half_win) for i in range(len(midi))],
        dtype=float,
    )

    deltas = np.full_like(smoothed, np.nan, dtype=float)
    for i in range(1, len(smoothed)):
        if np.isnan(smoothed[i]) or np.isnan(smoothed[i - 1]):
            continue
        deltas[i] = (smoothed[i] - smoothed[i - 1]) * 100.0  # semitone -> cents

    valid = ~np.isnan(deltas)
    if not np.any(valid):
        summary = {
            "mean_abs_delta_cents": None,
            "median_abs_delta_cents": None,
            "pct_within_tolerance": None,
            "tolerance_cents_per_step": tolerance_cents_per_step,
            "valid_steps": 0,
        }
    else:
        abs_d = np.abs(deltas[valid])
        summary = {
            "mean_abs_delta_cents": float(np.mean(abs_d)),
            "median_abs_delta_cents": float(np.median(abs_d)),
            "pct_within_tolerance": float(np.mean(abs_d <= tolerance_cents_per_step) * 100.0),
            "tolerance_cents_per_step": tolerance_cents_per_step,
            "valid_steps": int(len(abs_d)),
        }

    frames = [
        {
            "time": float(t),
            "smoothed_midi": None if np.isnan(sm) else float(sm),
            "delta_cents": None if np.isnan(dc) else float(dc),
        }
        for t, sm, dc in zip(times, smoothed, deltas)
    ]
    return summary, frames


def analyze_spectral_tone(
    y: np.ndarray,
    sr: int,
    frame_length: int,
    hop_length: int,
) -> Tuple[dict, List[dict]]:
    """Compute spectral centroid and flatness over time."""
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr, n_fft=frame_length, hop_length=hop_length)[0]
    flatness = librosa.feature.spectral_flatness(y=y, n_fft=frame_length, hop_length=hop_length)[0]
    times = librosa.frames_to_time(np.arange(len(centroid)), sr=sr, hop_length=hop_length)
    summary = {
        "mean_centroid_hz": float(np.mean(centroid)),
        "median_centroid_hz": float(np.median(centroid)),
        "mean_flatness": float(np.mean(flatness)),
        "median_flatness": float(np.median(flatness)),
    }
    frames = [
        {
            "time": float(t),
            "centroid_hz": float(c),
            "flatness": float(f),
        }
        for t, c, f in zip(times, centroid, flatness)
    ]
    return summary, frames


def analyze_jitter_shimmer(
    f0_hz: np.ndarray,
    rms: np.ndarray,
) -> Tuple[dict, List[dict]]:
    """
    Lightweight jitter/shimmer proxies.
    Jitter: relative change in pitch; Shimmer: relative change in amplitude (RMS).
    """
    jitter = np.full_like(f0_hz, np.nan, dtype=float)
    shimmer = np.full_like(rms, np.nan, dtype=float)
    for i in range(1, len(f0_hz)):
        if f0_hz[i] > 0 and f0_hz[i - 1] > 0:
            jitter[i] = abs(f0_hz[i] - f0_hz[i - 1]) / f0_hz[i - 1]
        if rms[i] > 0 and rms[i - 1] > 0:
            shimmer[i] = abs(rms[i] - rms[i - 1]) / rms[i - 1]

    def _summ(x):
        valid = x[~np.isnan(x)]
        if not valid.size:
            return {"mean": None, "median": None}
        return {"mean": float(np.mean(valid)), "median": float(np.median(valid))}

    summary = {
        "jitter": _summ(jitter),
        "shimmer": _summ(shimmer),
    }
    frames = [
        {
            "jitter": None if np.isnan(j) else float(j),
            "shimmer": None if np.isnan(s) else float(s),
        }
        for j, s in zip(jitter, shimmer)
    ]
    return summary, frames


def analyze_tone(
    y: np.ndarray,
    sr: int,
    f0_hz: np.ndarray,
    times: np.ndarray,
    frame_length: int,
    hop_length: int,
    metrics: Iterable[str],
    smooth_win: int = 5,
    smooth_tolerance_cents: float = 20.0,
) -> Tuple[dict, List[dict]]:
    """
    Compute requested tone metrics. metrics is an iterable of:
    - "smoothness": pitch smoothness (delta cents)
    - "spectral": centroid/flatness
    - "jitter": jitter/shimmer proxies
    Returns (summary_dict, frames_list) merged across metrics.
    """
    summary: dict = {}
    frames: List[dict] = [{"time": float(t)} for t in times]

    metric_set = {m.strip().lower() for m in metrics}

    if "smoothness" in metric_set:
        sm_summary, sm_frames = analyze_pitch_smoothness(f0_hz, times, smooth_win, smooth_tolerance_cents)
        summary["smoothness"] = sm_summary
        for f, sm in zip(frames, sm_frames):
            f.update({k: sm[k] for k in ("smoothed_midi", "delta_cents")})

    if "spectral" in metric_set:
        spec_summary, spec_frames = analyze_spectral_tone(y, sr, frame_length, hop_length)
        summary["spectral"] = spec_summary
        # align by index; assume same length or truncate
        for f, sf in zip(frames, spec_frames):
            f.update({k: sf[k] for k in ("centroid_hz", "flatness")})

    if "jitter" in metric_set:
        rms = librosa.feature.rms(y=y, frame_length=frame_length, hop_length=hop_length, center=True)[0]
        jit_summary, jit_frames = analyze_jitter_shimmer(f0_hz, rms)
        summary["jitter"] = jit_summary["jitter"]
        summary["shimmer"] = jit_summary["shimmer"]
        for f, jf in zip(frames, jit_frames):
            f.update(jf)

    return summary, frames

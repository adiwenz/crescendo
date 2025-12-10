#!/usr/bin/env python3
"""Helpers for analyzing pitch smoothness / tone stability."""

from typing import Iterable, List, Tuple, Optional

import librosa
import numpy as np
from vocal_analyzer.analysis_utils import hz_to_midi_safe

EPS = 1e-10


def _compute_spectral_tilt(S: np.ndarray, freqs: np.ndarray, split_hz: float = 2000.0) -> np.ndarray:
    """
    Compute spectral tilt per frame as the ratio (in dB) of low- vs high-frequency energy.
    Positive values mean more low-frequency energy (warmer/darker),
    negative values mean more high-frequency energy (brighter/edgier).
    """
    if S.size == 0:
        return np.array([])

    power = S ** 2
    low_mask = freqs < split_hz
    high_mask = freqs >= split_hz

    # Avoid degenerate masks
    if not np.any(low_mask) or not np.any(high_mask):
        return np.zeros(S.shape[1], dtype=float)

    low_energy = np.sum(power[low_mask, :], axis=0) + EPS
    high_energy = np.sum(power[high_mask, :], axis=0) + EPS

    tilt_db = 10.0 * np.log10(low_energy / high_energy)
    return tilt_db


def _compute_hnr(D: np.ndarray) -> np.ndarray:
    """
    Approximate harmonic-to-noise ratio (HNR) per frame using HPSS on the STFT.
    This is a rough proxy: higher HNR = clearer, more harmonic tone; lower HNR = noisier/breathier.
    """
    if D.size == 0:
        return np.array([])

    # Harmonic-percussive separation
    try:
        H, P = librosa.effects.hpss(D)
    except Exception:
        # Fallback: no separation possible
        S = np.abs(D)
        power = S ** 2
        total_energy = np.sum(power, axis=0) + EPS
        # If we have no noise estimate, treat noise as a fixed small fraction
        noise_energy = 0.1 * total_energy
        return 10.0 * np.log10(total_energy / noise_energy)

    S = np.abs(D)
    H_mag = np.abs(H)

    harmonic_power = H_mag ** 2
    total_power = S ** 2
    noise_power = np.clip(total_power - harmonic_power, a_min=0.0, a_max=None)

    harmonic_energy = np.sum(harmonic_power, axis=0) + EPS
    noise_energy = np.sum(noise_power, axis=0) + EPS

    hnr_db = 10.0 * np.log10(harmonic_energy / noise_energy)
    return hnr_db


def _compute_h1h2(S: np.ndarray, freqs: np.ndarray, f0: np.ndarray) -> np.ndarray:
    """
    Approximate H1–H2 (in dB) per frame.
    Positive values ~ breathier phonation, lower/negative ~ pressed.
    This implementation looks up magnitudes at f0 and 2*f0 bins.
    """
    n_freqs, n_frames = S.shape
    h1h2 = np.full(n_frames, np.nan, dtype=float)

    for i in range(n_frames):
        f0_i = f0[i] if i < len(f0) else np.nan
        if not np.isfinite(f0_i) or f0_i <= 0:
            continue

        f1 = f0_i
        f2 = 2.0 * f0_i

        # Find closest bins to f0 and 2*f0
        idx1 = int(np.argmin(np.abs(freqs - f1)))
        idx2 = int(np.argmin(np.abs(freqs - f2)))

        if idx1 < 0 or idx1 >= n_freqs or idx2 < 0 or idx2 >= n_freqs:
            continue

        mag1 = S[idx1, i]
        mag2 = S[idx2, i]

        h1h2[i] = 20.0 * np.log10((mag1 + EPS) / (mag2 + EPS))

    return h1h2


def _scale_to_1_10(value: float, vmin: float, vmax: float, invert: bool = False) -> Optional[float]:
    """
    Linearly map a raw value into a 1–10 score.
    Values outside [vmin, vmax] are clamped.
    If invert=True, low raw values map to high scores.
    """
    if value is None or not np.isfinite(value):
        return None
    if vmin == vmax:
        return None
    v = float(value)
    if v < vmin:
        v = vmin
    elif v > vmax:
        v = vmax
    frac = (v - vmin) / (vmax - vmin)
    if invert:
        frac = 1.0 - frac
    return 1.0 + 9.0 * frac


def _safe_float(x) -> Optional[float]:
    try:
        if x is None:
            return None
        xf = float(x)
        if not np.isfinite(xf):
            return None
        return xf
    except Exception:
        return None


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
    f0_hz: Optional[np.ndarray] = None,
) -> Tuple[dict, List[dict]]:
    """
    Compute spectral centroid, flatness, spectral tilt, HNR, and (optionally) H1–H2 over time.
    If f0_hz is provided, H1–H2 is estimated using the first two harmonics.
    """
    # Basic spectral features
    centroid = librosa.feature.spectral_centroid(
        y=y, sr=sr, n_fft=frame_length, hop_length=hop_length
    )[0]
    flatness = librosa.feature.spectral_flatness(
        y=y, n_fft=frame_length, hop_length=hop_length
    )[0]
    times = librosa.frames_to_time(
        np.arange(len(centroid)), sr=sr, hop_length=hop_length
    )

    # STFT for harmonic / noise / tilt measurements
    D = librosa.stft(y, n_fft=frame_length, hop_length=hop_length, center=True)
    S = np.abs(D)
    freqs = librosa.fft_frequencies(sr=sr, n_fft=frame_length)

    spectral_tilt = _compute_spectral_tilt(S, freqs)
    hnr = _compute_hnr(D)

    # Align optional f0 track to STFT frames if provided
    if f0_hz is not None:
        f0_arr = np.asarray(f0_hz, dtype=float)
        n_frames = S.shape[1]
        if len(f0_arr) > n_frames:
            f0_arr = f0_arr[:n_frames]
        elif len(f0_arr) < n_frames:
            pad_width = n_frames - len(f0_arr)
            f0_arr = np.pad(f0_arr, (0, pad_width), mode="edge")
        h1h2 = _compute_h1h2(S, freqs, f0_arr)
    else:
        h1h2 = np.full(S.shape[1], np.nan, dtype=float)

    # Helper stats ignoring NaNs
    def _nanmean_safe(arr: np.ndarray) -> float:
        if arr is None or len(arr) == 0:
            return float("nan")
        if not np.any(np.isfinite(arr)):
            return float("nan")
        return float(np.nanmean(arr))

    def _nanmedian_safe(arr: np.ndarray) -> float:
        if arr is None or len(arr) == 0:
            return float("nan")
        if not np.any(np.isfinite(arr)):
            return float("nan")
        return float(np.nanmedian(arr))

    def _nanstd_safe(arr: np.ndarray) -> float:
        if arr is None or len(arr) == 0:
            return float("nan")
        if not np.any(np.isfinite(arr)):
            return float("nan")
        return float(np.nanstd(arr))

    summary = {
        "mean_centroid_hz": float(np.mean(centroid)),
        "median_centroid_hz": float(np.median(centroid)),
        "mean_flatness": float(np.mean(flatness)),
        "median_flatness": float(np.median(flatness)),
        # New tone-related features
        "spectral_tilt_mean": _nanmean_safe(spectral_tilt),
        "spectral_tilt_median": _nanmedian_safe(spectral_tilt),
        "spectral_tilt_std": _nanstd_safe(spectral_tilt),
        "hnr_mean": _nanmean_safe(hnr),
        "hnr_median": _nanmedian_safe(hnr),
        "hnr_std": _nanstd_safe(hnr),
        "h1h2_mean": _nanmean_safe(h1h2),
        "h1h2_median": _nanmedian_safe(h1h2),
        "h1h2_std": _nanstd_safe(h1h2),
    }

    # Derive simple 1–10 categorical scores from spectral metrics.
    mean_centroid = _safe_float(summary["mean_centroid_hz"])
    mean_flatness = _safe_float(summary["mean_flatness"])
    mean_tilt = _safe_float(summary["spectral_tilt_mean"])
    mean_hnr = _safe_float(summary["hnr_mean"])
    mean_h1h2 = _safe_float(summary["h1h2_mean"])

    # Heuristic ranges (can be tuned):
    # - Centroid: 1000–5000 Hz (dark to very bright)
    # - Flatness: 0.01–0.5 (pitched to noise-like)
    # - Tilt: +15 dB (very warm) to -15 dB (very bright)
    # - HNR: 0–30 dB (noisy to very clear)
    # - H1–H2: -5 dB (pressed) to +15 dB (breathy)
    brightness_score = _scale_to_1_10(mean_centroid, 1000.0, 5000.0, invert=False)
    noisiness_score = _scale_to_1_10(mean_flatness, 0.01, 0.5, invert=False)
    tilt_score = _scale_to_1_10(mean_tilt, -15.0, 15.0, invert=True)  # 1=warm, 10=bright
    clarity_score = _scale_to_1_10(mean_hnr, 0.0, 30.0, invert=False)
    breathiness_score = _scale_to_1_10(mean_h1h2, -5.0, 15.0, invert=False)  # 1=pressed, 10=breathy

    summary["categories"] = {
        "brightness": {
            "score": brightness_score,
            "source": "mean_centroid_hz",
            "description": "Higher = brighter tone (higher spectral centroid).",
        },
        "noisiness": {
            "score": noisiness_score,
            "source": "mean_flatness",
            "description": "Higher = more noise-like spectrum (less purely pitched).",
        },
        "tilt_warm_to_bright": {
            "score": tilt_score,
            "source": "spectral_tilt_mean",
            "description": "1 = very warm (more low-frequency energy), 10 = very bright.",
        },
        "clarity": {
            "score": clarity_score,
            "source": "hnr_mean",
            "description": "Higher = clearer, more harmonic tone (higher HNR).",
        },
        "breathiness_to_pressed": {
            "score": breathiness_score,
            "source": "h1h2_mean",
            "description": "1 = more pressed, 10 = more breathy (via H1–H2).",
        },
    }

    # Align per-frame arrays to the centroid/flatness frame count for output
    n_out = len(centroid)

    def _align(arr: np.ndarray) -> np.ndarray:
        if len(arr) > n_out:
            return arr[:n_out]
        if len(arr) < n_out:
            pad_width = n_out - len(arr)
            return np.pad(arr, (0, pad_width), mode="edge")
        return arr

    spectral_tilt = _align(spectral_tilt)
    hnr = _align(hnr)
    h1h2 = _align(h1h2)

    frames = [
        {
            "time": float(t),
            "centroid_hz": float(c),
            "flatness": float(f),
            "spectral_tilt": float(st) if np.isfinite(st) else None,
            "hnr": float(hn) if np.isfinite(hn) else None,
            "h1h2": float(h12) if np.isfinite(h12) else None,
        }
        for t, c, f, st, hn, h12 in zip(times, centroid, flatness, spectral_tilt, hnr, h1h2)
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
        spec_summary, spec_frames = analyze_spectral_tone(
            y, sr, frame_length, hop_length, f0_hz=f0_hz
        )
        summary["spectral"] = spec_summary
        # align by index; assume same length or truncate
        for f, sf in zip(frames, spec_frames):
            f.update(
                {
                    k: sf.get(k)
                    for k in (
                        "centroid_hz",
                        "flatness",
                        "spectral_tilt",
                        "hnr",
                        "h1h2",
                    )
                }
            )

    if "jitter" in metric_set:
        rms = librosa.feature.rms(y=y, frame_length=frame_length, hop_length=hop_length, center=True)[0]
        jit_summary, jit_frames = analyze_jitter_shimmer(f0_hz, rms)
        summary["jitter"] = jit_summary["jitter"]
        summary["shimmer"] = jit_summary["shimmer"]
        for f, jf in zip(frames, jit_frames):
            f.update(jf)

    return summary, frames

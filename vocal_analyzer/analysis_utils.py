#!/usr/bin/env python3
"""Shared helpers for comparing vocal and reference pitch tracks."""

from pathlib import Path
from typing import Optional, Tuple

import librosa
import numpy as np
import pretty_midi


def hz_to_midi_safe(f):
    f = np.asarray(f)
    midi = np.full_like(f, np.nan, dtype=float)
    mask = f > 0
    midi[mask] = 69 + 12 * np.log2(f[mask] / 440.0)
    return midi


def cents_error(vocal_hz, ref_hz):
    vocal_hz = np.asarray(vocal_hz)
    ref_hz = np.asarray(ref_hz)
    err = np.full_like(vocal_hz, np.nan, dtype=float)
    mask = (vocal_hz > 0) & (ref_hz > 0)
    err[mask] = 1200 * np.log2(vocal_hz[mask] / ref_hz[mask])
    return err


def align_arrays(a, b):
    n = min(len(a), len(b))
    return a[:n], b[:n]


def summarize_errors(cents, frame_duration, max_abs=None, ignore_short_ms=None):
    valid = ~np.isnan(cents)
    if max_abs is not None and max_abs > 0:
        abs_ce = np.abs(cents)
        outliers = abs_ce > max_abs
        if ignore_short_ms and ignore_short_ms > 0 and frame_duration > 0:
            threshold_frames = max(1, int(ignore_short_ms / 1000.0 / frame_duration))
            i = 0
            while i < len(outliers):
                if not outliers[i]:
                    i += 1
                    continue
                start = i
                while i < len(outliers) and outliers[i]:
                    i += 1
                end = i  # exclusive
                seg_len = end - start
                if seg_len < threshold_frames:
                    valid[start:end] = False
            # keep longer outliers counted
        else:
            valid = valid & (abs_ce <= max_abs)
    if not np.any(valid):
        return {
            "mean_abs_cents": None,
            "pct_within_25": None,
            "pct_within_50": None,
            "pct_within_100": None,
            "valid_frames": 0,
        }
    ce = cents[valid]
    return {
        "mean_abs_cents": float(np.mean(np.abs(ce))),
        "pct_within_25": float(np.mean(np.abs(ce) <= 25) * 100.0),
        "pct_within_50": float(np.mean(np.abs(ce) <= 50) * 100.0),
        "pct_within_100": float(np.mean(np.abs(ce) <= 100) * 100.0),
        "valid_frames": int(len(ce)),
    }


def trim_audio(y, sr, trim_start=0.0, trim_end=0.0):
    """Trim leading/trailing seconds; non-destructive if values are 0 or negative."""
    n = len(y)
    start_samp = int(max(0.0, trim_start) * sr)
    end_samp = n - int(max(0.0, trim_end) * sr)
    end_samp = max(start_samp, end_samp)
    return y[start_samp:end_samp]


def gate_frames(f0, rms, rms_gate_ratio=0.02, jump_gate_cents=200.0):
    """Return a mask of frames to keep based on RMS and jump gating."""
    keep = np.ones_like(f0, dtype=bool)
    if rms is not None and rms_gate_ratio and rms_gate_ratio > 0:
        max_rms = np.max(rms) if rms.size else 0
        if max_rms > 0:
            keep &= rms >= (rms_gate_ratio * max_rms)
    prev = None
    for i, v in enumerate(f0):
        if np.isnan(v) or v <= 0:
            keep[i] = False
            continue
        if prev is not None and np.isfinite(prev) and jump_gate_cents and jump_gate_cents > 0:
            jump = 1200 * np.log2(v / prev)
            if abs(jump) > jump_gate_cents:
                keep[i] = False
                continue
        prev = v
    return keep


def none_if_nan(x):
    try:
        return None if np.isnan(x) else float(x)
    except Exception:
        return float(x) if x is not None else None


def load_audio_pair(
    vocal_path: Path,
    reference_path: Optional[Path] = None,
    alt_ref_dir: Optional[Path] = None,
) -> Tuple[np.ndarray, int, Optional[np.ndarray], int, Optional[Path]]:
    """Load vocal (required) and optional reference. Returns waveforms, sample rates, and resolved ref path."""
    vocal_y, vocal_sr = librosa.load(str(vocal_path), sr=None, mono=True)
    ref_y = None
    ref_sr = vocal_sr
    ref_resolved = None
    if reference_path:
        ref_path = Path(reference_path)
        if not ref_path.exists():
            alt = (alt_ref_dir / ref_path.name) if alt_ref_dir else None
            if alt is None or not alt.exists():
                raise FileNotFoundError(f"Reference not found: {reference_path}")
            ref_path = alt
        ref_resolved = ref_path
        ref_y, ref_sr = librosa.load(str(ref_path), sr=None, mono=True)
        if ref_sr != vocal_sr:
            raise ValueError(f"Sample rate mismatch (vocal {vocal_sr}, reference {ref_sr}); please resample.")
    return vocal_y, vocal_sr, ref_y, ref_sr, ref_resolved


def compute_similarity(
    vocal_y,
    vocal_sr,
    vocal_f0_raw,
    vocal_times,
    ref_f0,
    ref_times,
    frame_length,
    hop_length,
    rms_gate_ratio=0.0,
    jump_gate_cents=0.0,
    score_max_abs_cents=0.0,
    ignore_short_outliers_ms=0.0,
):
    """
    Compute vocal vs reference similarity summary and per-frame data.
    Returns (summary, frames).
    """
    vocal_f0, ref_f0 = align_arrays(vocal_f0_raw, ref_f0)
    vocal_times, ref_times = align_arrays(vocal_times, ref_times)
    ref_midi_nearest = np.round(hz_to_midi_safe(ref_f0))
    ref_target_hz = pretty_midi.note_number_to_hz(ref_midi_nearest)
    vocal_rms = librosa.feature.rms(y=vocal_y, frame_length=frame_length, hop_length=hop_length, center=True)[0]
    keep_mask = gate_frames(
        vocal_f0,
        vocal_rms,
        rms_gate_ratio=rms_gate_ratio,
        jump_gate_cents=jump_gate_cents,
    )
    vocal_f0 = np.where(keep_mask, vocal_f0, np.nan)
    ce = cents_error(vocal_f0, ref_target_hz)
    frame_duration = hop_length / float(vocal_sr)
    summary = summarize_errors(
        ce,
        frame_duration=frame_duration,
        max_abs=score_max_abs_cents if score_max_abs_cents > 0 else None,
        ignore_short_ms=ignore_short_outliers_ms,
    )
    frames = []
    for i, (t, vh, rh) in enumerate(zip(vocal_times, vocal_f0, ref_target_hz)):
        ref_midi_val = ref_midi_nearest[i] if i < len(ref_midi_nearest) else np.nan
        frames.append(
            {
                "time": float(t),
                "vocal_hz": none_if_nan(vh),
                "vocal_midi": none_if_nan(hz_to_midi_safe(vh)),
                "ref_hz": none_if_nan(rh),
                "ref_midi": int(ref_midi_val) if not np.isnan(ref_midi_val) else None,
                "cents_error": none_if_nan(ce[i]),
            }
        )
    return summary, frames

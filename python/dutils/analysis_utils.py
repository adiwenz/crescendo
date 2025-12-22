#!/usr/bin/env python3
"""Shared helpers for comparing vocal and reference pitch tracks."""

from pathlib import Path
from typing import Optional, Tuple

import librosa
import numpy as np
import pretty_midi


def hz_to_midi_safe(f):
    """Convert Hz array to MIDI numbers; returns NaN for non-positive inputs."""
    f = np.asarray(f)
    midi = np.full_like(f, np.nan, dtype=float)
    mask = f > 0
    midi[mask] = 69 + 12 * np.log2(f[mask] / 440.0)
    return midi


def cents_error(vocal_hz, ref_hz):
    """Compute signed cents error between aligned vocal and reference Hz arrays."""
    vocal_hz = np.asarray(vocal_hz)
    ref_hz = np.asarray(ref_hz)
    err = np.full_like(vocal_hz, np.nan, dtype=float)
    mask = (vocal_hz > 0) & (ref_hz > 0)
    err[mask] = 1200 * np.log2(vocal_hz[mask] / ref_hz[mask])
    return err


def align_arrays(a, b):
    """Trim both arrays to the length of the shorter one."""
    n = min(len(a), len(b))
    return a[:n], b[:n]


def summarize_errors(cents, frame_duration, max_abs=None, ignore_short_ms=None):
    """Summarize cents error array with thresholds and optional outlier gating."""
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
    """Convert NaN to None while preserving floats; handles non-numeric gracefully."""
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
    max_delay_ms: float = 0.0,
    penalize_late: bool = False,
) -> Tuple[dict, list, dict]:
    """
    Compute vocal vs reference similarity summary and per-frame data.
    Returns (summary, frames, offset_info).
    """
    vocal_rms = librosa.feature.rms(y=vocal_y, frame_length=frame_length, hop_length=hop_length, center=True)[0]
    keep_mask = gate_frames(
        vocal_f0_raw,
        vocal_rms,
        rms_gate_ratio=rms_gate_ratio,
        jump_gate_cents=jump_gate_cents,
    )
    gated_vocal_f0 = np.where(keep_mask, vocal_f0_raw, np.nan)
    frame_duration = hop_length / float(vocal_sr)

    max_offset_frames = int(round(max_delay_ms / 1000.0 / frame_duration)) if max_delay_ms > 0 else 0
    if max_offset_frames > 0:
        max_offset_frames = min(
            max_offset_frames,
            max(len(vocal_times) - 1, 0),
            max(len(ref_times) - 1, 0),
        )
    offsets_to_try = [0]
    if max_offset_frames > 0 and not penalize_late:
        offsets_to_try = list(range(-max_offset_frames, max_offset_frames + 1))

    def build_for_offset(offset_frames: int):
        vf0, rf0, vtimes, rtimes = _apply_offset(gated_vocal_f0, ref_f0, vocal_times, ref_times, offset_frames)
        vf0, rf0 = align_arrays(vf0, rf0)
        vtimes, _ = align_arrays(vtimes, rtimes)
        ref_midi_nearest = np.round(hz_to_midi_safe(rf0))
        ref_target_hz = pretty_midi.note_number_to_hz(ref_midi_nearest)
        ce = cents_error(vf0, ref_target_hz)
        summary = summarize_errors(
            ce,
            frame_duration=frame_duration,
            max_abs=score_max_abs_cents if score_max_abs_cents > 0 else None,
            ignore_short_ms=ignore_short_outliers_ms,
        )
        frames = []
        for i, (t, vh, rh) in enumerate(zip(vtimes, vf0, ref_target_hz)):
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

    best_summary = None
    best_frames = None
    best_offset = 0
    best_score = float("inf")
    for off in offsets_to_try:
        summary, frames = build_for_offset(off)
        score = summary["mean_abs_cents"] if summary["mean_abs_cents"] is not None else float("inf")
        if score < best_score:
            best_score = score
            best_summary = summary
            best_frames = frames
            best_offset = off

    summary = best_summary if best_summary is not None else {"mean_abs_cents": None, "pct_within_25": None, "pct_within_50": None, "pct_within_100": None, "valid_frames": 0}
    frames = best_frames if best_frames is not None else []
    offset_info = {
        "offset_frames": best_offset,
        "offset_ms": best_offset * frame_duration * 1000.0,
    }
    return summary, frames, offset_info


def _apply_offset(vf0, rf0, vtimes, rtimes, offset_frames: int):
    """Shift vocal vs reference by offset_frames (vocal delayed if positive)."""
    if offset_frames > 0:
        vf0 = vf0[offset_frames:]
        vtimes = vtimes[offset_frames:]
    elif offset_frames < 0:
        rf0 = rf0[-offset_frames:]
        rtimes = rtimes[-offset_frames:]
    return vf0, rf0, vtimes, rtimes

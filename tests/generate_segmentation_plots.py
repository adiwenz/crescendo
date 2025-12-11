#!/usr/bin/env python3
from pathlib import Path
import argparse
import sys

import librosa
import matplotlib.pyplot as plt
import numpy as np

# Ensure repo root on path for local imports
ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.append(str(ROOT))

from dutils.pitch_utils import estimate_pitch_pyin, _segment_notes_by_voicing

AUDIO_PATH = Path("audio/debug_phrase.wav")
OUT_ROOT = Path("segmentation_debug")

EXPERIMENTS = [
    {"name": "baseline", "max_gap_sec": 0.08, "max_jump_cents": 80.0},
    {"name": "more_sensitive", "max_gap_sec": 0.04, "max_jump_cents": 60.0},
    {"name": "tiny_gap", "max_gap_sec": 0.02, "max_jump_cents": 80.0},
    {"name": "small_jump", "max_gap_sec": 0.08, "max_jump_cents": 40.0},
    {"name": "tiny_gap_small_jump", "max_gap_sec": 0.02, "max_jump_cents": 40.0},
    {"name": "medium_gap_small_jump", "max_gap_sec": 0.06, "max_jump_cents": 50.0},
    {"name": "wide_gap_tight_jump", "max_gap_sec": 0.1, "max_jump_cents": 35.0},
    {"name": "loose_all", "max_gap_sec": 0.12, "max_jump_cents": 120.0},
]


def plot_experiment(exp_name, times, f0, vt, vf0, note_bounds, out_path: Path):
    fig, ax = plt.subplots(figsize=(12, 3))
    fig.patch.set_facecolor("#020617")
    ax.set_facecolor("#020617")

    f0_midi = librosa.hz_to_midi(f0)
    vf0_midi = librosa.hz_to_midi(vf0)

    # All frames
    ax.plot(times, f0_midi, color="#34d399", linewidth=1.0, label="All frames")
    # Voiced frames
    ax.plot(vt, vf0_midi, color="#22c55e", linewidth=1.2, label="Voiced frames")

    for start_i, end_i in note_bounds:
        start_t = vt[start_i]
        end_t = vt[end_i]
        seg_midi = vf0_midi[start_i : end_i + 1]
        mean_midi = float(np.nanmean(seg_midi)) if seg_midi.size else np.nan
        if not np.isfinite(mean_midi):
            continue
        ax.hlines(mean_midi, start_t, end_t, colors="#fbbf24", linewidth=4, label="Note" if start_i == note_bounds[0][0] else None)
        ax.axvline(start_t, color="#4b5563", linewidth=1, linestyle="--")

    ax.set_title(f"Segmentation: {exp_name}", color="#e5e7eb")
    ax.set_xlabel("Time (s)", color="#e5e7eb")
    ax.set_ylabel("Pitch (MIDI)", color="#e5e7eb")
    ax.grid(True, color="#111827")

    # Format y-axis ticks to note names where possible
    yticks = ax.get_yticks()
    ylabels = []
    for y in yticks:
        try:
            ylabels.append(librosa.midi_to_note(int(round(y))))
        except Exception:
            ylabels.append("")
    ax.set_yticks(yticks)
    ax.set_yticklabels(ylabels, color="#e5e7eb")
    ax.tick_params(axis="x", colors="#e5e7eb")

    handles, labels = ax.get_legend_handles_labels()
    if handles:
        ax.legend(loc="upper right", facecolor="#0f172a", edgecolor="#1f2937", labelcolor="#e5e7eb")

    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description="Generate segmentation debug plots for multiple configs.")
    parser.add_argument("--audio", type=Path, default=AUDIO_PATH, help="Input audio file (default: audio/debug_phrase.wav)")
    args = parser.parse_args()

    audio_path = args.audio

    if not audio_path.exists():
        sys.exit(f"Audio file not found: {audio_path}")

    print(f"Loading {audio_path} ...")
    y, sr = librosa.load(audio_path, sr=None, mono=True)

    print("Estimating pitch (PYIN)...")
    f0, times, voiced_flag = estimate_pitch_pyin(y, sr)
    voiced_mask = (~np.isnan(f0)) & (voiced_flag.astype(bool))
    if not np.any(voiced_mask):
        sys.exit("No voiced frames detected; cannot segment.")

    out_dir = OUT_ROOT / audio_path.stem
    out_dir.mkdir(parents=True, exist_ok=True)

    for cfg in EXPERIMENTS:
        name = cfg["name"]
        print(f"\nRunning experiment: {name}")
        vt, vf0, note_bounds = _segment_notes_by_voicing(
            times,
            f0,
            voiced_mask,
            max_gap_sec=cfg["max_gap_sec"],
            max_jump_cents=cfg["max_jump_cents"],
        )
        print(f"Found {len(note_bounds)} note segments")
        if not note_bounds:
            continue
        out_path = out_dir / f"segmentation_{name}.png"
        plot_experiment(name, times, f0, vt, vf0, note_bounds, out_path)
        print(f"Saved plot to {out_path}")

    print("\nDone.")


if __name__ == "__main__":
    main()

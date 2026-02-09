import argparse
import numpy as np
import soundfile as sf
import librosa
from scipy.signal import lfilter

# ----------------------------
# Utilities
# ----------------------------

def pre_emphasis(x: np.ndarray, coeff: float = 0.97) -> np.ndarray:
    """Simple pre-emphasis to flatten spectral tilt."""
    return np.append(x[0], x[1:] - coeff * x[:-1])

def frame_signal(x: np.ndarray, sr: int, frame_ms=30, hop_ms=10):
    frame_len = int(sr * frame_ms / 1000.0)
    hop_len = int(sr * hop_ms / 1000.0)
    if frame_len < 16 or hop_len < 1:
        raise ValueError("Frame/hop too small.")
    n_frames = 1 + max(0, (len(x) - frame_len) // hop_len)
    frames = np.stack([x[i * hop_len: i * hop_len + frame_len] for i in range(n_frames)], axis=0)
    return frames, frame_len, hop_len

def lpc_formants(frame: np.ndarray, sr: int, order: int = 16):
    """
    Estimate formants using LPC.
    Returns (f1, f2, f3, ...) in Hz (sorted), possibly empty if unstable.
    """
    # Window + normalize
    frame = frame * np.hamming(len(frame))
    if np.max(np.abs(frame)) < 1e-6:
        return []

    # LPC via autocorrelation + Levinson-Durbin (librosa provides lpc)
    try:
        a = librosa.lpc(frame, order=order)
    except Exception:
        return []

    # Roots of LPC polynomial -> formant candidates
    roots = np.roots(a)
    roots = roots[np.imag(roots) >= 0.0]  # one side
    ang = np.arctan2(np.imag(roots), np.real(roots))
    freqs = ang * (sr / (2.0 * np.pi))

    # Bandwidth estimate
    # bandwidth = -sr/(2π) * ln(|r|)
    mags = np.abs(roots)
    bws = - (sr / (2.0 * np.pi)) * np.log(np.maximum(mags, 1e-12))

    # Keep plausible speech/singing formants
    formants = []
    for f, bw in zip(freqs, bws):
        if 90 < f < 5000 and bw < 600:  # reject overly damped resonances
            formants.append(float(f))

    formants = sorted(formants)
    return formants

# Typical (very rough) vowel targets for adult speakers in Hz.
# Singing shifts these somewhat; treat as anchors, not truth.
VOWEL_TARGETS = {
    "iy": (300, 2300),  # "ee" as in "see"
    "ih": (400, 2000),  # "ih" as in "sit"
    "eh": (550, 1800),  # "eh" as in "set"
    "ae": (700, 1700),  # "ae" as in "sat"
    "aa": (800, 1300),  # "ah" as in "father" (varies!)
    "ao": (550, 1000),  # "aw" as in "saw"
    "uh": (500, 1200),  # "uh" as in "strut"
    "uw": (350, 900),   # "oo" as in "food"
    "ow": (450, 900),   # "oh" as in "go"
}

DISPLAY_NAMES = {
    "iy": "EE (iy)",
    "ih": "IH (ih)",
    "eh": "EH (eh)",
    "ae": "AE (ae)",
    "aa": "AH (aa)",
    "ao": "AW (ao)",
    "uh": "UH (uh)",
    "uw": "OO (uw)",
    "ow": "OH (ow)",
}

def classify_vowel(f1: float, f2: float, allowed=None):
    """
    Nearest neighbor in (F1,F2) space.
    If allowed is provided, restrict to those keys (e.g., ["aa","uh","uw"]).
    """
    keys = list(VOWEL_TARGETS.keys())
    if allowed:
        allowed_set = set(allowed)
        keys = [k for k in keys if k in allowed_set]
        if not keys:
            raise ValueError("Allowed set resulted in empty vowel list.")

    best_k, best_d = None, float("inf")
    for k in keys:
        t1, t2 = VOWEL_TARGETS[k]
        # Weighted distance: F2 tends to vary more; tweak weights as needed
        d = ((f1 - t1) ** 2) / (300 ** 2) + ((f2 - t2) ** 2) / (600 ** 2)
        if d < best_d:
            best_d = d
            best_k = k
    return best_k, best_d

def main():
    ap = argparse.ArgumentParser(description="Vowel detection for sustained sung vowels via LPC formants.")
    ap.add_argument("wav", help="Path to mono/stereo wav file")
    ap.add_argument("--allowed", nargs="*", default=None,
                    help="Restrict classification to these vowel keys (e.g., aa uh uw). Useful for on-screen prompts.")
    ap.add_argument("--sr", type=int, default=16000, help="Resample rate (default 16k)")
    ap.add_argument("--frame_ms", type=float, default=40.0, help="Frame length in ms (default 40)")
    ap.add_argument("--hop_ms", type=float, default=10.0, help="Hop length in ms (default 10)")
    ap.add_argument("--lpc_order", type=int, default=18, help="LPC order (default 18)")
    ap.add_argument("--min_f0", type=float, default=80.0, help="Min F0 for voiced gating (default 80)")
    ap.add_argument("--max_f0", type=float, default=1000.0, help="Max F0 for voiced gating (default 1000)")
    ap.add_argument("--top_db", type=float, default=35.0, help="Trim silence threshold (default 35dB)")
    args = ap.parse_args()

    y, file_sr = sf.read(args.wav)
    if y.ndim > 1:
        y = np.mean(y, axis=1)  # mono

    # Resample and trim
    y = librosa.resample(y.astype(np.float32), orig_sr=file_sr, target_sr=args.sr)
    y, _ = librosa.effects.trim(y, top_db=args.top_db)

    if len(y) < args.sr * 0.2:
        raise SystemExit("Audio too short after trimming. Provide a longer sustained vowel.")

    # Pitch track for voiced gating (pYIN)
    f0, voiced_flag, voiced_prob = librosa.pyin(
        y,
        fmin=args.min_f0,
        fmax=args.max_f0,
        sr=args.sr,
        frame_length=2048,
        hop_length=int(args.sr * args.hop_ms / 1000.0),
    )

    frames, frame_len, hop_len = frame_signal(y, args.sr, frame_ms=args.frame_ms, hop_ms=args.hop_ms)

    # Align voiced flags to frames (pyin hop matches our hop_ms if set correctly)
    # In practice, lengths might differ by 1; clamp safely.
    n = min(len(frames), len(voiced_flag))
    frames = frames[:n]
    vf = voiced_flag[:n]
    vp = voiced_prob[:n]
    f0 = f0[:n]

    # Pre-emphasis helps LPC a lot
    y_emph = pre_emphasis(y)
    frames_emph, _, _ = frame_signal(y_emph, args.sr, frame_ms=args.frame_ms, hop_ms=args.hop_ms)
    frames_emph = frames_emph[:n]

    f1_list = []
    f2_list = []
    conf_list = []

    for i in range(n):
        # Gate: voiced + decent confidence + not too low energy
        if not vf[i] or (vp[i] is not None and vp[i] < 0.7):
            continue

        frame = frames_emph[i]
        if np.sqrt(np.mean(frame ** 2)) < 1e-4:
            continue

        formants = lpc_formants(frame, args.sr, order=args.lpc_order)
        if len(formants) < 2:
            continue

        # Take first two formants
        f1, f2 = formants[0], formants[1]

        # Reject nonsense ordering / ranges that often occur on high F0 or noisy frames
        if not (150 <= f1 <= 1200 and 600 <= f2 <= 3500 and f2 > f1 + 200):
            continue

        f1_list.append(f1)
        f2_list.append(f2)
        conf_list.append(float(vp[i]) if vp[i] is not None else 0.7)

    if len(f1_list) < 8:
        raise SystemExit(
            "Not enough reliable voiced frames to estimate F1/F2.\n"
            "Tips: record a longer steady vowel, reduce background noise, and avoid very high pitches."
        )

    # Robust aggregate (median)
    f1_med = float(np.median(f1_list))
    f2_med = float(np.median(f2_list))
    conf = float(np.median(conf_list))

    vowel_key, dist = classify_vowel(f1_med, f2_med, allowed=args.allowed)

    print("---- Vowel Detection Result ----")
    print(f"Estimated F1: {f1_med:.1f} Hz")
    print(f"Estimated F2: {f2_med:.1f} Hz")
    print(f"Voicing confidence (median): {conf:.2f}")
    print(f"Predicted vowel: {DISPLAY_NAMES.get(vowel_key, vowel_key)}")
    print(f"Distance score (lower is better): {dist:.3f}")
    if args.allowed:
        print(f"Allowed set: {args.allowed}")
    print("--------------------------------")

if __name__ == "__main__":
    main()

import argparse, json, os
import numpy as np
import soundfile as sf
import librosa

def load_mono_resample(path, sr=16000, top_db=35):
    y, file_sr = sf.read(path)
    if y.ndim > 1:
        y = np.mean(y, axis=1)
    y = librosa.resample(y.astype(np.float32), orig_sr=file_sr, target_sr=sr)
    y, _ = librosa.effects.trim(y, top_db=top_db)
    return y, sr

def voiced_mask(y, sr, hop_length):
    f0, voiced_flag, voiced_prob = librosa.pyin(
        y, fmin=80, fmax=1000, sr=sr,
        frame_length=2048, hop_length=hop_length
    )
    # voiced_flag is boolean per frame
    return voiced_flag, voiced_prob

def mfcc_features(y, sr, frame_ms=40, hop_ms=10, n_mfcc=20, top_db=35):
    hop = int(sr * hop_ms / 1000.0)
    n_fft = 2048

    # Compute MFCC over time
    mfcc = librosa.feature.mfcc(
        y=y, sr=sr, n_mfcc=n_mfcc,
        n_fft=n_fft, hop_length=hop
    )  # shape: (n_mfcc, T)

    # Gate to voiced frames for stability
    vf, vp = voiced_mask(y, sr, hop)
    T = mfcc.shape[1]
    n = min(T, len(vf))
    mfcc = mfcc[:, :n]
    vf = vf[:n]
    vp = vp[:n]

    # Keep only confident voiced frames
    keep = (vf == True)
    if vp is not None:
        # vp has Nones; treat None as low confidence
        vp_arr = np.array([0.0 if v is None else float(v) for v in vp])
        keep = keep & (vp_arr >= 0.7)

    if np.sum(keep) < 10:
        raise RuntimeError("Not enough voiced frames. Sing a steadier sustained vowel.")

    mfcc_v = mfcc[:, keep]  # (n_mfcc, K)

    # Robust summary: median + IQR (helps separate close vowels like ih/iy)
    med = np.median(mfcc_v, axis=1)
    q25 = np.percentile(mfcc_v, 25, axis=1)
    q75 = np.percentile(mfcc_v, 75, axis=1)
    iqr = q75 - q25

    feat = np.concatenate([med, iqr], axis=0)  # length 2*n_mfcc
    return feat

def cosine_dist(a, b, eps=1e-9):
    a = a / (np.linalg.norm(a) + eps)
    b = b / (np.linalg.norm(b) + eps)
    return 1.0 - float(np.dot(a, b))

def calibrate(vowel_key, wav_path, sr, args):
    y, sr = load_mono_resample(wav_path, sr=sr, top_db=args.top_db)
    feat = mfcc_features(y, sr, frame_ms=args.frame_ms, hop_ms=args.hop_ms, n_mfcc=args.n_mfcc)
    return feat.tolist()

def predict(wav_path, model, sr, allowed, args):
    y, sr = load_mono_resample(wav_path, sr=sr, top_db=args.top_db)
    feat = mfcc_features(y, sr, frame_ms=args.frame_ms, hop_ms=args.hop_ms, n_mfcc=args.n_mfcc)
    feat = np.array(feat, dtype=np.float32)

    keys = list(model["centroids"].keys())
    if allowed:
        keys = [k for k in keys if k in set(allowed)]
        if not keys:
            raise RuntimeError("Allowed vowels not found in model. Calibrate them first.")

    best_k, best_d = None, 1e9
    for k in keys:
        c = np.array(model["centroids"][k], dtype=np.float32)
        d = cosine_dist(feat, c)
        if d < best_d:
            best_d = d
            best_k = k
    return best_k, best_d

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sr", type=int, default=16000)
    ap.add_argument("--frame_ms", type=float, default=40.0)
    ap.add_argument("--hop_ms", type=float, default=10.0)
    ap.add_argument("--n_mfcc", type=int, default=20)
    ap.add_argument("--top_db", type=float, default=35.0)
    ap.add_argument("--model", default="vowel_model.json")

    sub = ap.add_subparsers(dest="cmd", required=True)

    cal = sub.add_parser("calibrate")
    cal.add_argument("--vowel", required=True, help="Key like iy ih eh ae aa uw uh ow ao")
    cal.add_argument("--wav", required=True)

    pred = sub.add_parser("predict")
    pred.add_argument("--wav", required=True)
    pred.add_argument("--allowed", nargs="*", default=None)

    args = ap.parse_args()

    if args.cmd == "calibrate":
        model = {"sr": args.sr, "centroids": {}}
        if os.path.exists(args.model):
            with open(args.model, "r") as f:
                model = json.load(f)

        feat = calibrate(args.vowel, args.wav, sr=args.sr, args=args)
        model["centroids"][args.vowel] = feat

        with open(args.model, "w") as f:
            json.dump(model, f, indent=2)
        print(f"Saved centroid for {args.vowel} to {args.model}")

    elif args.cmd == "predict":
        if not os.path.exists(args.model):
            raise SystemExit("No model found. Run calibrate first.")
        with open(args.model, "r") as f:
            model = json.load(f)

        v, d = predict(args.wav, model, sr=model.get("sr", args.sr), allowed=args.allowed, args=args)
        print("---- Prediction ----")
        print(f"Predicted vowel: {v}")
        print(f"Distance: {d:.4f} (lower is better)")
        if args.allowed:
            print(f"Allowed: {args.allowed}")
        print("--------------------")

if __name__ == "__main__":
    main()

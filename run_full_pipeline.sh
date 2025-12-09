#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./run_full_pipeline.sh TAKE_NAME REFERENCE_WAV
# Example:
#   ./run_full_pipeline.sh LV35_05 audio_files/reference.wav
#
# Steps:
# 1) Record mic (press SPACE to stop) -> audio_files/<TAKE>.wav
# 2) Rebuild vocal_notes_stats.csv (all wavs), per-take CSV, takes_index.json
# 3) Run reference similarity (if REFERENCE_WAV provided) -> updates analysis_similarity.json
#
# Prereqs: `sounddevice`, `soundfile`, `librosa` installed (requirements.txt).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAKE_NAME="${1:-}"
REFERENCE_WAV="${2:-}"

if [[ -z "$TAKE_NAME" ]]; then
  echo "Take name required. Usage: ./run_full_pipeline.sh TAKE_NAME [REFERENCE_WAV]" >&2
  exit 1
fi

echo "=== Recording take '$TAKE_NAME' (press SPACE to stop; plays ref if provided) ==="
if [[ -n "$REFERENCE_WAV" ]]; then
  python3 "$ROOT/inter_take_analysis/record_and_process.py" --take_name "$TAKE_NAME" --play_reference "$REFERENCE_WAV"
else
  python3 "$ROOT/inter_take_analysis/record_and_process.py" --take_name "$TAKE_NAME"
fi

if [[ -n "$REFERENCE_WAV" ]]; then
  echo "=== Running similarity against reference: $REFERENCE_WAV ==="
  python3 "$ROOT/vocal_analyzer/update_analysis_similarity.py" \
    --vocal "$ROOT/audio_files/${TAKE_NAME}.wav" \
    --reference "$REFERENCE_WAV" \
    --take_name "$TAKE_NAME" \
    --trim_start 0 \
    --rms_gate_ratio 0.001 \
    --jump_gate_cents 1200
fi

echo "✅ Pipeline complete."

# Existing 
# python vocal_analyzer/update_analysis_similarity.py   --vocal vocal_analyzer/audio/vocal.wav   --reference vocal_analyzer/audio/reference.wav   --take_name EXISTING_TAKE

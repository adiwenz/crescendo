#!/usr/bin/env bash
set -euo pipefail

# Rerun pipeline for every take CSV in inter_take_analysis/takes/,
# skipping LV35_* takes. Reference WAV can be overridden by arg1.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAKES_DIR="$ROOT/inter_take_analysis/takes"
REF_WAV="${1:-$ROOT/audio_files/reference.wav}"

if [[ ! -f "$REF_WAV" ]]; then
  echo "Reference WAV not found: $REF_WAV" >&2
  exit 1
fi

PIPELINE="$ROOT/pipeline.py"

for csv in "$TAKES_DIR"/*.csv; do
  take="$(basename "$csv" .csv)"
  if [[ "$take" == LV35_* ]]; then
    echo "Skipping $take (LV35 prefix)"
    continue
  fi
  wav="$ROOT/audio_files/$take.wav"
  if [[ ! -f "$wav" ]]; then
    echo "Skipping $take (missing $wav)"
    continue
  fi
  echo "==> Re-running pipeline for $take"
  python3 "$PIPELINE" \
    --take_name "$take" \
    --reference "$REF_WAV" \
    --no_record \
    --score_max_abs_cents 100 \
    --ignore_short_outliers_ms 400 \
    --max_delay_ms 50
done

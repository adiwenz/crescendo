#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./batch_update_similarity.sh audio_files/reference.wav LV35_01 LV35_02 ...
# Example:
#   ./batch_update_similarity.sh audio_files/reference.wav LV35_01 LV35_02 LV35_03
#
# For each TAKE in args, runs update_analysis_similarity.py with:
#   vocal = audio_files/<TAKE>.wav
#   reference = provided reference wav
# Writes/updates vocal_analyzer/analysis_similarity.json with multiple runs.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF="${1:-}"
if [[ -z "$REF" ]]; then
  echo "Reference wav required. Usage: ./batch_update_similarity.sh reference.wav TAKE1 TAKE2 ..." >&2
  exit 1
fi
shift
if [[ $# -lt 1 ]]; then
  echo "Provide at least one take name (without .wav)." >&2
  exit 1
fi

for TAKE in "$@"; do
  VOC="$ROOT/audio_files/${TAKE}.wav"
  if [[ ! -f "$VOC" ]]; then
    echo "Skipping $TAKE (missing $VOC)" >&2
    continue
  fi
  echo "=== Updating $TAKE vs $REF ==="
  python3 "$ROOT/vocal_analyzer/update_analysis_similarity.py" \
    --vocal "$VOC" \
    --reference "$REF" \
    --take_name "$TAKE"
done

echo "✅ Done. Open vocal_analyzer/reference_takes_dashboard.html to view multiple takes."

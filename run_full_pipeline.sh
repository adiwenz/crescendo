#!/usr/bin/env bash
set -euo pipefail

# Legacy wrapper to use the new Python pipeline (no subprocess inside).
# Usage:
#   ./run_full_pipeline.sh TAKE_NAME [REFERENCE_WAV]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAKE_NAME="${1:-}"
REFERENCE_WAV="${2:-}"

if [[ -z "$TAKE_NAME" ]]; then
  echo "Take name required. Usage: ./run_full_pipeline.sh TAKE_NAME [REFERENCE_WAV]" >&2
  exit 1
fi

if [[ -n "$REFERENCE_WAV" ]]; then
  python3 "$ROOT/pipeline.py" --take_name "$TAKE_NAME" --reference "$REFERENCE_WAV"
else
  python3 "$ROOT/pipeline.py" --take_name "$TAKE_NAME"
fi

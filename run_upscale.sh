#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <input.mkv> [output.mkv]" >&2
  exit 1
fi

INPUT=$(readlink -f "$1")
BASENAME=$(basename "${INPUT%.*}")
OUTPUT=${2:-"${BASENAME}_4K.mkv"}

# refuse to overwrite the source
if [[ "$OUTPUT" == "$INPUT" ]]; then
  echo "[run_upscale] ERROR: output equals input; refusing to overwrite." >&2
  exit 2
fi

TMP_OUT="${OUTPUT}.tmp"

# Load env
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/env.sh"

# Basic host-side sanity
if [[ ! -r "$INPUT" ]]; then
  echo "[run_upscale] ERROR: input not readable on host: $INPUT" >&2
  exit 3
fi

# Build in-container script with concrete, host-expanded paths
# Execute the entrypoint script in the container
DOCKER_CMD="entrypoint.sh pipeline.vpy \"$INPUT\" \"$OUTPUT\""

# Debug view
if [[ "${DEBUG:-0}" == "1" ]]; then
  echo "[run_upscale] DOCKER_RUN: $DOCKER_RUN" >&2
  echo "[run_upscale] DOCKER_CMD: $DOCKER_CMD" >&2
fi

# Execute
$DOCKER_RUN bash -c "$DOCKER_CMD"

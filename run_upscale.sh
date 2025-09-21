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
IN_CONTAINER=$(cat <<SH
set -euo pipefail

INPUT="$INPUT"
OUTPUT="$OUTPUT"
TMP_OUT="$TMP_OUT"
WORKDIR="$PWD"

# Preflight: input readability
if [ ! -r "\$INPUT" ]; then
  echo "[container] ERROR: input not readable: \$INPUT" >&2
  exit 10
fi

# Preflight: print VS plugin presence (non-fatal)
python - <<'PY'
import vapoursynth as vs
c=vs.core
missing=[ns for ns in ("ffms2","lsmas","bs","nnedi3cl","tivtc") if not hasattr(c, ns)]
print("[container] VS OK; missing plugins:", ",".join(missing) if missing else "none")
PY

# Model auto-discovery
if [ "\${AUTO_FIND_MODELS:-false}" = "true" ]; then
  if [ ! -f "\$ESRGAN_MODEL" ] && [ -n "\${ESRGAN_MODEL_NAME:-}" ]; then
    f=\$(find /models -type f -iname "\$ESRGAN_MODEL_NAME" -print -quit 2>/dev/null); [ -n "\$f" ] && export ESRGAN_MODEL="\$f"
  fi
  if [ ! -f "\$BASICVSR_MODEL" ] && [ -n "\${BASICVSR_MODEL_NAME:-}" ]; then
    f=\$(find /models -type f -iname "\$BASICVSR_MODEL_NAME" -print -quit 2>/dev/null); [ -n "\$f" ] && export BASICVSR_MODEL="\$f"
  fi
fi

# Run pipeline (y4m) into ffmpeg; write to temp then move on success
set -o pipefail
cd "\$WORKDIR"
vspipe -c y4m "pipeline.vpy" "\$INPUT" | \
  ffmpeg -hide_banner -loglevel error -y -r 24000/1001 -i - -i "\$INPUT" \
    -map 0:v:0 -map 1:a:0 -c:a copy \
    -vf "scale=3840:2160:flags=lanczos+accurate_rnd:in_color_matrix=bt601:out_color_matrix=bt709,format=p010le" \
    -c:v hevc_nvenc -preset p5 -rc:v vbr_hq -cq:v 18 -b:v 0 \
    -pix_fmt p010le -profile:v main10 \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
    "\$TMP_OUT" \
  && mv -f "\$TMP_OUT" "\$OUTPUT"
SH
)

# Debug view
if [[ "${DEBUG:-0}" == "1" ]]; then
  echo "[run_upscale] DOCKER_RUN: $DOCKER_RUN" >&2
  echo "[run_upscale] IN_CONTAINER:" >&2
  echo "$IN_CONTAINER" >&2
fi

# Execute
$DOCKER_RUN "$(printf '%s' "$IN_CONTAINER")"

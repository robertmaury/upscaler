#!/usr/bin/env bash
set -euo pipefail

VPY_SCRIPT="$1"
INPUT="$2"
OUTPUT="$3"
TMP_OUT="${OUTPUT}.tmp"

# Preflight: input readability
if [ ! -r "$INPUT" ]; then
  echo "[container] ERROR: input not readable: $INPUT" >&2
  exit 10
fi

# Preflight: output must not equal input
if [ "$INPUT" = "$OUTPUT" ]; then
  echo "[container] ERROR: input and output files are the same; refusing to overwrite." >&2
  exit 11
fi

# Preflight: print VS plugin presence (non-fatal)
python3 -c '
import vapoursynth as vs
c=vs.core
missing=[ns for ns in ("ffms2","lsmas","bs","nnedi3cl","tivtc") if not hasattr(c, ns)]
print("[container] VS OK; missing plugins:", ",".join(missing) if missing else "none")
'

# Model auto-discovery
if [ "${AUTO_FIND_MODELS:-false}" = "true" ]; then
  if [ ! -f "$ESRGAN_MODEL" ] && [ -n "${ESRGAN_MODEL_NAME:-}" ]; then
    f=$(find /models -type f -iname "$ESRGAN_MODEL_NAME" -print -quit 2>/dev/null); [ -n "$f" ] && export ESRGAN_MODEL="$f"
  fi
  if [ ! -f "$BASICVSR_MODEL" ] && [ -n "${BASICVSR_MODEL_NAME:-}" ]; then
    f=$(find /models -type f -iname "$BASICVSR_MODEL_NAME" -print -quit 2>/dev/null); [ -n "$f" ] && export BASICVSR_MODEL="$f"
  fi
fi

# Detect frame rate from source video
FRAMERATE=$((ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT") 2>/dev/null || echo "24000/1001")

# Use detected frame rate, but allow override via environment variable
FINAL_FRAMERATE="${FFMPEG_FRAMERATE:-$FRAMERATE}"
echo "[container] Using frame rate: ${FINAL_FRAMERATE}"

# Run pipeline (y4m) into ffmpeg; write to temp then move on success
# Debugging vspipe - this will fail, but should produce a useful log
echo "[container] Running vspipe in debug mode..." >&2
vspipe "$VPY_SCRIPT" "$INPUT" -p >/tmp/vspipe.log 2>&1
echo "[container] vspipe finished. Check logs/vspipe.log on the host." >&2
exit 1 # Exit after debugging
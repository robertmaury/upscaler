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
set -o pipefail
vspipe -c y4m "$VPY_SCRIPT" "$INPUT" 2>/tmp/vspipe.log | \
  ffmpeg -hide_banner -loglevel error -y -r "${FINAL_FRAMERATE}" -i - -i "$INPUT" \
    -map 0:v:0 -map 1:a:0 -c:a copy \
    -vf "scale=-1:2160:flags=lanczos,pad=3840:2160:-1:-1:color=black,format=p010le" \
    -c:v "${FFMPEG_VCODEC:-hevc_nvenc}" -preset "${FFMPEG_PRESET:-p5}" -rc:v "${FFMPEG_RC:-vbr_hq}" -cq:v "${FFMPEG_CQ:-18}" -b:v 0 \
    -pix_fmt p010le -profile:v main10 \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
    "$TMP_OUT" \
  && mv -f "$TMP_OUT" "$OUTPUT"
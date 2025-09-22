#!/usr/bin/env bash
set -euo pipefail

VPY_SCRIPT="$1"
INPUT="$2"
OUTPUT="$3"
TMP_OUT=$(mktemp "${OUTPUT%.*}.XXXXXX.${OUTPUT##*.}")

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

# Preflight: comprehensive plugin diagnostics
python3 -c '
import vapoursynth as vs
c = vs.core

# Check critical plugins for source loading
source_plugins = {"ffms2": "FFMS2", "lsmas": "L-SMASH", "bs": "BestSource"}
available_sources = []
missing_sources = []

for plugin, name in source_plugins.items():
    if hasattr(c, plugin):
        try:
            # Test basic functionality
            if plugin == "ffms2":
                # Test ffms2 availability
                getattr(c.ffms2, "Source", None)
                available_sources.append(f"{name} (core.{plugin})")
            elif plugin == "lsmas":
                getattr(c.lsmas, "LWLibavSource", None)
                available_sources.append(f"{name} (core.{plugin})")
            elif plugin == "bs":
                getattr(c.bs, "VideoSource", None)
                available_sources.append(f"{name} (core.{plugin})")
        except Exception as e:
            missing_sources.append(f"{name} (core.{plugin} error: {e})")
    else:
        missing_sources.append(f"{name} (core.{plugin} missing)")

print(f"[container] Available source plugins: {available_sources}")
if missing_sources:
    print(f"[container] WARNING - Missing source plugins: {missing_sources}")

# Check other processing plugins
other_plugins = {"nnedi3cl": "NNEDI3CL", "tivtc": "TIVTC", "bm3dcuda": "BM3D-CUDA"}
missing_other = []
for plugin, name in other_plugins.items():
    if not hasattr(c, plugin):
        missing_other.append(name)

if missing_other:
    print(f"[container] Missing processing plugins: {missing_other}")
else:
    print("[container] All processing plugins available")

print(f"[container] VS plugin path: {vs.get_plugin_path()}")
'

# Model validation and auto-discovery
validate_and_find_models() {
  local upscale_impl="${UPSCALE_IMPL:-esrgan}"

  if [ "$upscale_impl" = "none" ]; then
    echo "[container] Upscaling disabled, skipping model validation"
    return 0
  fi

  # Auto-discovery if enabled
  if [ "${AUTO_FIND_MODELS:-false}" = "true" ]; then
    if [ ! -f "$ESRGAN_MODEL" ] && [ -n "${ESRGAN_MODEL_NAME:-}" ]; then
      f=$(find /models -type f -iname "$ESRGAN_MODEL_NAME" -print -quit 2>/dev/null)
      [ -n "$f" ] && export ESRGAN_MODEL="$f"
    fi
    if [ ! -f "$BASICVSR_MODEL" ] && [ -n "${BASICVSR_MODEL_NAME:-}" ]; then
      f=$(find /models -type f -iname "$BASICVSR_MODEL_NAME" -print -quit 2>/dev/null)
      [ -n "$f" ] && export BASICVSR_MODEL="$f"
    fi
    if [ ! -f "$REALCUGAN_MODEL" ] && [ -n "${REALCUGAN_MODEL_NAME:-}" ]; then
      f=$(find /models -type f -iname "$REALCUGAN_MODEL_NAME" -print -quit 2>/dev/null)
      [ -n "$f" ] && export REALCUGAN_MODEL="$f"
    fi
  fi

  # Validate required models exist
  case "$upscale_impl" in
    "realcugan")
      if [ ! -f "$REALCUGAN_MODEL" ]; then
        echo "[container] ERROR: Real-CUGAN model not found: $REALCUGAN_MODEL" >&2
        echo "[container] Available models in /models:" >&2
        find /models -name "*.pth" -o -name "*.onnx" 2>/dev/null | head -10 >&2
        echo "[container] Falling back to RealESRGAN" >&2
        export UPSCALE_IMPL="esrgan"
        validate_and_find_models  # Recursive fallback
        return $?
      fi
      echo "[container] Using Real-CUGAN model: $REALCUGAN_MODEL"
      ;;
    "esrgan")
      if [ ! -f "$ESRGAN_MODEL" ]; then
        echo "[container] ERROR: RealESRGAN model not found: $ESRGAN_MODEL" >&2
        echo "[container] Available models in /models:" >&2
        find /models -name "*.pth" -o -name "*.onnx" 2>/dev/null | head -10 >&2
        echo "[container] Falling back to no upscaling" >&2
        export UPSCALE_IMPL="none"
        return 1
      fi
      echo "[container] Using RealESRGAN model: $ESRGAN_MODEL"
      ;;
    "basicvsr")
      if [ ! -f "$BASICVSR_MODEL" ]; then
        echo "[container] ERROR: BasicVSR model not found: $BASICVSR_MODEL" >&2
        echo "[container] Available models in /models:" >&2
        find /models -name "*.pth" -o -name "*.onnx" 2>/dev/null | head -10 >&2
        echo "[container] Falling back to RealESRGAN" >&2
        export UPSCALE_IMPL="esrgan"
        validate_and_find_models  # Recursive fallback
        return $?
      fi
      echo "[container] Using BasicVSR model: $BASICVSR_MODEL"
      ;;
  esac
  return 0
}

validate_and_find_models

# Detect video properties from source
VIDEO_INFO=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate,display_aspect_ratio -of csv=p=0 "$INPUT" 2>/dev/null)
if [ -z "$VIDEO_INFO" ]; then
  echo "[container] ERROR: Could not detect video properties from $INPUT" >&2
  exit 12
fi

IFS=',' read -r WIDTH HEIGHT FRAMERATE ASPECT_RATIO <<< "$VIDEO_INFO"
FRAMERATE=${FRAMERATE:-"24000/1001"}

# Use detected frame rate, but allow override via environment variable
FINAL_FRAMERATE="${FFMPEG_FRAMERATE:-$FRAMERATE}"

# Calculate target dimensions preserving aspect ratio
# Handle variable input resolutions (480p, 720p, 1080p)

# Determine the upscaling factor based on source resolution
if [ "$HEIGHT" -le 480 ]; then
  # 480p or lower - 4x upscale
  SCALE_FACTOR=4
  TARGET_HEIGHT=$((HEIGHT * 4))
  TARGET_WIDTH=$((WIDTH * 4))
elif [ "$HEIGHT" -le 720 ]; then
  # 720p - 3x upscale to get close to 4K
  SCALE_FACTOR=3
  TARGET_HEIGHT=$((HEIGHT * 3))
  TARGET_WIDTH=$((WIDTH * 3))
elif [ "$HEIGHT" -le 1080 ]; then
  # 1080p - 2x upscale
  SCALE_FACTOR=2
  TARGET_HEIGHT=$((HEIGHT * 2))
  TARGET_WIDTH=$((WIDTH * 2))
else
  # Already high resolution - minimal upscale
  SCALE_FACTOR=1
  TARGET_HEIGHT=$HEIGHT
  TARGET_WIDTH=$WIDTH
fi

# Ensure dimensions are even numbers (required for most codecs)
TARGET_WIDTH=$(( (TARGET_WIDTH + 1) / 2 * 2 ))
TARGET_HEIGHT=$(( (TARGET_HEIGHT + 1) / 2 * 2 ))

# For standard aspect ratios, snap to common resolutions if close
CALCULATED_AR=$(echo "scale=3; $TARGET_WIDTH / $TARGET_HEIGHT" | bc -l)
if (( $(echo "$CALCULATED_AR > 1.7 && $CALCULATED_AR < 1.8" | bc -l) )); then
  # Close to 16:9 - snap to 4K or appropriate 16:9 resolution
  if [ "$TARGET_HEIGHT" -ge 2000 ]; then
    TARGET_WIDTH=3840
    TARGET_HEIGHT=2160
  elif [ "$TARGET_HEIGHT" -ge 1400 ]; then
    TARGET_WIDTH=2560
    TARGET_HEIGHT=1440
  fi
elif (( $(echo "$CALCULATED_AR > 1.3 && $CALCULATED_AR < 1.4" | bc -l) )); then
  # Close to 4:3 - maintain proportion but ensure even dimensions
  if [ "$TARGET_HEIGHT" -ge 2000 ]; then
    TARGET_WIDTH=2880
    TARGET_HEIGHT=2160
  fi
fi

echo "[container] Source: ${WIDTH}x${HEIGHT} (${ASPECT_RATIO})"
echo "[container] Target: ${TARGET_WIDTH}x${TARGET_HEIGHT} (${SCALE_FACTOR}x upscale)"
echo "[container] Using frame rate: ${FINAL_FRAMERATE}"

# Run pipeline (y4m) into ffmpeg; write to temp then move on success
set -o pipefail
vspipe -c y4m "$VPY_SCRIPT" "$INPUT" | \
  ffmpeg -hide_banner -loglevel error -y -r "${FINAL_FRAMERATE}" -i - -i "$INPUT" \
    -map 0:v:0 -map 1:a:0 -c:a copy \
    -vf "scale=${TARGET_WIDTH}:${TARGET_HEIGHT}:flags=lanczos,format=p010le" \
    -c:v "${FFMPEG_VCODEC:-hevc_nvenc}" -preset "${FFMPEG_PRESET:-p5}" -rc:v "${FFMPEG_RC:-vbr_hq}" -cq:v "${FFMPEG_CQ:-18}" -b:v 0 \
    -pix_fmt p010le -profile:v main10 \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
    "$TMP_OUT" \
  && mv -f "$TMP_OUT" "$OUTPUT"

# Clean up the temporary file if the script is interrupted
trap 'rm -f "$TMP_OUT"' EXIT
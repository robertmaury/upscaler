#!/usr/bin/env bash
# env.sh — clean

# ---- Image tag (use your built image) ----
: "${DOCKER_IMAGE:=vapoursynth:latest}"
# Temporary fallback (not recommended for long term):
# DOCKER_IMAGE=pifroggi/vapoursynth:2025_09_05

# ---- Source + IVTC toggles ----
# SOURCE_IMPL: ffms2 | lsmas | bestsource
: "${SOURCE_IMPL:=ffms2}"
# IVTC: 1=apply TFM/TDecimate, 0=skip (set 0 for pure interlaced or already-progressive sources)
: "${IVTC:=1}"
# FORCE_TFF: 1=top field first, 0=bottom field first (auto-detected if not set)
: "${FORCE_TFF:=1}"

# ---- Denoise + Upscaler choices ----
# DENOISE_IMPL: bm3d | none
: "${DENOISE_IMPL:=none}"  # Default to no denoise for clean animation
# BM3D parameters (lower values for animation)
: "${BM3D_SIGMA:=1.5}"  # Reduced for clean animation
: "${BM3D_RADIUS:=1}"
# UPSCALE_IMPL: esrgan | basicvsr | realcugan | none
: "${UPSCALE_IMPL:=esrgan}"

# ---- Animation-specific settings ----
# CONTENT_TYPE: animation | live_action | mixed
: "${CONTENT_TYPE:=animation}"
# QTGMC_PRESET: Fast | Medium | Slow (Fast recommended for animation)
: "${QTGMC_PRESET:=Fast}"

# ---- FFMPEG settings ----
# Frame rate is auto-detected by default.
# To override, set FFMPEG_FRAMERATE to your desired value (e.g., "30000/1001").
: "${FFMPEG_FRAMERATE:=}"
: "${FFMPEG_VCODEC:=hevc_nvenc}"
: "${FFMPEG_PRESET:=p5}"
: "${FFMPEG_RC:=vbr_hq}"
: "${FFMPEG_CQ:=18}"

# ---- Model locations ----
# If true: models are already in the image at /models (no host mount)
# If false: set MODELS_DIR (host path) to bind-mount at /models (read‑only)
: "${MODELS_IN_CONTAINER:=true}"
: "${MODELS_DIR:=/path/to/models}"

# (Optional) explicit relative paths under /models
: "${ESRGAN_MODEL_REL:=realesrgan/RealESRGAN_x4plus_anime_6B.pth}"
: "${BASICVSR_MODEL_REL:=basicvsrpp/BasicVSRPP_x4_vimeo90k.pth}"

# Animation-optimized model alternatives
: "${ESRGAN_ANIME_MODEL_REL:=realesrgan/RealESRGAN_x4plus_anime_6B.pth}"
: "${ESRGAN_CARTOON_MODEL_REL:=realesrgan/RealESRGAN_x2plus.pth}"  # For higher res sources
: "${BASICVSR_ANIME_MODEL_REL:=basicvsrpp/BasicVSRPP_x4_anime.pth}"

# (Optional) auto‑discover by filename anywhere under /models
: "${AUTO_FIND_MODELS:=true}"
: "${ESRGAN_MODEL_NAME:=RealESRGAN_x4plus_anime_6B.pth}"
: "${BASICVSR_MODEL_NAME:=BasicVSRPP_x4_vimeo90k.pth}"

# Alternative model names for auto-discovery
: "${ESRGAN_ANIME_MODEL_NAME:=RealESRGAN_x4plus_anime_6B.pth}"
: "${ESRGAN_CARTOON_MODEL_NAME:=RealESRGAN_x2plus.pth}"
: "${BASICVSR_ANIME_MODEL_NAME:=BasicVSRPP_x4_anime.pth}"

# Real-CUGAN models (superior for animation)
: "${REALCUGAN_MODEL_REL:=realcugan/Real-CUGAN_up4x-latest-conservative.pth}"
: "${REALCUGAN_2X_MODEL_REL:=realcugan/Real-CUGAN_up2x-latest-denoise3x.pth}"
: "${REALCUGAN_MODEL_NAME:=Real-CUGAN_up4x-latest-conservative.pth}"

# In‑container model paths (defaults)
export ESRGAN_MODEL="/models/${ESRGAN_MODEL_REL}"
export BASICVSR_MODEL="/models/${BASICVSR_MODEL_REL}"
export REALCUGAN_MODEL="/models/${REALCUGAN_MODEL_REL}"

# ---- Optional extra mounts for inputs (e.g., SMB share) ----
# Space‑separated list of host paths to mount read‑only at the same path in the container.
# Example: export MOUNT_INPUT_ROOTS="/mnt/futurama /media/raid"
: "${MOUNT_INPUT_ROOTS:=}"

# Build extra mount flags
EXTRA_MOUNTS=""
for p in ${MOUNT_INPUT_ROOTS}; do
  EXTRA_MOUNTS+=" -v ${p}:${p}:ro"
done

# Conditionally add /models mount
MODEL_MOUNT_OPTS=""
if [ "${MODELS_IN_CONTAINER}" != "true" ]; then
  if [ ! -d "${MODELS_DIR}" ]; then
    echo "[env.sh] ERROR: MODELS_DIR does not exist: ${MODELS_DIR}" >&2
    return 1 2>/dev/null || exit 1
  fi
  MODEL_MOUNT_OPTS="-v ${MODELS_DIR}:/models:ro"
fi

# Final docker run prefix (exports all toggles and paths)
export DOCKER_RUN="docker run --rm --gpus all \
  -v $PWD/logs:/tmp \
  -v $PWD:$PWD -w $PWD \
  ${MODEL_MOUNT_OPTS} ${EXTRA_MOUNTS} \
  -e SOURCE_IMPL=${SOURCE_IMPL} -e IVTC=${IVTC} -e FORCE_TFF=${FORCE_TFF} \
  -e DENOISE_IMPL=${DENOISE_IMPL} -e BM3D_SIGMA=${BM3D_SIGMA} -e BM3D_RADIUS=${BM3D_RADIUS} \
  -e UPSCALE_IMPL=${UPSCALE_IMPL} -e CONTENT_TYPE=${CONTENT_TYPE} -e QTGMC_PRESET=${QTGMC_PRESET} \
  -e FFMPEG_FRAMERATE=${FFMPEG_FRAMERATE} -e FFMPEG_VCODEC=${FFMPEG_VCODEC} -e FFMPEG_PRESET=${FFMPEG_PRESET} \
  -e FFMPEG_RC=${FFMPEG_RC} -e FFMPEG_CQ=${FFMPEG_CQ} \
  -e AUTO_FIND_MODELS=${AUTO_FIND_MODELS} \
  -e ESRGAN_MODEL=${ESRGAN_MODEL} -e ESRGAN_MODEL_NAME=${ESRGAN_MODEL_NAME} \
  -e BASICVSR_MODEL=${BASICVSR_MODEL} -e BASICVSR_MODEL_NAME=${BASICVSR_MODEL_NAME} \
  -e REALCUGAN_MODEL=${REALCUGAN_MODEL} -e REALCUGAN_MODEL_NAME=${REALCUGAN_MODEL_NAME} \
  ${DOCKER_IMAGE}"

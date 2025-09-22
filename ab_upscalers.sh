#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <input.mkv>" >&2
  exit 1
fi

INPUT=$(readlink -f "$1")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/env.sh"

base="$(basename "${INPUT%.*}")"

# Test with RealESRGAN
UPSCALE_IMPL=esrgan "$SCRIPT_DIR/run_upscale.sh" "$INPUT" "${base}_ESRGAN_4K.mkv"

# Test with BasicVSR++
UPSCALE_IMPL=basicvsr "$SCRIPT_DIR/run_upscale.sh" "$INPUT" "${base}_BasicVSR_4K.mkv"

# Test with Real-CUGAN (if available)
UPSCALE_IMPL=realcugan "$SCRIPT_DIR/run_upscale.sh" "$INPUT" "${base}_RealCUGAN_4K.mkv"

echo "A/B testing complete. Compare outputs:"
echo "  ${base}_ESRGAN_4K.mkv"
echo "  ${base}_BasicVSR_4K.mkv"
echo "  ${base}_RealCUGAN_4K.mkv"
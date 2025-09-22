#!/usr/bin/env bash
# Futurama-Optimized Environment Configuration
# Source this file for optimal Futurama box set processing

# Inherit base configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/env.sh"

# ---- Futurama-Specific Overrides ----

# Default to animation-optimized settings
export CONTENT_TYPE="animation"
export QTGMC_PRESET="Fast"
export UPSCALE_IMPL="realcugan"  # BEST for animation
export DENOISE_IMPL="none"       # Animation typically doesn't need denoising

# Interlaced content settings (most early Futurama)
export IVTC=1
export FORCE_TFF=1

# Animation-optimized encoding
export FFMPEG_VCODEC="hevc_nvenc"
export FFMPEG_PRESET="p5"       # Slower preset for better quality
export FFMPEG_CQ=18             # High quality for archival

# Memory-efficient tiling for typical Futurama content
export ESRGAN_TILE=256          # Conservative for 480p content
export BASICVSR_TILE_W=384
export BASICVSR_TILE_H=384
export BASICVSR_OVERLAP=16

# Model preferences for animation
export ESRGAN_MODEL_NAME="RealESRGAN_x4plus_anime_6B.pth"
export BASICVSR_MODEL_NAME="BasicVSRPP_x4_vimeo90k.pth"

# Season-specific presets
configure_for_season() {
    local season="$1"

    case "$season" in
        "1"|"2"|"3"|"4"|"5"|"6"|"7"|"early")
            echo "Configuring for early Futurama (Seasons 1-7, 1999-2003)"
            export CONTENT_TYPE="animation"
            export QTGMC_PRESET="Fast"
            export UPSCALE_IMPL="realcugan"  # Best for clean animation
            export DENOISE_IMPL="none"
            export IVTC=1
            export FORCE_TFF=1
            export REALCUGAN_TILE=256
            ;;
        "movies"|"films")
            echo "Configuring for Futurama movies"
            export CONTENT_TYPE="animation"
            export QTGMC_PRESET="Medium"    # Higher quality for movies
            export UPSCALE_IMPL="basicvsr"  # Better temporal coherence
            export DENOISE_IMPL="bm3d"      # Light denoising for film sources
            export BM3D_SIGMA=1.0
            export IVTC=1
            export FORCE_TFF=1
            export BASICVSR_TILE_W=512      # Larger tiles for better quality
            export BASICVSR_TILE_H=512
            ;;
        "8"|"9"|"10"|"11"|"later"|"hd")
            echo "Configuring for later Futurama (Seasons 8-11, 2008+)"
            export CONTENT_TYPE="animation"
            export QTGMC_PRESET="Fast"
            export UPSCALE_IMPL="esrgan"
            export DENOISE_IMPL="none"
            export IVTC=0                   # Usually progressive
            export ESRGAN_TILE=384          # Can handle larger tiles
            ;;
        *)
            echo "Unknown season: $season. Using default animation settings."
            ;;
    esac
}

# Quality presets
configure_for_quality() {
    local quality="$1"

    case "$quality" in
        "archive"|"best")
            echo "Configuring for archival quality"
            export QTGMC_PRESET="Slow"
            export FFMPEG_CQ=15             # Very high quality
            export FFMPEG_PRESET="p7"       # Slowest preset
            export DENOISE_IMPL="bm3d"
            export BM3D_SIGMA=0.8           # Minimal denoising
            ;;
        "fast"|"preview")
            echo "Configuring for fast processing"
            export QTGMC_PRESET="Fast"
            export FFMPEG_CQ=22             # Lower quality, faster
            export FFMPEG_PRESET="p1"       # Fastest preset
            export ESRGAN_TILE=192          # Smaller tiles
            ;;
        "balanced"|"default")
            echo "Configuring for balanced quality/speed"
            export QTGMC_PRESET="Medium"
            export FFMPEG_CQ=18
            export FFMPEG_PRESET="p5"
            ;;
    esac
}

# Batch processing helpers
setup_batch_processing() {
    local input_dir="$1"
    local output_dir="$2"

    if [[ ! -d "$input_dir" ]]; then
        echo "Error: Input directory does not exist: $input_dir" >&2
        return 1
    fi

    mkdir -p "$output_dir/logs"

    export BATCH_INPUT_DIR="$input_dir"
    export BATCH_OUTPUT_DIR="$output_dir"

    echo "Batch processing configured:"
    echo "  Input: $input_dir"
    echo "  Output: $output_dir"
    echo "  Logs: $output_dir/logs"
}

# Print current configuration
show_config() {
    cat << EOF
Current Futurama Upscaling Configuration:
==========================================

Content Settings:
  Content Type: $CONTENT_TYPE
  QTGMC Preset: $QTGMC_PRESET
  Upscale Method: $UPSCALE_IMPL
  Denoise Method: $DENOISE_IMPL

Deinterlacing:
  IVTC Enabled: $IVTC
  Field Order (TFF): $FORCE_TFF

Encoding:
  Video Codec: $FFMPEG_VCODEC
  Preset: $FFMPEG_PRESET
  Quality (CQ): $FFMPEG_CQ

Performance:
  ESRGAN Tile Size: ${ESRGAN_TILE:-"auto"}
  BasicVSR Tile: ${BASICVSR_TILE_W:-"auto"}x${BASICVSR_TILE_H:-"auto"}

Models:
  ESRGAN Model: $ESRGAN_MODEL_NAME
  BasicVSR Model: $BASICVSR_MODEL_NAME
  Models Directory: $MODELS_DIR
  Models in Container: $MODELS_IN_CONTAINER

Docker Image: $DOCKER_IMAGE

EOF
}

# Usage examples
usage_examples() {
    cat << EOF
Futurama Processing Examples:
============================

1. Process early seasons (1999-2003):
   configure_for_season "early"
   ./batch_futurama.sh /media/futurama/seasons1-7 /media/output/futurama_4k

2. Process movies with high quality:
   configure_for_season "movies"
   configure_for_quality "archive"
   ./batch_futurama.sh /media/futurama/movies /media/output/movies_4k

3. Quick preview of later seasons:
   configure_for_season "later"
   configure_for_quality "fast"
   ./run_upscale.sh /media/futurama/s08e01.mkv preview_output.mkv

4. Custom processing:
   export UPSCALE_IMPL="basicvsr"
   export DENOISE_IMPL="bm3d"
   export BM3D_SIGMA=1.5
   ./run_upscale.sh input.mkv output.mkv

5. Batch with parallel processing:
   configure_for_season "early"
   ./batch_futurama.sh --parallel 2 /input /output

Functions available:
  configure_for_season [1-7|movies|8-11|early|later|hd]
  configure_for_quality [archive|fast|balanced]
  setup_batch_processing INPUT_DIR OUTPUT_DIR
  show_config
  usage_examples

EOF
}

# Auto-detect and suggest configuration
auto_configure() {
    local input_path="${1:-$PWD}"

    echo "Auto-detecting Futurama content in: $input_path"

    # Look for season indicators
    local season_files=$(find "$input_path" -name "*.mkv" -o -name "*.avi" -o -name "*.mp4" | head -10)

    if echo "$season_files" | grep -qi "season.*0?[1-7]\|s0?[1-7]e"; then
        echo "Detected early seasons (1999-2003) - configuring for 480i interlaced content"
        configure_for_season "early"
    elif echo "$season_files" | grep -qi "movie\|film\|bender\|wild"; then
        echo "Detected movies - configuring for high-quality processing"
        configure_for_season "movies"
    elif echo "$season_files" | grep -qi "season.*0?[8-9]\|season.*1[0-1]\|s0?[8-9]e\|s1[0-1]e"; then
        echo "Detected later seasons (2008+) - configuring for HD progressive content"
        configure_for_season "later"
    else
        echo "Could not auto-detect content type - using default animation settings"
        configure_for_season "early"  # Conservative default
    fi

    show_config
}

# Initialize with defaults
echo "Futurama upscaling environment loaded"
echo "Run 'usage_examples' for help, or 'auto_configure [path]' for automatic setup"
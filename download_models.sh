#!/usr/bin/env bash
set -euo pipefail

# Model Download Helper for Futurama Upscaling
# Downloads optimal AI models for animation upscaling

MODELS_DIR="${MODELS_DIR:-./models}"
# SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"  # Currently unused

# Model URLs and info
declare -A MODELS=(
    # Real-CUGAN models (BEST for animation)
    ["Real-CUGAN_up4x-latest-conservative.pth"]="https://github.com/bilibili/ailab/releases/download/Real-CUGAN/up4x-latest-conservative.pth|realcugan|BEST for clean animation like Futurama"
    ["Real-CUGAN_up2x-latest-denoise3x.pth"]="https://github.com/bilibili/ailab/releases/download/Real-CUGAN/up2x-latest-denoise3x.pth|realcugan|For 720p+ animation sources"

    # RealESRGAN models
    ["RealESRGAN_x4plus_anime_6B.pth"]="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth|realesrgan|Good fallback for 480p episodes"
    ["RealESRGAN_x2plus.pth"]="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth|realesrgan|For 720p/1080p sources"
    ["RealESRGAN_x4plus.pth"]="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth|realesrgan|General purpose fallback"

    # New RealESRGAN Anime Video models
    ["RealESRGANv2-animevideo-xsx4.pth"]="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-x4plus-anime.pth|realesrgan|Latest anime video model"

    # BasicVSR++ models
    ["BasicVSRPP_x4_vimeo90k.pth"]="https://github.com/ckkelvinchan/BasicVSR_PlusPlus/releases/download/v1.0.0/BasicVSRPP_x4_vimeo90k.pth|basicvsrpp|Good for temporal coherence"

    # Community animation models
    ["AnimeSharp_4x.pth"]="https://huggingface.co/Kim2091/AnimeSharp/resolve/main/4x-AnimeSharp.pth|realesrgan|Community-optimized for sharp animation"
    ["NMKD-Siax_200k.pth"]="https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/8x_NMKD-Siax_200k.pth|realesrgan|Specialized animation upscaler"
)

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [MODEL_NAMES...]

Download AI upscaling models optimized for Futurama processing.

Arguments:
  MODEL_NAMES    Specific models to download (default: download recommended set)

Options:
  --models-dir DIR    Directory to store models (default: ./models)
  --list             List available models
  --recommended      Download recommended set for Futurama
  --all              Download all available models
  --force            Overwrite existing models
  -h, --help         Show this help

Recommended Models for Futurama:
  - RealESRGAN_x4plus_anime_6B.pth (primary for 480p episodes)
  - RealESRGAN_x2plus.pth (for HD content)
  - BasicVSRPP_x4_vimeo90k.pth (alternative method)

Examples:
  $0 --recommended
  $0 --models-dir /data/models RealESRGAN_x4plus_anime_6B.pth
  $0 --list
EOF
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

list_models() {
    echo "Available models:"
    echo
    for model in "${!MODELS[@]}"; do
        IFS='|' read -r url subdir description <<< "${MODELS[$model]}"
        printf "  %-35s %s\n" "$model" "$description"
    done
    echo
    echo "Model storage structure:"
    echo "  models/"
    echo "  ├── realesrgan/"
    echo "  └── basicvsrpp/"
}

download_model() {
    local model_name="$1"
    local force="$2"

    if [[ ! "${MODELS[$model_name]+isset}" ]]; then
        log "ERROR: Unknown model: $model_name"
        return 1
    fi

    IFS='|' read -r url subdir description <<< "${MODELS[$model_name]}"
    local output_dir="$MODELS_DIR/$subdir"
    local output_file="$output_dir/$model_name"

    mkdir -p "$output_dir"

    if [[ -f "$output_file" ]] && [[ "$force" == "false" ]]; then
        log "Model already exists: $output_file (use --force to overwrite)"
        return 0
    fi

    log "Downloading: $model_name"
    log "Description: $description"
    log "URL: $url"
    log "Output: $output_file"

    # Check if URL is accessible
    if ! curl -sf --head "$url" >/dev/null; then
        log "WARNING: URL not accessible: $url"
        log "You may need to download this model manually"
        return 1
    fi

    # Download with progress bar
    if curl -L --progress-bar -o "$output_file.tmp" "$url"; then
        mv "$output_file.tmp" "$output_file"
        log "✓ Downloaded: $model_name ($(du -h "$output_file" | cut -f1))"

        # Verify file integrity (basic check)
        if [[ $(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file") -lt 1000000 ]]; then
            log "WARNING: Downloaded file seems too small, might be corrupted"
        fi

        return 0
    else
        log "✗ Failed to download: $model_name"
        rm -f "$output_file.tmp"
        return 1
    fi
}

get_recommended_models() {
    echo "Real-CUGAN_up4x-latest-conservative.pth"
    echo "Real-CUGAN_up2x-latest-denoise3x.pth"
    echo "RealESRGAN_x4plus_anime_6B.pth"
    echo "RealESRGAN_x2plus.pth"
}

main() {
    local models_to_download=()
    local force=false
    local list_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --models-dir)
                MODELS_DIR="$2"
                shift 2
                ;;
            --list)
                list_only=true
                shift
                ;;
            --recommended)
                mapfile -t models_to_download < <(get_recommended_models)
                shift
                ;;
            --all)
                models_to_download=("${!MODELS[@]}")
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
            *)
                models_to_download+=("$1")
                shift
                ;;
        esac
    done

    if [[ "$list_only" == "true" ]]; then
        list_models
        exit 0
    fi

    # Default to recommended if no models specified
    if [[ ${#models_to_download[@]} -eq 0 ]]; then
        mapfile -t models_to_download < <(get_recommended_models)
        log "No models specified, downloading recommended set for Futurama"
    fi

    log "Starting model downloads"
    log "Models directory: $MODELS_DIR"
    log "Force overwrite: $force"
    log "Models to download: ${models_to_download[*]}"

    # Create models directory structure
    mkdir -p "$MODELS_DIR"/{realesrgan,basicvsrpp}

    # Download each model
    local downloaded=0
    local failed=0

    for model in "${models_to_download[@]}"; do
        if download_model "$model" "$force"; then
            ((downloaded++))
        else
            ((failed++))
        fi
    done

    log "Download summary:"
    log "  Downloaded: $downloaded models"
    log "  Failed: $failed models"

    # Generate model inventory
    local inventory_file="$MODELS_DIR/inventory.txt"
    cat > "$inventory_file" << EOF
Futurama Upscaling Models Inventory
Generated: $(date)

Directory: $MODELS_DIR

Available Models:
EOF

    find "$MODELS_DIR" -name "*.pth" -type f | while read -r model_file; do
        local size
        local rel_path
        size=$(du -h "$model_file" | cut -f1)
        rel_path=$(realpath --relative-to="$MODELS_DIR" "$model_file")
        echo "  $rel_path ($size)" >> "$inventory_file"
    done

    echo "" >> "$inventory_file"
    echo "Usage in env.sh:" >> "$inventory_file"
    echo "  export MODELS_DIR=\"$MODELS_DIR\"" >> "$inventory_file"
    echo "  export MODELS_IN_CONTAINER=false" >> "$inventory_file"

    log "Model inventory created: $inventory_file"

    if [[ $failed -gt 0 ]]; then
        log "WARNING: Some downloads failed. Check the logs above."
        exit 1
    fi

    log "All models downloaded successfully!"
    log "Update your env.sh to use these models:"
    log "  MODELS_DIR=\"$MODELS_DIR\""
    log "  MODELS_IN_CONTAINER=false"
}

main "$@"
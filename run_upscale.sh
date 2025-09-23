#!/usr/bin/env bash
set -euo pipefail

# Configuration
LOG_LEVEL="${LOG_LEVEL:-INFO}"
ENABLE_LOGGING="${ENABLE_LOGGING:-true}"

# Logging function
log() {
    local level="$1"
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ "$ENABLE_LOGGING" != "true" ]]; then
        return 0
    fi

    case "$LOG_LEVEL" in
        "DEBUG") echo "[$timestamp] [run_upscale] [$level] $*" >&2 ;;
        "INFO") [[ "$level" != "DEBUG" ]] && echo "[$timestamp] [run_upscale] [$level] $*" >&2 ;;
        "WARN") [[ "$level" =~ ^(WARN|ERROR)$ ]] && echo "[$timestamp] [run_upscale] [$level] $*" >&2 ;;
        "ERROR") [[ "$level" == "ERROR" ]] && echo "[$timestamp] [run_upscale] [$level] $*" >&2 ;;
    esac
}

# Validation and setup
if [[ $# -lt 1 ]]; then
  log "ERROR" "Usage: $0 <input.mkv> [output.mkv]"
  exit 1
fi

INPUT=$(readlink -f "$1")
BASENAME=$(basename "${INPUT%.*}")
OUTPUT=${2:-"${BASENAME}_4K.mkv"}

log "INFO" "Starting upscale process"
log "INFO" "Input file: $INPUT"
log "INFO" "Output file: $OUTPUT"

# refuse to overwrite the source
if [[ "$OUTPUT" == "$INPUT" ]]; then
  log "ERROR" "Output equals input; refusing to overwrite"
  exit 2
fi

# Load env
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
log "DEBUG" "Script directory: $SCRIPT_DIR"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/env.sh"

log "DEBUG" "Environment loaded successfully"
log "DEBUG" "Docker image: $DOCKER_IMAGE"
log "DEBUG" "Upscale implementation: $UPSCALE_IMPL"

# Basic host-side sanity
if [[ ! -r "$INPUT" ]]; then
  log "ERROR" "Input file not readable on host: $INPUT"
  exit 3
fi

# Get input file info for logging
if command -v ffprobe >/dev/null 2>&1; then
    INPUT_SIZE=$(du -h "$INPUT" 2>/dev/null | cut -f1 || echo "unknown")
    INPUT_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT" 2>/dev/null | cut -d. -f1 || echo "unknown")
    INPUT_RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$INPUT" 2>/dev/null || echo "unknown")

    log "INFO" "Input properties: ${INPUT_RESOLUTION}, ${INPUT_DURATION}s, ${INPUT_SIZE}"
else
    log "DEBUG" "ffprobe not available for input analysis"
fi

# Check available disk space
OUTPUT_DIR=$(dirname "$OUTPUT")
if [[ -d "$OUTPUT_DIR" ]]; then
    AVAILABLE_SPACE=$(df -h "$OUTPUT_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo "unknown")
    log "DEBUG" "Available space in output directory: $AVAILABLE_SPACE"
fi

# Build in-container script with concrete, host-expanded paths
DOCKER_CMD="entrypoint.sh pipeline.vpy \"$INPUT\" \"$OUTPUT\""

log "DEBUG" "Docker command: $DOCKER_CMD"

# Debug view
if [[ "${DEBUG:-0}" == "1" ]]; then
  log "DEBUG" "DOCKER_RUN: $DOCKER_RUN"
  log "DEBUG" "Full command: $DOCKER_RUN bash -c \"$DOCKER_CMD\""
fi

# Track processing time
START_TIME=$(date +%s)
log "INFO" "Starting Docker container for processing"

# Execute with error handling
if $DOCKER_RUN bash -c "$DOCKER_CMD"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    # Get output file info
    if [[ -f "$OUTPUT" ]]; then
        OUTPUT_SIZE=$(du -h "$OUTPUT" 2>/dev/null | cut -f1 || echo "unknown")
        log "INFO" "✓ Processing completed successfully in ${DURATION}s"
        log "INFO" "Output file: $OUTPUT (${OUTPUT_SIZE})"

        # Calculate compression ratio if both sizes available
        if [[ "$INPUT_SIZE" != "unknown" && "$OUTPUT_SIZE" != "unknown" ]]; then
            log "INFO" "Size change: ${INPUT_SIZE} → ${OUTPUT_SIZE}"
        fi
    else
        log "WARN" "Processing reported success but output file not found: $OUTPUT"
        exit 4
    fi
else
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    log "ERROR" "✗ Processing failed after ${DURATION}s"

    # Clean up partial output if it exists
    if [[ -f "$OUTPUT" ]]; then
        log "DEBUG" "Removing partial output file: $OUTPUT"
        rm -f "$OUTPUT"
    fi

    exit 5
fi

log "INFO" "Upscale process completed successfully"

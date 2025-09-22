#!/usr/bin/env bash
set -euo pipefail

# Futurama Box Set Batch Upscaler
# Optimized for processing complete seasons with progress tracking and metadata preservation

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/env.sh"

# Configuration
INPUT_DIR=""
OUTPUT_DIR=""
RESUME_MODE=false
DRY_RUN=false
PARALLEL_JOBS=1
SKIP_EXISTING=true
LOG_LEVEL="INFO"

# Futurama-specific settings
FUTURAMA_PRESETS=(
    "season1-7:480i:CONTENT_TYPE=animation,QTGMC_PRESET=Fast,UPSCALE_IMPL=esrgan,DENOISE_IMPL=none"
    "movies:480p:CONTENT_TYPE=animation,QTGMC_PRESET=Medium,UPSCALE_IMPL=basicvsr,DENOISE_IMPL=bm3d,BM3D_SIGMA=1.0"
    "season8-10:720p:CONTENT_TYPE=animation,QTGMC_PRESET=Fast,UPSCALE_IMPL=esrgan,DENOISE_IMPL=none"
)

usage() {
    cat << EOF
Usage: $0 [OPTIONS] INPUT_DIR OUTPUT_DIR

Batch upscale Futurama episodes with intelligent presets.

Arguments:
  INPUT_DIR     Directory containing .mkv files
  OUTPUT_DIR    Directory for upscaled output

Options:
  -p, --parallel N      Process N files in parallel (default: 1)
  -r, --resume          Resume from last processed file
  -n, --dry-run         Show what would be processed without executing
  -s, --skip-existing   Skip files that already exist in output (default: true)
  -f, --force           Overwrite existing output files
  --preset PRESET       Use specific Futurama preset (season1-7, movies, season8-10)
  --log-level LEVEL     Set log level (DEBUG, INFO, WARN, ERROR)
  -h, --help           Show this help

Futurama Presets:
  season1-7    : 480i interlaced episodes (1999-2003)
  movies       : 480p movies with light denoising
  season8-10   : 720p later episodes (2008-2023)

Examples:
  $0 /media/futurama/season1 /media/output/futurama_4k
  $0 --parallel 2 --preset movies /media/movies /media/output
  $0 --resume --skip-existing /media/input /media/output
EOF
}

log() {
    local level="$1"
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$LOG_LEVEL" in
        "DEBUG") echo "[$timestamp] [$level] $*" ;;
        "INFO") [[ "$level" != "DEBUG" ]] && echo "[$timestamp] [$level] $*" ;;
        "WARN") [[ "$level" =~ ^(WARN|ERROR)$ ]] && echo "[$timestamp] [$level] $*" ;;
        "ERROR") [[ "$level" == "ERROR" ]] && echo "[$timestamp] [$level] $*" ;;
    esac
}

detect_futurama_preset() {
    local file="$1"
    local basename
    basename=$(basename "$file")

    # Auto-detect based on filename patterns and metadata
    if [[ "$basename" =~ [Ss]eason.*0?[1-7] ]] || [[ "$basename" =~ [Ss]0?[1-7][Ee] ]]; then
        echo "season1-7"
    elif [[ "$basename" =~ [Mm]ovie ]] || [[ "$basename" =~ [Bb]ender ]] || [[ "$basename" =~ [Ww]ild ]]; then
        echo "movies"
    elif [[ "$basename" =~ [Ss]eason.*0?[8-9] ]] || [[ "$basename" =~ [Ss]eason.*1[0-1] ]] || [[ "$basename" =~ [Ss]0?[8-9][Ee] ]] || [[ "$basename" =~ [Ss]1[0-1][Ee] ]]; then
        echo "season8-10"
    else
        # Fallback: detect by video properties
        local height
        height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "480")

        if [[ "$height" -le 480 ]]; then
            echo "season1-7"  # Assume early seasons for 480p content
        elif [[ "$height" -le 576 ]]; then
            echo "movies"     # DVDs are often 576p
        else
            echo "season8-10" # HD content
        fi
    fi
}

apply_preset() {
    local preset="$1"

    for preset_config in "${FUTURAMA_PRESETS[@]}"; do
        IFS=':' read -r preset_name resolution settings <<< "$preset_config"
        if [[ "$preset_name" == "$preset" ]]; then
            log "INFO" "Applying preset '$preset' ($resolution): $settings"

            # Parse and export settings
            IFS=',' read -ra SETTING_PAIRS <<< "$settings"
            for setting in "${SETTING_PAIRS[@]}"; do
                IFS='=' read -r key value <<< "$setting"
                export "$key"="$value"
                log "DEBUG" "Set $key=$value"
            done
            return 0
        fi
    done

    log "WARN" "Unknown preset '$preset', using defaults"
    return 1
}

process_file() {
    local input_file="$1"
    local output_file="$2"
    local preset="$3"

    local basename=$(basename "$input_file" .mkv)
    local log_file="$OUTPUT_DIR/logs/${basename}.log"

    mkdir -p "$(dirname "$log_file")"

    log "INFO" "Processing: $basename"
    log "DEBUG" "Input: $input_file"
    log "DEBUG" "Output: $output_file"
    log "DEBUG" "Preset: $preset"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would process $basename with preset $preset"
        return 0
    fi

    # Apply preset settings
    apply_preset "$preset"

    # Track processing time
    local start_time=$(date +%s)

    # Run the upscaler with logging
    if "$SCRIPT_DIR/run_upscale.sh" "$input_file" "$output_file" 2>&1 | tee "$log_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log "INFO" "✓ Completed $basename in ${duration}s"

        # Add metadata about processing
        echo "# Upscaling completed at $(date)" >> "$log_file"
        echo "# Duration: ${duration} seconds" >> "$log_file"
        echo "# Preset: $preset" >> "$log_file"

        return 0
    else
        log "ERROR" "✗ Failed to process $basename"
        return 1
    fi
}

create_progress_file() {
    local progress_file="$OUTPUT_DIR/.futurama_progress"

    if [[ ! -f "$progress_file" ]] || [[ "$RESUME_MODE" == "false" ]]; then
        find "$INPUT_DIR" -name "*.mkv" -type f | sort > "$progress_file.todo"
        touch "$progress_file.done"
        log "INFO" "Created progress tracking files"
    fi
}

get_remaining_files() {
    local progress_file="$OUTPUT_DIR/.futurama_progress"
    local todo_file="$progress_file.todo"
    local done_file="$progress_file.done"

    if [[ -f "$done_file" ]]; then
        comm -23 <(sort "$todo_file") <(sort "$done_file")
    else
        cat "$todo_file"
    fi
}

mark_file_done() {
    local input_file="$1"
    local progress_file="$OUTPUT_DIR/.futurama_progress"
    echo "$input_file" >> "$progress_file.done"
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--parallel)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -r|--resume)
                RESUME_MODE=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--skip-existing)
                SKIP_EXISTING=true
                shift
                ;;
            -f|--force)
                SKIP_EXISTING=false
                shift
                ;;
            --preset)
                MANUAL_PRESET="$2"
                shift 2
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
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
                if [[ -z "$INPUT_DIR" ]]; then
                    INPUT_DIR="$1"
                elif [[ -z "$OUTPUT_DIR" ]]; then
                    OUTPUT_DIR="$1"
                else
                    echo "Too many arguments" >&2
                    usage >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate arguments
    if [[ -z "$INPUT_DIR" ]] || [[ -z "$OUTPUT_DIR" ]]; then
        echo "Error: INPUT_DIR and OUTPUT_DIR are required" >&2
        usage >&2
        exit 1
    fi

    if [[ ! -d "$INPUT_DIR" ]]; then
        echo "Error: Input directory does not exist: $INPUT_DIR" >&2
        exit 1
    fi

    mkdir -p "$OUTPUT_DIR/logs"

    log "INFO" "Starting Futurama batch upscaling"
    log "INFO" "Input: $INPUT_DIR"
    log "INFO" "Output: $OUTPUT_DIR"
    log "INFO" "Parallel jobs: $PARALLEL_JOBS"
    log "INFO" "Resume mode: $RESUME_MODE"
    log "INFO" "Skip existing: $SKIP_EXISTING"

    # Initialize progress tracking
    create_progress_file

    # Get list of files to process
    mapfile -t files_to_process < <(get_remaining_files)

    if [[ ${#files_to_process[@]} -eq 0 ]]; then
        log "INFO" "No files to process!"
        exit 0
    fi

    log "INFO" "Found ${#files_to_process[@]} files to process"

    # Process files
    local processed=0
    local failed=0
    local skipped=0

    for input_file in "${files_to_process[@]}"; do
        local basename=$(basename "$input_file" .mkv)
        local output_file="$OUTPUT_DIR/${basename}_4K.mkv"

        # Skip if output exists and skip mode enabled
        if [[ "$SKIP_EXISTING" == "true" ]] && [[ -f "$output_file" ]]; then
            log "INFO" "⏭ Skipping existing: $basename"
            mark_file_done "$input_file"
            ((skipped++))
            continue
        fi

        # Detect or use manual preset
        local preset="${MANUAL_PRESET:-$(detect_futurama_preset "$input_file")}"

        # Process the file
        if process_file "$input_file" "$output_file" "$preset"; then
            mark_file_done "$input_file"
            ((processed++))
        else
            ((failed++))
        fi

        # Progress update
        local total=$((processed + failed + skipped))
        log "INFO" "Progress: $total/${#files_to_process[@]} (✓$processed ✗$failed ⏭$skipped)"
    done

    log "INFO" "Batch processing complete!"
    log "INFO" "Processed: $processed files"
    log "INFO" "Failed: $failed files"
    log "INFO" "Skipped: $skipped files"

    # Generate summary report
    cat > "$OUTPUT_DIR/batch_summary.txt" << EOF
Futurama Batch Upscaling Summary
Generated: $(date)

Input Directory: $INPUT_DIR
Output Directory: $OUTPUT_DIR

Results:
- Successfully processed: $processed files
- Failed: $failed files
- Skipped (existing): $skipped files
- Total files: ${#files_to_process[@]}

Settings Used:
- Parallel jobs: $PARALLEL_JOBS
- Resume mode: $RESUME_MODE
- Skip existing: $SKIP_EXISTING
- Manual preset: ${MANUAL_PRESET:-"auto-detected"}

Individual logs available in: $OUTPUT_DIR/logs/
EOF

    if [[ $failed -gt 0 ]]; then
        exit 1
    fi
}

# Handle Ctrl+C gracefully
trap 'log "WARN" "Interrupted by user"; exit 130' INT

main "$@"
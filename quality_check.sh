#!/usr/bin/env bash
set -euo pipefail

# Quality Control Script for Futurama Upscaling
# Validates output files and generates comparison reports

# SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"  # Currently unused

usage() {
    cat << EOF
Usage: $0 [OPTIONS] ORIGINAL UPSCALED

Compare original and upscaled video files for quality assessment.

Arguments:
  ORIGINAL     Path to original video file
  UPSCALED     Path to upscaled video file

Options:
  --output-dir DIR     Directory for comparison outputs (default: ./comparisons)
  --sample-time TIME   Time for sample extraction (default: 300s)
  --sample-duration N  Duration of sample clip (default: 30s)
  --generate-thumbs    Generate thumbnail comparison grid
  --psnr               Calculate PSNR metrics
  --ssim               Calculate SSIM metrics
  -h, --help          Show this help

Examples:
  $0 original.mkv upscaled_4K.mkv
  $0 --generate-thumbs --psnr original.mkv upscaled.mkv
EOF
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

extract_sample() {
    local input="$1"
    local output="$2"
    local start_time="$3"
    local duration="$4"

    log "Extracting ${duration}s sample from $input at ${start_time}s"

    ffmpeg -hide_banner -loglevel error -y \
        -ss "$start_time" -i "$input" -t "$duration" \
        -c:v libx264 -preset fast -crf 18 \
        -c:a copy \
        "$output"
}

generate_thumbnails() {
    local input="$1"
    local output_pattern="$2"
    local count="$3"

    log "Generating $count thumbnails from $input"

    ffmpeg -hide_banner -loglevel error -y \
        -i "$input" \
        -vf "select=not(mod(n\\,$(($(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of default=noprint_wrappers=1:nokey=1 "$input") / count)))),scale=640:480" \
        -vsync vfr -q:v 2 \
        "$output_pattern"
}

create_comparison_grid() {
    local original_pattern="$1"
    local upscaled_pattern="$2"
    local output="$3"

    log "Creating comparison grid: $output"

    # Create side-by-side comparison grid using ImageMagick
    if command -v montage >/dev/null; then
        montage \
            \( "$original_pattern" -label "Original" \) \
            \( "$upscaled_pattern" -label "Upscaled 4K" \) \
            -tile 2x -geometry +5+5 -background black -fill white \
            "$output"
    else
        log "WARNING: ImageMagick not available, skipping thumbnail grid"
    fi
}

calculate_metrics() {
    local original="$1"
    local upscaled="$2"
    local output_dir="$3"
    local metrics="$4"

    log "Calculating video quality metrics: $metrics"

    # Scale both videos to same resolution for comparison
    local temp_original="$output_dir/temp_original_scaled.mkv"
    local temp_upscaled="$output_dir/temp_upscaled_scaled.mkv"

    # Get upscaled dimensions
    local upscaled_width
    local upscaled_height
    upscaled_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$upscaled")
    upscaled_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$upscaled")

    # Scale original to match upscaled resolution
    ffmpeg -hide_banner -loglevel error -y \
        -i "$original" -t 30 \
        -vf "scale=${upscaled_width}:${upscaled_height}:flags=lanczos" \
        -c:v libx264 -preset fast -crf 18 \
        "$temp_original"

    # Extract same duration from upscaled
    ffmpeg -hide_banner -loglevel error -y \
        -i "$upscaled" -t 30 \
        -c:v libx264 -preset fast -crf 18 \
        "$temp_upscaled"

    local metrics_file="$output_dir/quality_metrics.txt"

    if [[ "$metrics" =~ psnr ]]; then
        log "Calculating PSNR..."
        ffmpeg -hide_banner -loglevel error \
            -i "$temp_original" -i "$temp_upscaled" \
            -lavfi "psnr=stats_file=$output_dir/psnr_stats.log" \
            -f null - 2>/dev/null

        if [[ -f "$output_dir/psnr_stats.log" ]]; then
            local avg_psnr=$(awk 'END {print $5}' "$output_dir/psnr_stats.log" | cut -d: -f2)
            echo "Average PSNR: ${avg_psnr:-"N/A"} dB" >> "$metrics_file"
        fi
    fi

    if [[ "$metrics" =~ ssim ]]; then
        log "Calculating SSIM..."
        ffmpeg -hide_banner -loglevel error \
            -i "$temp_original" -i "$temp_upscaled" \
            -lavfi "ssim=stats_file=$output_dir/ssim_stats.log" \
            -f null - 2>/dev/null

        if [[ -f "$output_dir/ssim_stats.log" ]]; then
            local avg_ssim=$(awk 'END {print $2}' "$output_dir/ssim_stats.log" | cut -d: -f2)
            echo "Average SSIM: ${avg_ssim:-"N/A"}" >> "$metrics_file"
        fi
    fi

    # Cleanup temp files
    rm -f "$temp_original" "$temp_upscaled"
}

generate_report() {
    local original="$1"
    local upscaled="$2"
    local output_dir="$3"

    local report_file="$output_dir/quality_report.txt"

    cat > "$report_file" << EOF
Futurama Upscaling Quality Report
Generated: $(date)

Files Compared:
Original: $original
Upscaled: $upscaled

Original Video Info:
$(ffprobe -v error -show_entries stream=width,height,r_frame_rate,duration,bit_rate -select_streams v:0 "$original" 2>/dev/null | grep -E "(width|height|r_frame_rate|duration|bit_rate)" | sed 's/^/  /')

Upscaled Video Info:
$(ffprobe -v error -show_entries stream=width,height,r_frame_rate,duration,bit_rate -select_streams v:0 "$upscaled" 2>/dev/null | grep -E "(width|height|r_frame_rate|duration|bit_rate)" | sed 's/^/  /')

File Sizes:
  Original: $(du -h "$original" | cut -f1)
  Upscaled: $(du -h "$upscaled" | cut -f1)
  Size Ratio: $(echo "scale=2; $(stat -f%z "$upscaled") / $(stat -f%z "$original")" | bc -l)x

EOF

    if [[ -f "$output_dir/quality_metrics.txt" ]]; then
        echo "Quality Metrics:" >> "$report_file"
        sed 's/^/  /' "$output_dir/quality_metrics.txt" >> "$report_file"
    fi

    echo "" >> "$report_file"
    echo "Output Directory: $output_dir" >> "$report_file"
    echo "- Sample clips: sample_original.mkv, sample_upscaled.mkv" >> "$report_file"
    echo "- Thumbnails: thumbs_original_*.jpg, thumbs_upscaled_*.jpg" >> "$report_file"
    echo "- Comparison grid: comparison_grid.jpg" >> "$report_file"

    log "Quality report generated: $report_file"
}

main() {
    local original=""
    local upscaled=""
    local output_dir="./comparisons"
    local sample_time="300"
    local sample_duration="30"
    local generate_thumbs=false
    local calculate_psnr=false
    local calculate_ssim=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            --sample-time)
                sample_time="$2"
                shift 2
                ;;
            --sample-duration)
                sample_duration="$2"
                shift 2
                ;;
            --generate-thumbs)
                generate_thumbs=true
                shift
                ;;
            --psnr)
                calculate_psnr=true
                shift
                ;;
            --ssim)
                calculate_ssim=true
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
                if [[ -z "$original" ]]; then
                    original="$1"
                elif [[ -z "$upscaled" ]]; then
                    upscaled="$1"
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
    if [[ -z "$original" ]] || [[ -z "$upscaled" ]]; then
        echo "Error: Both ORIGINAL and UPSCALED files are required" >&2
        usage >&2
        exit 1
    fi

    if [[ ! -f "$original" ]]; then
        echo "Error: Original file does not exist: $original" >&2
        exit 1
    fi

    if [[ ! -f "$upscaled" ]]; then
        echo "Error: Upscaled file does not exist: $upscaled" >&2
        exit 1
    fi

    mkdir -p "$output_dir"

    log "Starting quality comparison"
    log "Original: $original"
    log "Upscaled: $upscaled"
    log "Output: $output_dir"

    # Extract sample clips
    extract_sample "$original" "$output_dir/sample_original.mkv" "$sample_time" "$sample_duration"
    extract_sample "$upscaled" "$output_dir/sample_upscaled.mkv" "$sample_time" "$sample_duration"

    # Generate thumbnails if requested
    if [[ "$generate_thumbs" == "true" ]]; then
        generate_thumbnails "$original" "$output_dir/thumbs_original_%03d.jpg" 6
        generate_thumbnails "$upscaled" "$output_dir/thumbs_upscaled_%03d.jpg" 6

        # Create comparison grid
        create_comparison_grid "$output_dir/thumbs_original_*.jpg" "$output_dir/thumbs_upscaled_*.jpg" "$output_dir/comparison_grid.jpg"
    fi

    # Calculate metrics if requested
    local metrics=""
    [[ "$calculate_psnr" == "true" ]] && metrics="${metrics}psnr "
    [[ "$calculate_ssim" == "true" ]] && metrics="${metrics}ssim "

    if [[ -n "$metrics" ]]; then
        calculate_metrics "$original" "$upscaled" "$output_dir" "$metrics"
    fi

    # Generate final report
    generate_report "$original" "$upscaled" "$output_dir"

    log "Quality comparison complete!"
    log "Results available in: $output_dir"
}

main "$@"
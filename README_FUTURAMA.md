# Futurama Box Set Upscaling Guide

Complete workflow for upscaling your Futurama collection from 480p/720p to 4K using AI-powered video enhancement.

## Quick Start

### 1. Setup Models
```bash
# Download optimal models for animation
./download_models.sh --recommended

# Or manually specify models directory
./download_models.sh --models-dir /path/to/models RealESRGAN_x4plus_anime_6B.pth
```

### 2. Configure Environment
```bash
# Load Futurama-optimized settings
source env_futurama.sh

# Auto-configure based on your content
auto_configure /path/to/futurama/collection

# Or manually configure for specific seasons
configure_for_season "early"    # Seasons 1-7 (1999-2003)
configure_for_season "movies"   # Movies
configure_for_season "later"    # Seasons 8+ (2008+)
```

### 3. Process Content
```bash
# Single file
./run_upscale.sh "Futurama S01E01.mkv" "Futurama S01E01_4K.mkv"

# Batch processing with progress tracking
./batch_futurama.sh /media/futurama/input /media/futurama/4k_output

# Parallel processing (2 files at once)
./batch_futurama.sh --parallel 2 /input /output
```

## Content-Specific Configurations

### Early Seasons (1999-2003)
**Characteristics**: 480i interlaced, 4:3 aspect ratio, film-like animation

```bash
configure_for_season "early"
# - Uses QTGMC Fast deinterlacing
# - RealESRGAN x4 anime model
# - No denoising (clean animation)
# - 4x upscale: 640x480 → 2560x1920
```

### Movies (2007-2009)
**Characteristics**: Higher quality film transfers, some 16:9

```bash
configure_for_season "movies"
# - QTGMC Medium for higher quality
# - BasicVSR++ for temporal coherence
# - Light BM3D denoising
# - Larger processing tiles
```

### Later Seasons (2008+)
**Characteristics**: 720p HD, progressive, 16:9

```bash
configure_for_season "later"
# - Skip deinterlacing (progressive)
# - 3x upscale: 1280x720 → 3840x2160
# - Optimized for HD sources
```

## Batch Processing Features

### Progress Tracking
- Automatic resume functionality
- Skip existing files
- Detailed logging per episode
- Progress monitoring

### Quality Presets
```bash
configure_for_quality "archive"   # Best quality, slower
configure_for_quality "balanced"  # Default quality/speed
configure_for_quality "fast"      # Quick processing
```

### File Organization
```
output/
├── logs/                    # Processing logs per file
├── .futurama_progress.todo  # Files to process
├── .futurama_progress.done  # Completed files
└── batch_summary.txt        # Final summary report
```

## Quality Control

### Compare Results
```bash
# Generate quality comparison
./quality_check.sh original.mkv upscaled_4K.mkv

# With thumbnails and metrics
./quality_check.sh --generate-thumbs --psnr original.mkv upscaled.mkv
```

### Monitor Processing
```bash
# Run monitoring in background
docker-compose --profile monitor up -d monitor

# Check logs
docker-compose logs -f monitor
```

## Docker Compose Workflow

### Simple Setup
```bash
# Configure your paths
export FUTURAMA_INPUT_DIR="/media/futurama"
export FUTURAMA_OUTPUT_DIR="/media/futurama_4k"
export MODELS_DIR="/data/ai_models"

# Start container
docker-compose up -d upscaler

# Enter container for processing
docker-compose exec upscaler bash

# Inside container:
source env_futurama.sh
auto_configure /input
./batch_futurama.sh /input /output
```

### With Monitoring
```bash
# Start with monitoring
docker-compose --profile monitor up -d

# Check progress
docker-compose logs monitor
```

## Recommended Models

### Primary (Required)
- **RealESRGAN_x4plus_anime_6B.pth** - Best for 480p Futurama episodes
- **RealESRGAN_x2plus.pth** - For 720p+ sources

### Secondary (Optional)
- **BasicVSRPP_x4_vimeo90k.pth** - Alternative method, better temporal coherence
- **RealESRGAN_x4plus.pth** - General fallback

## Performance Optimization

### GPU Memory Management
```bash
# For 8GB+ VRAM
export ESRGAN_TILE=512

# For 6-8GB VRAM
export ESRGAN_TILE=384

# For 4GB VRAM
export ESRGAN_TILE=256
```

### Processing Speed
```bash
# Fastest (lower quality)
configure_for_quality "fast"
export QTGMC_PRESET="Fast"
export FFMPEG_PRESET="p1"

# Balanced
configure_for_quality "balanced"

# Best quality (slower)
configure_for_quality "archive"
export QTGMC_PRESET="Slow"
```

## Troubleshooting

### Common Issues

**Source loading failures**: Check `entrypoint.sh` logs for plugin availability
```bash
# Container will show available source plugins on startup
docker-compose exec upscaler bash -c "python3 -c 'import vapoursynth as vs; print(vs.core.get_plugins())'"
```

**Out of memory**: Reduce tile sizes
```bash
export ESRGAN_TILE=192
export BASICVSR_TILE_W=256
export BASICVSR_TILE_H=256
```

**Aspect ratio issues**: Modern fixes handle this automatically
```bash
# Shows detected and target resolutions
./run_upscale.sh input.mkv output.mkv
# [container] Source: 640x480 (4:3)
# [container] Target: 2560x1920 (4x upscale)
```

### Quality Issues

**Over-sharpening**: Reduce sharpness in QTGMC
```bash
# In pipeline.vpy, QTGMC sharpness is set to 0.2 for animation
# Reduce if content appears over-sharpened
```

**Temporal artifacts**: Try BasicVSR instead of RealESRGAN
```bash
export UPSCALE_IMPL="basicvsr"
```

## File Naming Conventions

The batch processor maintains original naming with `_4K` suffix:
```
Futurama S01E01 Space Pilot 3000.mkv → Futurama S01E01 Space Pilot 3000_4K.mkv
Futurama Movie 1.mkv → Futurama Movie 1_4K.mkv
```

## Expected Processing Times

**Per Episode** (varies by hardware):
- 480p episode (22min): 30-60 minutes on RTX 3080
- 720p episode: 45-90 minutes
- Movie (90min): 2-4 hours

**Full Collection Estimate**:
- Seasons 1-7 (140 episodes): ~70-140 hours
- Movies (4 films): ~8-16 hours
- Seasons 8-10 (39 episodes): ~30-60 hours

## Storage Requirements

**Estimated Output Sizes**:
- 480p episode → 4K: 500MB → 3-5GB
- 720p episode → 4K: 1GB → 4-6GB
- Movie → 4K: 2GB → 10-15GB

**Total Collection**: ~800GB - 1.2TB for complete Futurama box set

## Advanced Usage

### Custom Presets
```bash
# Create custom configuration
export CONTENT_TYPE="animation"
export QTGMC_PRESET="Medium"
export UPSCALE_IMPL="basicvsr"
export DENOISE_IMPL="bm3d"
export BM3D_SIGMA=1.0
export FFMPEG_CQ=16  # Higher quality

./run_upscale.sh input.mkv output.mkv
```

### A/B Testing
```bash
# Compare different upscaling methods
./ab_upscalers.sh "Futurama S01E01.mkv"
# Outputs: S01E01_ESRGAN_4K.mkv and S01E01_BasicVSR_4K.mkv

# Then compare quality
./quality_check.sh --generate-thumbs S01E01_ESRGAN_4K.mkv S01E01_BasicVSR_4K.mkv
```

Happy upscaling! 🚀
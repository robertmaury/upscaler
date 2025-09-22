# AI Video Upscaler for Animation Content

Complete Docker-based workflow for upscaling animated content from 480p/720p to 4K using state-of-the-art AI models, optimized specifically for animation and Futurama box sets.

## Features

- **Real-CUGAN Integration** - Superior AI upscaling specifically designed for animation
- **Multi-Model Support** - RealESRGAN, BasicVSR++, and Real-CUGAN with automatic fallbacks
- **Intelligent Deinterlacing** - QTGMC with IVTC telecine detection for interlaced sources
- **Aspect Ratio Preservation** - Maintains original 4:3 or 16:9 ratios automatically
- **Batch Processing** - Process entire collections with progress tracking and resume
- **GPU Acceleration** - NVIDIA NVENC encoding and CUDA-accelerated upscaling
- **Quality Control** - Automated comparison tools with PSNR/SSIM metrics

## Quick Start

### 1. Setup Models
```bash
# Download animation-optimized models (includes Real-CUGAN)
./download_models.sh --recommended

# List all available models
./download_models.sh --list
```

### 2. Configure Environment
```bash
# Load animation-optimized settings
source env_futurama.sh

# Auto-configure based on your content
auto_configure /path/to/video/collection

# Or manually configure for specific content types
configure_for_season "early"    # 480i interlaced (1999-2003)
configure_for_season "movies"   # High-quality film sources
configure_for_season "later"    # 720p+ HD progressive
```

### 3. Process Content
```bash
# Single file with Real-CUGAN (best for animation)
export UPSCALE_IMPL="realcugan"
./run_upscale.sh "input.mkv" "output_4K.mkv"

# Batch processing with progress tracking
./batch_futurama.sh /input/directory /output/directory

# Parallel processing (2 files simultaneously)
./batch_futurama.sh --parallel 2 /input /output
```

## AI Upscaling Models

### Real-CUGAN (Recommended for Animation)
**Best choice for animated content** - Specifically trained on animation data.

```bash
export UPSCALE_IMPL="realcugan"
export REALCUGAN_MODEL_NAME="up4x-latest-conservative.pth"
```

**Advantages:**
- Superior edge preservation for animation
- Minimal artifacts on flat colored areas
- Optimized for cartoon/anime aesthetics
- Conservative upscaling reduces over-sharpening

### RealESRGAN (Versatile)
General-purpose model with excellent animation support.

```bash
export UPSCALE_IMPL="esrgan"
export ESRGAN_MODEL_NAME="RealESRGAN_x4plus_anime_6B.pth"
```

### BasicVSR++ (Temporal Coherence)
Best for temporal consistency across frames.

```bash
export UPSCALE_IMPL="basicvsr"
export BASICVSR_MODEL_NAME="BasicVSRPP_x4_vimeo90k.pth"
```

## Content-Specific Configurations

### Early Animated Series (480i Interlaced)
For content like Futurama Seasons 1-7, classic cartoons.

```bash
configure_for_season "early"
# - Real-CUGAN upscaling (best for animation)
# - QTGMC Fast deinterlacing
# - IVTC telecine detection
# - 4x upscale: 640x480 → 2560x1920
# - No denoising (preserves animation clarity)
```

### Animation Movies (Film Sources)
Higher quality film transfers, potentially 16:9.

```bash
configure_for_season "movies"
# - Real-CUGAN or BasicVSR++ (temporal coherence)
# - QTGMC Medium for higher quality
# - Light BM3D denoising for film grain
# - Larger processing tiles for quality
```

### Modern HD Animation (720p+)
Progressive HD animated content.

```bash
configure_for_season "later"
# - Skip deinterlacing (progressive source)
# - RealESRGAN or Real-CUGAN
# - 3x upscale: 1280x720 → 3840x2160
# - Optimized for HD sources
```

## Advanced Features

### A/B Testing Different Models
```bash
# Compare Real-CUGAN vs RealESRGAN vs BasicVSR++
./ab_upscalers.sh "input_episode.mkv"
# Outputs: episode_REALCUGAN_4K.mkv, episode_ESRGAN_4K.mkv, episode_BasicVSR_4K.mkv

# Generate quality comparison
./quality_check.sh --generate-thumbs --psnr episode_REALCUGAN_4K.mkv episode_ESRGAN_4K.mkv
```

### Quality Control
```bash
# Comprehensive quality analysis
./quality_check.sh original.mkv upscaled_4K.mkv

# With thumbnails and metrics
./quality_check.sh --generate-thumbs --ssim --psnr original.mkv upscaled.mkv

# Outputs:
# - comparison_grid.jpg (side-by-side thumbnails)
# - quality_metrics.txt (PSNR/SSIM scores)
# - sample clips for manual review
```

### Batch Processing Features

**Progress Tracking:**
- Automatic resume from interruptions
- Skip existing files option
- Per-file logging
- Progress monitoring

**Example Batch Workflow:**
```bash
# Setup batch processing
./batch_futurama.sh --resume --parallel 2 /media/anime /media/anime_4k

# Monitor progress
tail -f /media/anime_4k/logs/*.log

# Generate summary report
cat /media/anime_4k/batch_summary.txt
```

## Performance Optimization

### GPU Memory Management
```bash
# RTX 3090 (24GB) - Maximum quality
export ESRGAN_TILE=768
export REALCUGAN_TILE=512
export BASICVSR_TILE_W=512
export BASICVSR_TILE_H=512

# RTX 3080 (10GB) - Balanced
export ESRGAN_TILE=512
export REALCUGAN_TILE=384
export BASICVSR_TILE_W=384
export BASICVSR_TILE_H=384

# RTX 3070 (8GB) - Conservative
export ESRGAN_TILE=384
export REALCUGAN_TILE=256
export BASICVSR_TILE_W=256
export BASICVSR_TILE_H=256
```

### Processing Speed vs Quality
```bash
# Maximum quality (slowest)
configure_for_quality "archive"
export QTGMC_PRESET="Slow"
export FFMPEG_CQ=15
export FFMPEG_PRESET="p7"

# Balanced (recommended)
configure_for_quality "balanced"
export QTGMC_PRESET="Medium"
export FFMPEG_CQ=18
export FFMPEG_PRESET="p5"

# Fast preview (lower quality)
configure_for_quality "fast"
export QTGMC_PRESET="Fast"
export FFMPEG_CQ=22
export FFMPEG_PRESET="p1"
```

## Docker Usage

### Prerequisites
```bash
# Install NVIDIA Container Toolkit (Ubuntu 24.04)
sudo apt install nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### Container Management
```bash
# Build container
docker build -t anime-upscaler .

# Run interactive session
docker run --rm --gpus all -it \
  -v /path/to/videos:/input:ro \
  -v /path/to/output:/output \
  -v /path/to/models:/models:ro \
  anime-upscaler bash

# Inside container
source env_futurama.sh
auto_configure /input
./batch_futurama.sh /input /output
```

## Model Recommendations

### Primary Models (Download First)
- **Real-CUGAN up4x-latest-conservative.pth** - Best for animation upscaling
- **Real-CUGAN up2x-latest-denoise3x.pth** - For 720p+ sources
- **RealESRGAN_x4plus_anime_6B.pth** - Excellent fallback for animation

### Secondary Models (Optional)
- **BasicVSRPP_x4_vimeo90k.pth** - Best temporal coherence
- **AnimeSharp_4x.pth** - Community-optimized for sharp animation
- **RealESRGAN_x2plus.pth** - For HD content

```bash
# Download all recommended models
./download_models.sh --recommended

# Download specific models
./download_models.sh Real-CUGAN_up4x-latest-conservative.pth RealESRGAN_x4plus_anime_6B.pth
```

## Troubleshooting

### Common Issues

**Real-CUGAN Not Working:**
```bash
# Check Real-CUGAN installation
docker run --rm --gpus all anime-upscaler python3 -c "import vsrealcugan; print('Real-CUGAN OK')"

# Fallback to RealESRGAN
export UPSCALE_IMPL="esrgan"
```

**Out of GPU Memory:**
```bash
# Reduce tile sizes
export REALCUGAN_TILE=192
export ESRGAN_TILE=256
export BASICVSR_TILE_W=192
export BASICVSR_TILE_H=192
```

**Source Loading Failures:**
```bash
# Check available source plugins
python3 -c "import vapoursynth as vs; print([p.name for p in vs.core.get_plugins().values()])"

# BestSource should be available as fallback
```

**Aspect Ratio Issues:**
The system automatically preserves aspect ratios. Check logs for resolution detection:
```
[container] Source: 640x480 (4:3) → Target: 2560x1920 (4x scale)
[container] Source: 1280x720 (16:9) → Target: 3840x2160 (3x scale)
```

### Quality Issues

**Over-sharpening with Real-CUGAN:**
```bash
# Use conservative model
export REALCUGAN_MODEL_NAME="up4x-latest-conservative.pth"

# Or try noise-reduction variant
export REALCUGAN_MODEL_NAME="up2x-latest-denoise3x.pth"
```

**Temporal Artifacts:**
```bash
# Switch to BasicVSR++ for better temporal coherence
export UPSCALE_IMPL="basicvsr"
export BASICVSR_MODEL_NAME="BasicVSRPP_x4_vimeo90k.pth"
```

## Performance Benchmarks

### Processing Times (RTX 3090)
**Per Episode (22 minutes):**
- Real-CUGAN (480p→4K): 25-40 minutes
- RealESRGAN (480p→4K): 30-50 minutes
- BasicVSR++ (480p→4K): 45-75 minutes

**Per Movie (90 minutes):**
- Real-CUGAN: 1.5-3 hours
- RealESRGAN: 2-4 hours
- BasicVSR++: 3-6 hours

### Storage Requirements
**Output Sizes (4K H.265):**
- 480p episode (22min): 500MB → 3-5GB
- 720p episode (22min): 1GB → 4-6GB
- Movie (90min): 2GB → 10-15GB

## Advanced Customization

### Custom Model Integration
```bash
# Add your own models to the models directory
export CUSTOM_MODEL="/models/realesrgan/MyCustomModel.pth"
export ESRGAN_MODEL="$CUSTOM_MODEL"
```

### Pipeline Modifications
Edit `pipeline.vpy` to customize the VapourSynth processing chain:
- Deinterlacing parameters
- Upscaling tile sizes
- Color space handling
- Denoising settings

### Environment Variables
```bash
# Core upscaling
UPSCALE_IMPL=realcugan|esrgan|basicvsr
REALCUGAN_MODEL_NAME=up4x-latest-conservative.pth
ESRGAN_MODEL_NAME=RealESRGAN_x4plus_anime_6B.pth

# Processing settings
CONTENT_TYPE=animation
QTGMC_PRESET=Fast|Medium|Slow
DENOISE_IMPL=none|bm3d
IVTC=0|1

# Encoding
FFMPEG_VCODEC=hevc_nvenc
FFMPEG_PRESET=p1|p3|p5|p7
FFMPEG_CQ=15-25
```

## System Requirements

### Minimum
- NVIDIA GPU with 6GB+ VRAM (GTX 1060, RTX 2060)
- 16GB RAM
- Ubuntu 20.04+ with NVIDIA drivers 470+
- Docker with NVIDIA Container Toolkit

### Recommended
- NVIDIA RTX 3080/3090/4080/4090 (10GB+ VRAM)
- 32GB+ RAM
- NVMe SSD for temporary files
- Ubuntu 22.04/24.04 with latest drivers

### Supported Architectures
- CUDA Compute Capability 6.1+ (GTX 10 series and newer)
- RTX 20/30/40 series fully supported
- Optimized for RTX 3090 (24GB) and RTX 4090 (24GB)

Happy upscaling! 🚀✨

---

*For specific Futurama box set processing, see the detailed configuration examples using `env_futurama.sh` and `batch_futurama.sh`.*
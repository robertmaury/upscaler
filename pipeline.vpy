# pipeline.vpy (safer source + self‑healing tivtc)
import os, sys, glob
import vapoursynth as vs
import havsfunc as haf
core = vs.core

if len(sys.argv) < 2:
    raise SystemExit("Usage: vspipe pipeline.vpy <input.mkv>")

SRC = sys.argv[1]
SOURCE_IMPL = os.environ.get("SOURCE_IMPL", "ffms2").lower()  # ffms2|lsmas|bestsource
try:
    IVTC = int(os.environ.get("IVTC", "1"))
except (ValueError, TypeError):
    IVTC = 1
DENOISE_IMPL = os.environ.get("DENOISE_IMPL", "none").lower()
UPSCALE_IMPL = os.environ.get("UPSCALE_IMPL", "esrgan").lower()
CONTENT_TYPE = os.environ.get("CONTENT_TYPE", "animation").lower()
QTGMC_PRESET = os.environ.get("QTGMC_PRESET", "Fast")

# ---------- Source with fallback ----------
def load_source(path: str):
    impl_order = {
        "ffms2": ["ffms2", "lsmas", "bestsource"],
        "lsmas": ["lsmas", "ffms2", "bestsource"],
        "bestsource": ["bestsource", "ffms2", "lsmas"],
    }.get(SOURCE_IMPL, ["ffms2", "lsmas", "bestsource"])

    errors = {}
    for impl in impl_order:
        try:
            if impl == "ffms2" and hasattr(core, "ffms2"):
                print(f"[pipeline] Trying ffms2...")
                try:
                    # Try with default settings first
                    clip = core.ffms2.Source(path)
                    print(f"[pipeline] Successfully loaded with ffms2: {clip.width}x{clip.height}, {clip.num_frames} frames")
                    return clip
                except Exception as ffms_err:
                    # Try with alternative settings for problematic files
                    print(f"[pipeline] ffms2 default failed ({ffms_err}), trying alternative settings...")
                    try:
                        # Force index recreation and use different threading
                        clip = core.ffms2.Source(path, cachedir="", threads=1)
                        print(f"[pipeline] Successfully loaded with ffms2 (alternative): {clip.width}x{clip.height}, {clip.num_frames} frames")
                        return clip
                    except Exception as ffms_err2:
                        raise Exception(f"ffms2 failed with both default ({ffms_err}) and alternative ({ffms_err2}) settings")

            elif impl == "lsmas" and hasattr(core, "lsmas"):
                print(f"[pipeline] Trying l-smash...")
                try:
                    # Try default l-smash settings
                    clip = core.lsmas.LWLibavSource(path)
                    print(f"[pipeline] Successfully loaded with l-smash: {clip.width}x{clip.height}, {clip.num_frames} frames")
                    return clip
                except Exception as lsmas_err:
                    # Try with alternative l-smash settings
                    print(f"[pipeline] l-smash default failed ({lsmas_err}), trying alternative settings...")
                    try:
                        # Try with different threading and caching
                        clip = core.lsmas.LWLibavSource(path, threads=1, cache=0)
                        print(f"[pipeline] Successfully loaded with l-smash (alternative): {clip.width}x{clip.height}, {clip.num_frames} frames")
                        return clip
                    except Exception as lsmas_err2:
                        try:
                            # Last resort: minimal settings
                            clip = core.lsmas.LibavSMASHSource(path)
                            print(f"[pipeline] Successfully loaded with LibavSMASHSource: {clip.width}x{clip.height}, {clip.num_frames} frames")
                            return clip
                        except Exception as lsmas_err3:
                            raise Exception(f"l-smash failed with LWLibavSource ({lsmas_err}), LWLibavSource-alt ({lsmas_err2}), and LibavSMASHSource ({lsmas_err3})")

            elif impl == "bestsource" and hasattr(core, "bs"):
                print(f"[pipeline] Trying BestSource...")

                # Try different BestSource parameter combinations
                bs_attempts = [
                    # Attempt 1: Full explicit parameters
                    lambda: core.bs.VideoSource(
                        source=path,
                        track=-1,
                        fpsnum=-1,
                        fpsden=1,
                        rff=False,
                        threads=0,
                        seekpreroll=20,
                        hwdevice="",
                        exactseek=True,
                        readahead=False
                    ),
                    # Attempt 2: Minimal parameters (common working config)
                    lambda: core.bs.VideoSource(
                        source=path,
                        track=-1,
                        threads=0
                    ),
                    # Attempt 3: Basic parameters only
                    lambda: core.bs.VideoSource(path, track=-1),
                    # Attempt 4: Absolute minimal (just path)
                    lambda: core.bs.VideoSource(path)
                ]

                bs_error = None
                for i, attempt in enumerate(bs_attempts, 1):
                    try:
                        print(f"[pipeline] BestSource attempt {i}/4...")
                        clip = attempt()
                        print(f"[pipeline] Successfully loaded with BestSource (attempt {i}): {clip.width}x{clip.height}, {clip.num_frames} frames")
                        return clip
                    except Exception as e:
                        bs_error = e
                        print(f"[pipeline] BestSource attempt {i} failed: {e}")
                        continue

                # If all BestSource attempts failed, re-raise the last error
                raise bs_error if bs_error else Exception("BestSource failed with unknown error")
            else:
                print(f"[pipeline] Plugin {impl} not available (core.{impl} missing)")
                errors[impl] = f"Plugin not available"

        except Exception as e:
            error_msg = str(e)
            print(f"[pipeline] {impl} failed: {error_msg}")
            errors[impl] = error_msg
            continue

    # Detailed error reporting
    error_details = []
    for impl, error in errors.items():
        error_details.append(f"{impl}: {error}")

    raise RuntimeError(f"All source methods failed. Errors: {'; '.join(error_details)}")

src = load_source(SRC)

# ---------- Detect field order ----------
def detect_field_order(clip):
    """Simple field order detection based on motion analysis"""
    try:
        # Sample a few frames for analysis
        frame_count = min(100, clip.num_frames)
        if frame_count < 10:
            return True  # Default to TFF

        # Use basic motion detection - this is a simplified heuristic
        # In practice, you might want more sophisticated detection
        return bool(os.environ.get("FORCE_TFF", "1"))  # Fallback to env var
    except:
        return True  # Default to TFF

TFF_DETECTED = detect_field_order(src)
print(f"[pipeline] Detected field order: {'TFF' if TFF_DETECTED else 'BFF'}")

# ---------- IVTC Analysis for Animated Content ----------
telecined = src
needs_deinterlacing = True
ivtc_applied = False

# For Futurama and similar animated content, most episodes are true interlaced
# Some later episodes might be telecined film content
if IVTC and hasattr(core, "tivtc"):
    print("[pipeline] Analyzing content for telecine patterns...")

    try:
        # Apply TFM (field matching) first
        tfm_clip = core.tivtc.TFM(src, field=int(not TFF_DETECTED), PP=3)

        # Get TDecimate metrics to analyze telecine pattern
        metrics_clip = core.tivtc.TDecimate(tfm_clip, mode=1, hybrid=1)

        # For animated content, we need to be more conservative about IVTC
        # Check frame rate to determine if IVTC is appropriate
        try:
            # If source is ~29.97fps, it might be telecined 23.976fps content
            import subprocess
            fps_result = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
                                       '-show_entries', 'stream=r_frame_rate', '-of',
                                       'default=noprint_wrappers=1:nokey=1', SRC],
                                      capture_output=True, text=True, timeout=10)

            if fps_result.returncode == 0:
                fps_str = fps_result.stdout.strip()
                if '30000/1001' in fps_str or '29.97' in fps_str:
                    # Likely telecined content, apply TDecimate
                    telecined = core.tivtc.TDecimate(tfm_clip, mode=0)
                    ivtc_applied = True
                    needs_deinterlacing = False
                    print("[pipeline] 29.97fps source detected - applying IVTC for telecined content")
                elif '25' in fps_str or '24' in fps_str:
                    # Progressive content, no IVTC needed
                    telecined = src
                    needs_deinterlacing = False
                    print("[pipeline] Progressive content detected, skipping IVTC and deinterlacing")
                else:
                    # True interlaced content (common for early Futurama episodes)
                    telecined = src
                    print("[pipeline] True interlaced content detected, will deinterlace")
            else:
                # Fallback to deinterlacing
                telecined = src
                print("[pipeline] Could not determine frame rate, defaulting to deinterlacing")

        except Exception as fps_e:
            print(f"[pipeline] Frame rate detection failed: {fps_e}, defaulting to deinterlacing")
            telecined = src

    except Exception as e:
        print(f"[pipeline] IVTC analysis failed: {e}, falling back to deinterlacing")
        telecined = src
elif IVTC:
    import sys as _sys
    _sys.stderr.write("[pipeline] Warning: IVTC requested but core.tivtc missing; skipping IVTC.\n")

# ---------- QTGMC Deinterlacing (optimized for animation) ----------
if needs_deinterlacing:
    print("[pipeline] Applying QTGMC deinterlacing for animated content")

    # Adaptive QTGMC settings based on content type
    if CONTENT_TYPE == "animation":
        # Animation-optimized settings
        qtgmc_params = {
            "Preset": QTGMC_PRESET,
            "TFF": TFF_DETECTED,
            "EdiMode": "NNEDI3CL",
            "EdiThreads": 1,
            "TR2": 1,
            "EZKeepGrain": 0.0,     # No grain in animation
            "NoiseProcess": 0,       # Disable noise processing
            "GrainRestore": 0.0,     # No grain restoration
            "Sharpness": 0.2,        # Crisp lines
            "FPSDivisor": 1
        }
        print(f"[pipeline] Using animation-optimized QTGMC preset: {QTGMC_PRESET}")
    else:
        # Live action settings (more conservative)
        qtgmc_params = {
            "Preset": QTGMC_PRESET,
            "TFF": TFF_DETECTED,
            "EdiMode": "NNEDI3CL",
            "EdiThreads": 1,
            "TR2": 2,                # Higher temporal radius
            "EZKeepGrain": 0.3,      # Preserve some grain
            "NoiseProcess": 1,       # Enable noise processing
            "Sharpness": 0.0,        # No extra sharpening
            "FPSDivisor": 1
        }
        print(f"[pipeline] Using live-action QTGMC preset: {QTGMC_PRESET}")

    prog = haf.QTGMC(telecined, **qtgmc_params)
else:
    if ivtc_applied:
        print("[pipeline] IVTC applied, content now progressive")
    else:
        print("[pipeline] Content already progressive, no deinterlacing needed")
    prog = telecined

# ---------- Optional denoise (BM3D-CUDA) ----------
clean = prog
if DENOISE_IMPL == "bm3d":
    if not hasattr(core, "bm3dcuda"):
        raise RuntimeError("DENOISE_IMPL=bm3d but bm3dcuda plugin is missing")
    try:
        sigma = float(os.environ.get("BM3D_SIGMA", "2.5"))
    except (ValueError, TypeError):
        sigma = 2.5
    try:
        radius = int(float(os.environ.get("BM3D_RADIUS", "1")))
    except (ValueError, TypeError):
        radius = 1
    tmp = core.bm3dcuda.VBasic(clean, sigma=sigma, radius=radius)
    clean = core.bm3dcuda.VFinal(clean, ref=tmp, sigma=sigma, radius=radius)

# ---------- GPU Memory Detection ----------
def get_optimal_tile_size():
    """Calculate optimal tile size based on available VRAM and frame resolution"""
    try:
        import subprocess
        # Try to get GPU memory info
        result = subprocess.run(['nvidia-smi', '--query-gpu=memory.total,memory.free', '--format=csv,noheader,nounits'],
                              capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')
            if lines:
                total_mem, free_mem = map(int, lines[0].split(', '))
                print(f"[pipeline] GPU Memory: {free_mem}MB free / {total_mem}MB total")

                # Conservative tile size calculation based on free memory
                if free_mem >= 8000:  # 8GB+
                    return 512, 512
                elif free_mem >= 6000:  # 6-8GB
                    return 384, 384
                elif free_mem >= 4000:  # 4-6GB
                    return 256, 256
                else:  # <4GB
                    return 192, 192
    except:
        pass

    # Fallback based on frame size
    frame_width = rgb.width if 'rgb' in locals() else 720
    frame_height = rgb.height if 'rgb' in locals() else 480

    # Conservative defaults for different frame sizes
    if frame_width * frame_height > 1920 * 1080:  # >1080p source
        return 192, 192
    elif frame_width * frame_height > 1280 * 720:  # 720p-1080p
        return 256, 256
    else:  # <=720p
        return 384, 384

# ---------- Upscale ----------
rgb = core.resize.Bicubic(clean, format=vs.RGBS)

# ---------- Upscaling with Error Recovery ----------
def try_upscale_method(method, rgb_clip):
    """Try upscaling with fallback on failure"""
    try:
        if method == "basicvsr":
            from vsbasicvsrpp import BasicVSRPP
            model = os.environ.get("BASICVSR_MODEL", "/models/basicvsrpp/BasicVSRPP_x4_vimeo90k.pth")

            if not os.path.isfile(model):
                raise FileNotFoundError(f"BasicVSR model not found: {model}")

            # Dynamic tiling for BasicVSR
            tile_w, tile_h = get_optimal_tile_size()
            tile_w = int(os.environ.get("BASICVSR_TILE_W", tile_w))
            tile_h = int(os.environ.get("BASICVSR_TILE_H", tile_h))
            overlap = int(os.environ.get("BASICVSR_OVERLAP", "16"))

            print(f"[pipeline] BasicVSR tiling: {tile_w}x{tile_h}, overlap={overlap}")
            return BasicVSRPP(rgb_clip, model_path=model, tile_w=tile_w, tile_h=tile_h, overlap=overlap, device_id=0)

        elif method == "realcugan":
            # Real-CUGAN: Superior for clean animation content
            try:
                # Import and initialize Real-CUGAN wrapper
                import vsrealcugan

                model = os.environ.get("REALCUGAN_MODEL", "/models/realcugan/Real-CUGAN_up4x-latest-conservative.pth")

                if not os.path.isfile(model):
                    print(f"[pipeline] Real-CUGAN model not found: {model}, using default scaling")
                    # Use built-in scaling if model not found
                    tile_w, tile_h = get_optimal_tile_size()
                    tile_size = int(os.environ.get("REALCUGAN_TILE", min(tile_w, tile_h)))

                    # Use the wrapper with fallback
                    upscaler = vsrealcugan.RealCUGAN(
                        device_id=0,
                        model_path=model,
                        scale=4,
                        tile=tile_size,
                        sync=0,
                        tta_mode=0
                    )
                    print(f"[pipeline] Real-CUGAN tiling: {tile_size}x{tile_size}")
                    return upscaler(rgb_clip)

                tile_w, tile_h = get_optimal_tile_size()
                tile_size = int(os.environ.get("REALCUGAN_TILE", min(tile_w, tile_h)))

                print(f"[pipeline] Real-CUGAN tiling: {tile_size}x{tile_size}")

                # Create upscaler instance
                upscaler = vsrealcugan.RealCUGAN(
                    device_id=0,
                    model_path=model,
                    scale=4,
                    tile=tile_size,
                    sync=0,
                    tta_mode=0
                )

                return upscaler(rgb_clip)

            except ImportError as e:
                print(f"[pipeline] Real-CUGAN wrapper import failed: {e}")
                print("[pipeline] Falling back to RealESRGAN")
                # Fallback to RealESRGAN
                from vsrealesrgan import RealESRGAN
                model = os.environ.get("ESRGAN_MODEL", "/models/realesrgan/RealESRGAN_x4plus_anime_6B.pth")
                if not os.path.isfile(model):
                    raise FileNotFoundError(f"RealESRGAN fallback model not found: {model}")
                tile_w, tile_h = get_optimal_tile_size()
                tile_size = int(os.environ.get("ESRGAN_TILE", min(tile_w, tile_h)))
                return RealESRGAN(device_id=0, model_path=model, scale=4, tile=tile_size, tile_pad=16, pre_pad=0, half=True)(rgb_clip)
            except Exception as e:
                print(f"[pipeline] Real-CUGAN processing failed: {e}")
                print("[pipeline] Falling back to RealESRGAN")
                # Fallback to RealESRGAN on any error
                from vsrealesrgan import RealESRGAN
                model = os.environ.get("ESRGAN_MODEL", "/models/realesrgan/RealESRGAN_x4plus_anime_6B.pth")
                if not os.path.isfile(model):
                    raise FileNotFoundError(f"RealESRGAN fallback model not found: {model}")
                tile_w, tile_h = get_optimal_tile_size()
                tile_size = int(os.environ.get("ESRGAN_TILE", min(tile_w, tile_h)))
                return RealESRGAN(device_id=0, model_path=model, scale=4, tile=tile_size, tile_pad=16, pre_pad=0, half=True)(rgb_clip)

        elif method == "esrgan":
            from vsrealesrgan import RealESRGAN
            model = os.environ.get("ESRGAN_MODEL", "/models/realesrgan/RealESRGAN_x4plus_anime_6B.pth")

            if not os.path.isfile(model):
                raise FileNotFoundError(f"RealESRGAN model not found: {model}")

            # Dynamic tiling for RealESRGAN
            tile_w, tile_h = get_optimal_tile_size()
            tile_size = int(os.environ.get("ESRGAN_TILE", min(tile_w, tile_h)))
            tile_pad = int(os.environ.get("ESRGAN_TILE_PAD", "16"))

            print(f"[pipeline] RealESRGAN tiling: {tile_size}x{tile_size}, pad={tile_pad}")
            return RealESRGAN(device_id=0, model_path=model, scale=4, tile=tile_size, tile_pad=tile_pad, pre_pad=0, half=True)(rgb_clip)

        elif method == "none":
            print("[pipeline] No upscaling applied")
            # Simple 4x bicubic upscale to maintain expected output size
            return core.resize.Bicubic(rgb_clip, width=rgb_clip.width*4, height=rgb_clip.height*4)

    except Exception as e:
        print(f"[pipeline] ERROR: {method} upscaling failed: {e}")
        return None

# Try upscaling with fallback chain
upscale_methods = [UPSCALE_IMPL]
if UPSCALE_IMPL == "realcugan":
    upscale_methods.extend(["esrgan", "basicvsr", "none"])
elif UPSCALE_IMPL == "basicvsr":
    upscale_methods.extend(["realcugan", "esrgan", "none"])
elif UPSCALE_IMPL == "esrgan":
    upscale_methods.extend(["realcugan", "none"])

up = None
for method in upscale_methods:
    print(f"[pipeline] Attempting upscaling with: {method}")
    up = try_upscale_method(method, rgb)
    if up is not None:
        print(f"[pipeline] Successfully upscaled with: {method}")
        break
    else:
        print(f"[pipeline] {method} failed, trying next method...")

if up is None:
    raise RuntimeError("All upscaling methods failed")

# ---------- Output ----------
out = core.resize.Spline36(up, format=vs.YUV420P10, matrix_in_s="709", matrix_s="709", range_s="limited")
out.set_output()

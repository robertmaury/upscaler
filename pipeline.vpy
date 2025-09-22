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

# ---------- Source with fallback ----------
def load_source(path: str):
    impl_order = {
        "ffms2": ["ffms2", "lsmas", "bestsource"],
        "lsmas": ["lsmas", "ffms2", "bestsource"],
        "bestsource": ["bestsource", "ffms2", "lsmas"],
    }.get(SOURCE_IMPL, ["ffms2", "lsmas", "bestsource"])

    last_err = None
    for impl in impl_order:
        try:
            if impl == "ffms2" and hasattr(core, "ffms2"):
                return core.ffms2.Source(path)
            if impl == "lsmas" and hasattr(core, "lsmas"):
                return core.lsmas.LWLibavSource(path)
            if impl == "bestsource" and hasattr(core, "bs"):
                # threads=0 lets it auto-pick, seekmode=1 for mkv
                return core.bs.VideoSource(path, threads=0, seekmode=1)
        except Exception as e:
            last_err = e
            continue
    raise RuntimeError(f"Could not open source with {impl_order}: {last_err}")

src = load_source(SRC)

# ---------- QTGMC ----------
# TFF is typical for NTSC DVDs; flip to False if needed
deint = haf.QTGMC(
    src, Preset="Slow", TFF=True,
    EdiMode="NNEDI3CL", EdiThreads=1, TR2=1, EZKeepGrain=0.20
)

prog = deint

# ---------- Try to auto‑load TIVTC if missing ----------
# ---------- IVTC (soft‑fallback) ----------
if IVTC:
    if not hasattr(core, "tivtc"):
        import sys as _sys
        _sys.stderr.write("[pipeline] Warning: IVTC requested but core.tivtc missing; skipping IVTC.\n")
    else:
        prog = core.tivtc.TFM(prog)
        prog = core.tivtc.TDecimate(prog)

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

# ---------- Upscale ----------
rgb = core.resize.Bicubic(clean, format=vs.RGBS)

if UPSCALE_IMPL == "basicvsr":
    from vsbasicvsrpp import BasicVSRPP
    model = os.environ.get("BASICVSR_MODEL", "/models/basicvsrpp/BasicVSRPP_x4_vimeo90k.pth")
    up = BasicVSRPP(rgb, model_path=model, tile_w=0, tile_h=0, overlap=16, device_id=0)
elif UPSCALE_IMPL == "none":
    up = rgb
else:
    from vsrealesrgan import RealESRGAN
    model = os.environ.get("ESRGAN_MODEL", "/models/realesrgan/RealESRGAN_x4plus_anime_6B.pth")
    up = RealESRGAN(device_id=0, model_path=model, scale=4, tile=256, tile_pad=16, pre_pad=0, half=True)(rgb)

# ---------- Output ----------
out = core.resize.Spline36(up, format=vs.YUV420P10, matrix_in_s="709", matrix_s="709", range_s="limited")
out.set_output()

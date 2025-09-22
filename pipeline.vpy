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

# ---------- DEBUG: Passthrough ----------
# All processing is disabled to isolate the source filter.
out = src
out.set_output()

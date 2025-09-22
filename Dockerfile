# ---------------------------------------------
# Child layer: add VS plugins & Python wrappers
# ---------------------------------------------
FROM pifroggi/vapoursynth:2025_09_05

LABEL maintainer="Robert Maury <daquinox@gmail.com>"
LABEL description="VapourSynth container with plugins for deinterlacing and upscaling."

ARG DEBIAN_FRONTEND=noninteractive

# Set consistent plugin path for all builds
ENV VS_PLUGIN_DIR="/usr/local/lib/vapoursynth"
ENV VAPOURSYNTH_PLUGIN_PATH=${VS_PLUGIN_DIR}
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# Set CUDA environment
ENV CUDA_HOME=/usr/local/cuda
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/lib:/usr/local/lib:${LD_LIBRARY_PATH}
ENV CUDA_PATH=/usr/local/cuda

# Install runtime dependencies and vsrepo for simplified plugin management
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ocl-icd-libopencl1 ocl-icd-opencl-dev \
    libzimg-dev libjpeg-turbo8-dev libpng-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    python3-pip python3-setuptools python3-wheel \
    && rm -rf /var/lib/apt/lists/*

# Install VapourSynth plugins using vsrepo to avoid build complexities
RUN python3 -m pip install --no-cache-dir vsrepo && \
    /usr/local/bin/vsrepo init --update && \
    /usr/local/bin/vsrepo install \
      com.dubhater.mvtools \
      com.homeofvaisynth.nnedi3cl \
      com.eleonoremizo.fmtconv \
      com.dubhater.tivtc \
      com.wolframrhodium.bm3dcuda

# --- Python side: QTGMC script + CUDA wrappers for A/B ---
RUN python3 -m pip install --no-cache-dir --upgrade vsutil && \
    python3 -m pip install --no-cache-dir \
    havsfunc \
    vsrealesrgan vsbasicvsrpp basicsr facexlib gfpgan tqdm scipy && \
    PYV=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")') && \
    SITE="/usr/local/lib/python${PYV}/dist-packages" && \
    curl -fsSL -o "${SITE}/mvsfunc.py" https://raw.githubusercontent.com/HomeOfVapourSynthEvolution/mvsfunc/refs/tags/r10/mvsfunc.py

# Optional: model mount points (bind real weights at runtime)
RUN mkdir -p /models/realesrgan /models/basicvsrpp
ENV ESRGAN_MODEL=/models/realesrgan/RealESRGAN_x4plus_anime_6B.pth
ENV BASICVSR_MODEL=/models/basicvsrpp/BasicVSRPP_x4_vimeo90k.pth

# Quick sanity script to verify plugins are discoverable
RUN printf '%s\n' \
'import vapoursynth as vs, havsfunc as haf' \
'c=vs.core' \
'print("VS", c.version())' \
'print("ffms2", hasattr(c,"ffms2"))' \
'print("lsmas", hasattr(c,"lsmas"))' \
'print("bestsource", hasattr(c,"bs"))' \
'print("mv", hasattr(c,"mv"))' \
'print("nnedi3cl", hasattr(c,"nnedi3cl"))' \
'print("fmtc", hasattr(c,"fmtc"))' \
'print("hqdn3d", hasattr(c,"hqdn3d"))' \
'print("tivtc", hasattr(c,"tivtc"))' \
'print("QTGMC via havsfunc", hasattr(haf,"QTGMC"))' \
> /usr/local/bin/vs_sanity.py && chmod +x /usr/local/bin/vs_sanity.py


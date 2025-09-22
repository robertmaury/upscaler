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
    git curl \
    ocl-icd-libopencl1 ocl-icd-opencl-dev \
    libzimg-dev libjpeg-turbo8-dev libpng-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    python3-pip python3-setuptools python3-wheel \
    && rm -rf /var/lib/apt/lists/*

# Install VapourSynth plugins using vsrepo to avoid build complexities
RUN git clone https://github.com/vapoursynth/vsrepo.git /tmp/vsrepo && \
    python3 /tmp/vsrepo/vsrepo.py init --update && \
    python3 /tmp/vsrepo/vsrepo.py install \
      com.dubhater.mvtools \
      com.homeofvaisynth.nnedi3cl \
      com.eleonoremizo.fmtconv \
      com.dubhater.tivtc \
      com.wolframrhodium.bm3dcuda \
      com.homeofvaisynth.mvsfunc && \
    rm -rf /tmp/vsrepo

# --- Python side: QTGMC script + CUDA wrappers for A/B ---
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel vsutil && \
    python3 -m pip install --no-cache-dir \
    havsfunc vsrealesrgan vsbasicvsrpp basicsr facexlib gfpgan tqdm scipy

# Optional: model mount points (bind real weights at runtime)
RUN mkdir -p /models/realesrgan /models/basicvsrpp
ENV ESRGAN_MODEL=/models/realesrgan/RealESRGAN_x4plus_anime_6B.pth
ENV BASICVSR_MODEL=/models/basicvsrpp/BasicVSRPP_x4_vimeo90k.pth


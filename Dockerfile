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

# Install build and runtime dependencies
RUN BUILD_DEPS="git build-essential meson ninja-build pkg-config python3-dev cython3" && \
    apt-get update && apt-get install -y --no-install-recommends \
    $BUILD_DEPS \
    curl ocl-icd-libopencl1 ocl-icd-opencl-dev \
    libzimg-dev libjpeg-turbo8-dev libpng-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    python3-pip python3-setuptools

# Build nnedi3cl from source for Linux compatibility
RUN git clone --depth=1 https://github.com/HomeOfVapourSynthEvolution/VapourSynth-NNEDI3CL.git /tmp/nnedi3cl && \
    cd /tmp/nnedi3cl && \
    meson setup build --buildtype=release --prefix=/usr/local --libdir="${VS_PLUGIN_DIR}" && \
    ninja -C build && ninja -C build install && \
    rm -rf /tmp/nnedi3cl

# Install other plugins using vsrepo
RUN git clone https://github.com/vapoursynth/vsrepo.git /tmp/vsrepo && \
    python3 /tmp/vsrepo/vsrepo.py update && \
    python3 /tmp/vsrepo/vsrepo.py install \
      com.nodame.mvtools \
      fmtconv \
      com.nodame.tivtc \
      com.wolframrhodium.bm3dcuda \
      mvsfunc && \
    rm -rf /tmp/vsrepo

# --- Python side: QTGMC script + CUDA wrappers for A/B ---
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools vsutil && \
    python3 -m pip install --no-cache-dir \
    havsfunc vsrealesrgan vsbasicvsrpp basicsr facexlib gfpgan tqdm scipy

# --- Cleanup ---
RUN apt-get purge -y --auto-remove \
      git build-essential meson ninja-build pkg-config python3-dev cython3 && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* && \
    ldconfig

# Optional: model mount points (bind real weights at runtime)
RUN mkdir -p /models/realesrgan /models/basicvsrpp
ENV ESRGAN_MODEL=/models/realesrgan/RealESRGAN_x4plus_anime_6B.pth
ENV BASICVSR_MODEL=/models/basicvsrpp/BasicVSRPP_x4_vimeo90k.pth

# Add and set up the entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh


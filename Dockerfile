# Base image from NVIDIA
FROM nvcr.io/nvidia/tensorrt:24.08-py3
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
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools
    git build-essential meson ninja-build pkg-config python3-dev cython3 \
    # VapourSynth dependencies
    curl ocl-icd-libopencl1 ocl-icd-opencl-dev \
    libzimg-dev libjpeg-turbo8-dev libpng-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    # Python
    python3-pip python3-setuptools \
    # General utilities
    p7zip-full x264 autoconf libtool yasm nasm clang ffmsindex libffms2-dev wget \
    # Compression and development libraries
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libncursesw5-dev \
    xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    libfftw3-dev

# Upgrade pip and Install torch
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install --no-cache-dir --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu121

# Install VapourSynth R72
RUN wget https://github.com/vapoursynth/vapoursynth/archive/refs/tags/R72.tar.gz && \
    tar -zxvf R72.tar.gz && \
    cd vapoursynth-R72 && \
    ./autogen.sh && \
    ./configure && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd .. && rm -rf vapoursynth-R72 R72.tar.gz

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
RUN python3 -m pip install --no-cache-dir --upgrade setuptools vsutil && \
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

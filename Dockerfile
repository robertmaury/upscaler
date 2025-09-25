# Base image from NVIDIA
#FROM nvcr.io/nvidia/tensorrt:25.08-py3
FROM nvcr.io/nvidia/pytorch:25.08-py3
ARG DEBIAN_FRONTEND=noninteractive

# Set consistent plugin path for all builds
ENV VS_PLUGIN_DIR="/usr/local/lib/vapoursynth"
ENV VAPOURSYNTH_PLUGIN_PATH=${VS_PLUGIN_DIR}
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# Set CUDA environment
ENV CUDA_HOME=/usr/local/cuda
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/lib:/usr/local/lib:${LD_LIBRARY_PATH}
ENV CUDA_PATH=/usr/local/cuda

# Install essential runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Essential utilities and Python runtime
    curl python3-pip python3-setuptools wget \
    # Core multimedia libraries
    ffmpeg libffms2-5 ocl-icd-libopencl1 \
    # Compression and crypto libraries
    libssl3 zlib1g libbz2-1.0 libffi8 liblzma5 \
    # Math and hash libraries
    libfftw3-double3 libturbojpeg libgsl27 libxxhash0 \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip and Install torch
# RUN python3 -m pip install --upgrade pip && \
#     python3 -m pip install --no-cache-dir --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu130

# Install Python packages
RUN python -m pip install Cython meson ninja setuptools wheel \
	onnx onnxruntime onnxruntime-gpu \
    opencv-python Pillow tensorboardX pyiqa einops positional_encodings timm PyTurboJPEG \
    # Real-CUGAN dependencies
    torch torchvision numpy

# FFmpeg is already installed above, skip redundant installation

# Install mmcv from source with support for 20-50 series gpus (below no longer supported with newest cuda)
ENV MMCV_WITH_OPS=1 FORCE_CUDA=1 TORCH_CUDA_ARCH_LIST="8.6;8.9;9.0"
RUN python -m pip -v install --no-cache-dir --force-reinstall --no-binary mmcv "mmcv>=2.0.0" --ignore-installed PyYAML


# Install VapourSynth R72 with its build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools for VapourSynth
    git build-essential autoconf automake libtool pkg-config python3-dev cython3 yasm nasm \
    # VapourSynth dependencies
    libzimg-dev libjpeg-turbo8-dev libpng-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    libboost-dev libboost-system-dev libboost-filesystem-dev \
    && wget https://github.com/vapoursynth/vapoursynth/archive/refs/tags/R72.tar.gz \
    && tar -zxvf R72.tar.gz \
    && cd vapoursynth-R72 \
    && ./autogen.sh \
    && ./configure \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd .. && rm -rf vapoursynth-R72 R72.tar.gz \
    # Clean up VapourSynth build dependencies but keep runtime libs
    && apt-get purge -y --auto-remove git build-essential autoconf automake libtool cython3 yasm nasm \
    && rm -rf /var/lib/apt/lists/*
# Install the Python bindings so vsrepo can find the installation
RUN python3 -m pip install --use-pep517 vapoursynth

# Build nnedi3cl from source for Linux compatibility
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential meson ninja-build opencl-headers ocl-icd-opencl-dev \
    && git clone --depth=1 https://github.com/HomeOfVapourSynthEvolution/VapourSynth-NNEDI3CL.git /tmp/nnedi3cl \
    && cd /tmp/nnedi3cl \
    && meson setup build --buildtype=release --prefix=/usr/local --libdir="${VS_PLUGIN_DIR}" \
    && ninja -C build && ninja -C build install \
    && cd / && rm -rf /tmp/nnedi3cl \
    && apt-get purge -y --auto-remove git build-essential meson ninja-build opencl-headers ocl-icd-opencl-dev \
    && rm -rf /var/lib/apt/lists/*

# Build L-SMASH library with proper dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential autoconf automake libtool \
    && git clone https://github.com/l-smash/l-smash \
    && cd l-smash \
    && CFLAGS="-fPIC -O2" CXXFLAGS="-fPIC -O2" LDFLAGS="-Wl,-Bsymbolic" \
        ./configure --enable-shared --extra-ldflags="-Wl,-Bsymbolic" \
    && make -j$(nproc) && make install && ldconfig \
    && cd .. && rm -rf l-smash \
    && apt-get purge -y --auto-remove git build-essential autoconf automake libtool \
    && rm -rf /var/lib/apt/lists/*

# Build L-SMASH-Works VapourSynth plugin
RUN apt-get update && apt-get install -y --no-install-recommends \
    git meson ninja-build pkg-config \
    && git clone https://github.com/HomeOfAviSynthPlusEvolution/L-SMASH-Works \
    && cd L-SMASH-Works/VapourSynth \
    && PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH \
    meson setup build --buildtype=release --prefix=/usr/local --libdir="${VS_PLUGIN_DIR}" \
    && ninja -C build && ninja -C build install && ldconfig \
    && python3 -c "import vapoursynth as vs; c=vs.core; print('LSMAS available:', hasattr(c, 'lsmas'))" \
    && cd ../../.. && rm -rf L-SMASH-Works \
    && apt-get purge -y --auto-remove git meson ninja-build pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install other plugins using vsrepo
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && git clone https://github.com/vapoursynth/vsrepo.git /tmp/vsrepo \
    && python3 /tmp/vsrepo/vsrepo.py update \
    && python3 /tmp/vsrepo/vsrepo.py install \
      com.nodame.mvtools \
      com.vapoursynth.ffms2 \
      io.github.amusementclub.vsmlrt_script \
      com.vapoursynth.bestsource \
      fmtconv \
      com.nodame.tivtc \
      com.wolframrhodium.bm3dcuda \
      mvsfunc \
    && python3 -c "import vapoursynth as vs; c=vs.core; print('BestSource available:', hasattr(c, 'bs'))" \
    && rm -rf /tmp/vsrepo \
    && apt-get purge -y --auto-remove git \
    && rm -rf /var/lib/apt/lists/*

# --- Python side: QTGMC script + CUDA wrappers for A/B ---
RUN python3 -m pip install --no-cache-dir --upgrade setuptools vsutil && \
    python3 -m pip install --no-cache-dir \
    havsfunc vsrealesrgan vsbasicvsrpp basicsr facexlib gfpgan tqdm scipy

# Install Real-CUGAN dependencies and create VapourSynth wrapper
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && python3 -m pip install --no-cache-dir torch torchvision torchaudio \
    && git clone https://github.com/bilibili/ailab.git /tmp/realcugan-src \
    && cd /tmp/realcugan-src/Real-CUGAN \
    && mkdir -p /usr/local/lib/realcugan \
    && cp -r . /usr/local/lib/realcugan/ \
    && chmod +x /usr/local/lib/realcugan/upcunet_v3.py \
    && cd / && rm -rf /tmp/realcugan-src \
    && apt-get purge -y --auto-remove git \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Real-CUGAN VapourSynth wrapper
# Copy Real-CUGAN VapourSynth wrapper to Python site-packages
COPY vsrealcugan.py /usr/local/lib/python3/dist-packages/
RUN PYTHON_SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])") && \
    cp /usr/local/lib/python3/dist-packages/vsrealcugan.py "$PYTHON_SITE_PACKAGES/" && \
    python3 -c "\
import sys; \
try: \
    import vsrealcugan; \
    print('Real-CUGAN VapourSynth wrapper installed successfully'); \
except Exception as e: \
    print(f'Real-CUGAN wrapper installation check failed: {e}'); \
"

# Create models directory structure for Real-CUGAN
RUN mkdir -p /models/realcugan

# Skip Qt6 and vsedit for headless operation
# These are only needed for GUI editing, not for batch processing

# Final cleanup
RUN apt-get autoremove -y && \
    apt-get autoclean -y && \
    rm -rf /var/lib/apt/lists/* \
           /tmp/* \
           /var/tmp/* \
           /root/.cache \
           /home/*/.cache && \
    ldconfig

# Optional: model mount points (bind real weights at runtime)
RUN mkdir -p /models/realesrgan /models/basicvsrpp
ENV ESRGAN_MODEL=/models/realesrgan/RealESRGAN_x4plus_anime_6B.pth
ENV BASICVSR_MODEL=/models/basicvsrpp/BasicVSRPP_x4_vimeo90k.pth

# Final cleanup already done above, remove duplicate

# Skip config file links for removed GUI applications

# Remove Nvidia banner text wall
RUN rm -f /opt/nvidia/entrypoint.d/*banner* /opt/nvidia/entrypoint.d/*.txt

# Add and set up the entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

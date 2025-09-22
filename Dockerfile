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
    p7zip-full x264 autoconf automake libtool yasm nasm clang ffmsindex libffms2-dev wget \
    # Compression and development libraries
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libncursesw5-dev \
    xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    libfftw3-dev \
    # GUI and advanced dependencies from original image
    checkinstall qt6-base-dev libqt6websockets6-dev libqt6core5compat6-dev \
    libboost-dev libboost-system-dev libboost-filesystem-dev \
    x11-xserver-utils libxcb-cursor0 xfe libfftw3-dev libturbojpeg big-cursor \
    libgsl-dev libxxhash-dev

# Upgrade pip and Install torch
# RUN python3 -m pip install --upgrade pip && \
#     python3 -m pip install --no-cache-dir --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu130

# Install Python packages
RUN python -m pip install Cython meson ninja setuptools wheel \
	onnx onnxruntime onnxruntime-gpu \
    opencv-python Pillow tensorboardX pyiqa einops positional_encodings timm PyTurboJPEG

# Install mmcv from source with support for 20-50 series gpus (below no longer supported with newest cuda)
ENV MMCV_WITH_OPS=1 FORCE_CUDA=1 TORCH_CUDA_ARCH_LIST="7.5;8.6;8.9;12.0"
RUN python -m pip -v install --no-cache-dir --force-reinstall --no-binary mmcv "mmcv>=2.0.0" --ignore-installed PyYAML


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
# Install the Python bindings so vsrepo can find the installation
RUN python3 -m pip install --use-pep517 vapoursynth

# Build nnedi3cl from source for Linux compatibility
RUN git clone --depth=1 https://github.com/HomeOfVapourSynthEvolution/VapourSynth-NNEDI3CL.git /tmp/nnedi3cl && \
    cd /tmp/nnedi3cl && \
    meson setup build --buildtype=release --prefix=/usr/local --libdir="${VS_PLUGIN_DIR}" && \
    ninja -C build && ninja -C build install && \
    rm -rf /tmp/nnedi3cl

RUN git clone https://github.com/l-smash/l-smash && \
    cd l-smash && CFLAGS=-fPIC CXXFLAGS=-fPIC LDFLAGS="-Wl,-Bsymbolic" \
        ./configure --enable-shared --extra-ldflags="-Wl,-Bsymbolic" && \
    make -j$(nproc) && make install && \
    cd .. && rm -rf l-smash && \
    git clone https://github.com/HomeOfAviSynthPlusEvolution/L-SMASH-Works && \
    cd L-SMASH-Works/VapourSynth && \
    meson build && ninja -C build && ninja -C build install && \
    cd ../../.. && rm -rf L-SMASH-Works

# Install other plugins using vsrepo
RUN git clone https://github.com/vapoursynth/vsrepo.git /tmp/vsrepo && \
    python3 /tmp/vsrepo/vsrepo.py update && \
    python3 /tmp/vsrepo/vsrepo.py install \
      com.nodame.mvtools \
      com.vapoursynth.ffms2 \
      io.github.amusementclub.vsmlrt_script \
      com.vapoursynth.bestsource \
      fmtconv \
      com.nodame.tivtc \
      com.wolframrhodium.bm3dcuda \
      mvsfunc && \
    rm -rf /tmp/vsrepo

# --- Python side: QTGMC script + CUDA wrappers for A/B ---
RUN python3 -m pip install --no-cache-dir --upgrade setuptools vsutil && \
    python3 -m pip install --no-cache-dir \
    havsfunc vsrealesrgan vsbasicvsrpp basicsr facexlib gfpgan tqdm scipy

# Setup Qt6
ENV PATH="/usr/lib/qt6/bin:$PATH" \
    XDG_RUNTIME_DIR=/tmp/runtime-root

# Install vsedit
RUN git clone https://github.com/YomikoR/VapourSynth-Editor && \
    cd VapourSynth-Editor/pro && \
    apt-get install -y --no-install-recommends \
    qt6-base-dev qt6-base-dev-tools qmake6 && \
    qmake pro.pro && \
    make && \
    mv ../build/release-64bit-gcc/vsedit /usr/local/bin/ && \
    cd ../.. && rm -rf VapourSynth-Editor

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

# Clean up unnecessary files
RUN apt-get autoclean -y && apt-get autoremove -y && apt-get clean -y && \
    python -m pip cache purge

# Create symbolic links for vsedit and xfe config files so that they don't reset
RUN mkdir -p /root/.config/xfe \
    && ln -sf /workspace/vapoursynth/configs/vsedit.config /root/.config/vsedit.config \
    && ln -sf /workspace/vapoursynth/configs/xfwrc /root/.config/xfe/xfwrc \
    && ln -sf /workspace/vapoursynth/configs/xferc /root/.config/xfe/xferc

# Remove Nvidia banner text wall
RUN rm -f /opt/nvidia/entrypoint.d/*banner* /opt/nvidia/entrypoint.d/*.txt

# Add and set up the entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

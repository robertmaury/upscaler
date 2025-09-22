# ---------------------------------------------
# Child layer: add VS plugins & Python wrappers
# ---------------------------------------------
FROM pifroggi/vapoursynth:2025_09_05

LABEL maintainer="Your Name <you@example.com>"
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

# Install build dependencies, compile plugins, and then remove build deps in a single layer
RUN BUILD_DEPS="git build-essential meson ninja-build cmake pkg-config python3-dev cython3 autoconf automake libtool" && \
    apt-get update && apt-get install -y --no-install-recommends \
    $BUILD_DEPS \
    ocl-icd-libopencl1 ocl-icd-opencl-dev \
    libzimg-dev libjpeg-turbo8-dev libpng-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    && \
    # --- Build Core VapourSynth Plugins --- \
    # All plugins will be installed to ${VS_PLUGIN_DIR} \
    \
    # mvtools
    git clone --depth=1 https://github.com/dubhater/vapoursynth-mvtools.git /tmp/mvtools && \
    cd /tmp/mvtools && \
    meson setup build --buildtype=release --prefix=/usr/local --libdir="${VS_PLUGIN_DIR}" && \
    ninja -C build && ninja -C build install && \
    \
    # nnedi3cl (OpenCL-based interpolator used by QTGMC)
    git clone --depth=1 https://github.com/HomeOfVapourSynthEvolution/VapourSynth-NNEDI3CL.git /tmp/nnedi3cl && \
    cd /tmp/nnedi3cl && \
    meson setup build --buildtype=release --prefix=/usr/local --libdir="${VS_PLUGIN_DIR}" && \
    ninja -C build && ninja -C build install && \
    \
    # fmtconv (use AUTOTOOLS in build/unix — NOT CMake here)
    git clone --depth=1 https://gitlab.com/EleonoreMizo/fmtconv.git /tmp/fmtconv && \
    cd /tmp/fmtconv/build/unix && \
    ./autogen.sh && \
    ./configure --prefix=/usr/local --libdir="${VS_PLUGIN_DIR}" && \
    make -j"$(nproc)" && make install && \
    \
    # TIVTC (fieldmatch/decimate for IVTC inside VS)
    git clone --depth=1 https://github.com/dubhater/vapoursynth-tivtc.git /tmp/vs_tivtc && \
    cd /tmp/vs_tivtc && \
    ./autogen.sh && \
    ./configure --prefix=/usr/local --libdir="${VS_PLUGIN_DIR}" && \
    make -j"$(nproc)" && make install && \
    \
    # ---- BM3D-CUDA (VapourSynth-BM3DCUDA) ----
    mkdir -p /tmp/bm3d && \
    curl -L https://github.com/WolframRhodium/VapourSynth-BM3DCUDA/archive/refs/tags/R2.15.tar.gz \
      | tar -xz -C /tmp/bm3d --strip-components=1 && \
    find /tmp/bm3d -name CMakeLists.txt -exec \
      sed -i 's/CUDA::nvrtc_static/CUDA::nvrtc/g; s/CUDA::nvrtc-builtins_static/CUDA::nvrtc-builtins/g; s/nvrtc_static/nvrtc/g; s/nvrtc-builtins_static/nvrtc-builtins/g' {} + && \
    cmake -S /tmp/bm3d -B /tmp/bm3d/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_INSTALL_LIBDIR="${VS_PLUGIN_DIR}" \
      -DVAPOURSYNTH_INCLUDE_DIRECTORY=/usr/local/include/vapoursynth \
      -DCMAKE_CUDA_ARCHITECTURES="86" \
      -DCMAKE_CUDA_FLAGS="--use_fast_math" && \
    cmake --build /tmp/bm3d/build -j"$(nproc)" && \
    cmake --install /tmp/bm3d/build && \
    \
    # --- Cleanup --- \
    cd / && rm -rf /tmp/* && \
    apt-get purge -y --auto-remove $BUILD_DEPS && \
    rm -rf /var/lib/apt/lists/* && \
    ldconfig

# --- Python side: QTGMC script + CUDA wrappers for A/B ---
RUN python -m pip install --no-cache-dir --upgrade pip setuptools wheel vsutil && \
    python -m pip install --no-cache-dir \
    havsfunc \
    vsrealesrgan vsbasicvsrpp basicsr facexlib gfpgan tqdm scipy && \
    PYV=$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")') && \
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


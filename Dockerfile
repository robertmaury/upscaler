# ---------------------------------------------
# Child layer: add VS plugins & Python wrappers
# ---------------------------------------------
FROM pifroggi/vapoursynth:2025_09_05
ARG DEBIAN_FRONTEND=noninteractive

# Build deps (tiny set) + OpenCL runtime (for NNEDI3CL)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential meson ninja-build cmake pkg-config \
    python3-dev cython3 \
    ocl-icd-libopencl1 ocl-icd-opencl-dev \
    libzimg-dev libjpeg-turbo8-dev libpng-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
 && rm -rf /var/lib/apt/lists/*

# Make sure pkg-config & runtime can see VapourSynth (installed in base)
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
ENV VAPOURSYNTH_PLUGIN_PATH=/usr/local/lib/vapoursynth:/usr/local/lib/x86_64-linux-gnu/vapoursynth

ENV CUDA_HOME=/usr/local/cuda
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/lib:/usr/local/lib:${LD_LIBRARY_PATH}
ENV CUDA_PATH=/usr/local/cuda


# --- Core plugins required for QTGMC/IVTC ---

# mvtools
RUN git clone --depth=1 https://github.com/dubhater/vapoursynth-mvtools.git /tmp/mvtools \
 && cd /tmp/mvtools && meson setup build --buildtype=release --prefix=/usr/local \
 && ninja -C build && ninja -C build install && rm -rf /tmp/mvtools

# nnedi3cl (OpenCL-based interpolator used by QTGMC)
RUN git clone --depth=1 https://github.com/HomeOfVapourSynthEvolution/VapourSynth-NNEDI3CL.git /tmp/nnedi3cl \
 && cd /tmp/nnedi3cl && meson setup build --buildtype=release --prefix=/usr/local \
 && ninja -C build && ninja -C build install && rm -rf /tmp/nnedi3cl

# fmtconv (use AUTOTOOLS in build/unix — NOT CMake here)
RUN git clone --depth=1 https://gitlab.com/EleonoreMizo/fmtconv.git /tmp/fmtconv \
 && cd /tmp/fmtconv/build/unix \
 && ./autogen.sh \
 && ./configure --prefix=/usr/local --libdir=/usr/local/lib \
 && make -j"$(nproc)" && make install \
 && cd / && rm -rf /tmp/fmtconv

# ---- BM3D-CUDA (VapourSynth-BM3DCUDA) ----
# Links to shared NVRTC libs (no static dev pkgs needed)
RUN mkdir -p /tmp/bm3d && \
    curl -L https://github.com/WolframRhodium/VapourSynth-BM3DCUDA/archive/refs/tags/R2.15.tar.gz \
      | tar -xz -C /tmp/bm3d --strip-components=1 && \
    # swap *both* namespaced and bare static targets to shared ones across all CMakeLists
    find /tmp/bm3d -name CMakeLists.txt -exec \
      sed -i 's/CUDA::nvrtc_static/CUDA::nvrtc/g; s/CUDA::nvrtc-builtins_static/CUDA::nvrtc-builtins/g; s/nvrtc_static/nvrtc/g; s/nvrtc-builtins_static/nvrtc-builtins/g' {} + && \
    cmake -S /tmp/bm3d -B /tmp/bm3d/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_INSTALL_LIBDIR=lib/vapoursynth \
      -DVAPOURSYNTH_INCLUDE_DIRECTORY=/usr/local/include/vapoursynth \
      -DCMAKE_CUDA_ARCHITECTURES="86" \
      -DCMAKE_CUDA_FLAGS="--use_fast_math" && \
    cmake --build /tmp/bm3d/build -j"$(nproc)" && \
    cmake --install /tmp/bm3d/build && \
    rm -rf /tmp/bm3d && ldconfig


# TIVTC (fieldmatch/decimate for IVTC inside VS) — optional but recommended
RUN mkdir -p /tmp/vs_tivtc && \
    curl -L https://github.com/dubhater/vapoursynth-tivtc/archive/refs/heads/master.tar.gz \
      | tar -xz -C /tmp/vs_tivtc --strip-components=1 && \
    cd /tmp/vs_tivtc && \
    meson setup build --buildtype=release --prefix=/usr/local --libdir=lib && \
    ninja -C build && ninja -C build install && \
    cd / && rm -rf /tmp/vs_tivtc

# (Your base already installed BestSource, FFMS2, L-SMASH Works, zimg, VS core)

# --- Python side: QTGMC script + CUDA wrappers for A/B ---

# QTGMC function via havsfunc, plus VS wrappers for ESRGAN/BasicVSR++ on CUDA
RUN python -m pip install --no-cache-dir --upgrade pip setuptools wheel \
 && python -m pip install --no-cache-dir \
    havsfunc \
    vsrealesrgan vsbasicvsrpp basicsr facexlib gfpgan tqdm scipy 

RUN python -m pip install --no-cache-dir --upgrade vsutil && \
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


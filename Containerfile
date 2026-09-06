# Fedora amd64 crossbuild container: linux + windows + macos from
# one image. osxcross does not build inside this image — it is
# downloaded as a release asset (see scripts/build-osxcross-package.sh)
# because Xcode SDK redistribution is Apple-license-gated.

FROM registry.fedoraproject.org/fedora:41

# Native + windows cross toolchains, plus every dep godot's SConstruct
# expects on linuxbsd. sccache + scons + zstd for the cache path; git
# because osxcross patches ship as a repo; xz + xar because the Xcode
# SDK extraction path needs both.
RUN dnf -y install \
      gcc gcc-c++ clang lld llvm cmake make scons pkgconf-pkg-config \
      python3 python3-pip \
      zstd git-core xz xar cpio \
      mingw64-gcc mingw64-gcc-c++ mingw64-winpthreads-static \
      mingw64-pkg-config \
      libX11-devel libXcursor-devel libXinerama-devel libXrandr-devel \
      libXi-devel mesa-libGL-devel mesa-libGLU-devel \
      alsa-lib-devel pulseaudio-libs-devel systemd-devel \
      yasm nasm \
      libstdc++-static \
      ca-certificates jq \
    && dnf clean all

# sccache comes from Homebrew on Linux — the workspace convention is
# `brew install sccache` on both macOS and Linux desks, so this
# container matches. Homebrew requires a non-root user, so we set up
# a `builder` user and put brew's shims first on PATH.
RUN dnf -y install procps-ng file which sudo shadow-utils \
    && dnf clean all \
    && useradd -m -u 1000 -s /bin/bash builder \
    && echo "builder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builder

USER builder
WORKDIR /home/builder
RUN NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    && /home/linuxbrew/.linuxbrew/bin/brew install sccache

USER root

# Where the packaged osxcross toolchain lands on first use.
ENV OSXCROSS_ROOT=/opt/osxcross \
    PATH=/home/linuxbrew/.linuxbrew/bin:/opt/osxcross/bin:/usr/local/bin:/usr/bin:/bin

# Cache mount points — bound in by scripts/build.sh from the host.
RUN mkdir -p /cache/sccache /cache/scons /work /opt/osxcross
VOLUME ["/cache/sccache", "/cache/scons", "/work"]

# sccache wraps the compiler for every platform. When the Tigris
# env vars are supplied (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
# / AWS_ENDPOINT_URL_S3 / SCCACHE_BUCKET) sccache writes to the
# shared S3 bucket instead of the local /cache/sccache disk; the
# disk path stays as the offline fallback. Bucket cap is enforced
# on the Tigris side (20 GB per the operator's directive).
ENV SCCACHE_DIR=/cache/sccache \
    SCCACHE_CACHE_SIZE=20G \
    CC="sccache gcc" \
    CXX="sccache g++"

WORKDIR /work
ENTRYPOINT ["/bin/bash"]

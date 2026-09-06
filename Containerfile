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

# sccache is not in Fedora repos; pull the upstream x86_64 tarball
# from its GitHub release. Pin the version so a rebuild doesn't drift.
ARG SCCACHE_VERSION=0.8.2
RUN curl -fsSL -o /tmp/sccache.tgz \
      "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/sccache-v${SCCACHE_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && tar -xzf /tmp/sccache.tgz -C /tmp \
    && install -m 0755 /tmp/sccache-v${SCCACHE_VERSION}-x86_64-unknown-linux-musl/sccache /usr/local/bin/sccache \
    && rm -rf /tmp/sccache.tgz /tmp/sccache-v${SCCACHE_VERSION}-x86_64-unknown-linux-musl

# Where the packaged osxcross toolchain lands on first use.
ENV OSXCROSS_ROOT=/opt/osxcross \
    PATH=/opt/osxcross/bin:/usr/local/bin:/usr/bin:/bin

# Cache mount points — bound in by scripts/build.sh from the host.
RUN mkdir -p /cache/sccache /cache/scons /work /opt/osxcross
VOLUME ["/cache/sccache", "/cache/scons", "/work"]

# sccache wraps the compiler for every platform. Scons cache lives on
# the same host under /cache/scons and is passed to scons via
# cache_path= in the build entrypoint.
ENV SCCACHE_DIR=/cache/sccache \
    SCCACHE_CACHE_SIZE=20G \
    CC="sccache gcc" \
    CXX="sccache g++"

WORKDIR /work
ENTRYPOINT ["/bin/bash"]

#!/usr/bin/env bash
# Run a scons build inside the crossbuild-fedora container. Every
# workspace project is expected to have a top-level SConstruct that
# godot's flags apply to (this covers godot itself and its module
# checkouts).
#
# Usage: ./scripts/build.sh <platform> <project-dir> [extra scons args...]
#   platform: linux-amd64 | windows-amd64 | macos-arm64 | macos-x86_64

set -euo pipefail

PLATFORM="${1:?platform required}"
PROJECT="${2:?project dir required}"
shift 2
EXTRA=("$@")

PROJECT_ABS=$(cd "$PROJECT" && pwd)
[ -f "$PROJECT_ABS/SConstruct" ] || {
  echo "No SConstruct at $PROJECT_ABS" >&2; exit 1;
}

REPO="v-sekai-fabric/crossbuild-fedora"
IMAGE="ghcr.io/v-sekai-fabric/crossbuild-fedora:latest"
HOST_CACHE=$HOME/.cache/crossbuild-fedora
mkdir -p "$HOST_CACHE/sccache" "$HOST_CACHE/scons" "$HOST_CACHE/osxcross"

# Pull the published image from ghcr.io. Fall back to a local build
# only when the pull fails — the ghcr image is the reference, a local
# build is the escape hatch for offline / pre-publish work.
podman image exists "$IMAGE" \
  || podman pull "$IMAGE" \
  || podman build --platform linux/amd64 -t "$IMAGE" \
       -f "$(dirname "$0")/../Containerfile" "$(dirname "$0")/.."

# Pull the packaged osxcross toolchain the first time a macos target
# is asked for. gh unauthenticated pulls work on public releases;
# authenticate for private ones with GH_TOKEN in the environment.
if [[ "$PLATFORM" == macos-* ]] && [ ! -x "$HOST_CACHE/osxcross/bin/o64-clang" ]; then
  echo "Fetching packaged osxcross from $REPO dev-latest ..."
  TAR=$(mktemp --suffix=.tar.zst)
  gh release download dev-latest --repo "$REPO" \
     --pattern 'osxcross-*.tar.zst' -O "$TAR"
  tar --zstd -xf "$TAR" -C "$HOST_CACHE" --strip-components=1
  rm -f "$TAR"
fi

case "$PLATFORM" in
  linux-amd64)
    SCONS_ARGS=(platform=linuxbsd arch=x86_64)
    ;;
  windows-amd64)
    SCONS_ARGS=(platform=windows arch=x86_64 use_mingw=yes)
    ;;
  macos-arm64)
    SCONS_ARGS=(platform=macos arch=arm64 osxcross_sdk=darwin23)
    ;;
  macos-x86_64)
    SCONS_ARGS=(platform=macos arch=x86_64 osxcross_sdk=darwin23)
    ;;
  *) echo "Unknown platform: $PLATFORM" >&2; exit 1 ;;
esac

# `template_release`, gdscript off, size-optimized: matches the
# starforged shipping profile. Callers can override via EXTRA args.
podman run --rm -it \
  -v "$PROJECT_ABS":/work \
  -v "$HOST_CACHE/sccache":/cache/sccache \
  -v "$HOST_CACHE/scons":/cache/scons \
  -v "$HOST_CACHE/osxcross":/opt/osxcross:ro \
  -e OSXCROSS_ROOT=/opt/osxcross \
  -e PATH=/opt/osxcross/bin:/usr/local/bin:/usr/bin:/bin \
  "$IMAGE" -c "
    sccache --start-server || true
    sccache --show-stats | head -6
    scons -j\$(nproc) \
      target=template_release module_gdscript_enabled=no tools=no \
      optimize=size cache_path=/cache/scons cache_show=yes \
      ${SCONS_ARGS[*]} ${EXTRA[*]}
    sccache --show-stats | head -14
  "

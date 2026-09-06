#!/usr/bin/env bash
# Build the osxcross toolchain once and publish it as a release asset
# on this repo's dev-latest release. Every crossbuild-fedora container
# downloads that asset instead of rebuilding osxcross per session.
#
# Usage: ./scripts/build-osxcross-package.sh /path/to/Xcode_15.4.xip
#
# Requires: the container image already built, gh CLI logged in.

set -euo pipefail

XCODE_XIP="${1:?Xcode .xip path required}"
[ -f "$XCODE_XIP" ] || { echo "Not a file: $XCODE_XIP" >&2; exit 1; }

REPO="v-sekai-fabric/crossbuild-fedora"
OSXCROSS_REPO="https://github.com/tpoechtrager/osxcross"
OSXCROSS_REF="master"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Run the toolchain build inside the container so the produced binaries
# link against Fedora's glibc, not the host's. The container writes the
# packaged tarball to $WORK/out, which the host then uploads.
mkdir -p "$WORK/out" "$WORK/in"
cp "$XCODE_XIP" "$WORK/in/xcode.xip"

podman run --rm \
  -v "$WORK/in:/in:ro" \
  -v "$WORK/out:/out" \
  --entrypoint /bin/bash \
  crossbuild-fedora:latest -c '
set -euo pipefail
cd /tmp
git clone --depth=1 https://github.com/tpoechtrager/osxcross
cd osxcross

# Extract the SDK from the Xcode .xip. tools/gen_sdk_package_pbzx.sh
# handles both .xip and .app inputs.
./tools/gen_sdk_package_pbzx.sh /in/xcode.xip
SDK_TARBALL=$(ls MacOSX*.sdk.tar.* | head -1)
[ -n "$SDK_TARBALL" ] || { echo "SDK extraction failed" >&2; exit 1; }
mv "$SDK_TARBALL" tarballs/

UNATTENDED=1 SDK_VERSION=$(echo "$SDK_TARBALL" | sed -E "s/MacOSX([0-9.]+).sdk.*/\1/") \
  ./build.sh
UNATTENDED=1 ./build_compiler_rt.sh || true

# Package: /opt/osxcross/{bin,lib,SDK} — installs to /opt on target.
mkdir -p /opt/osxcross
cp -a target/. /opt/osxcross/

SDK_VER=$(basename target/SDK/MacOSX*.sdk | sed -E "s/MacOSX([0-9.]+).sdk/\1/")
OSX_SHA=$(git rev-parse --short HEAD)
TAR=/out/osxcross-sdk${SDK_VER}-${OSX_SHA}.tar.zst

tar --zstd -C /opt -cf "$TAR" osxcross
ls -lh "$TAR"
'

TAR=$(ls "$WORK/out"/osxcross-*.tar.zst | head -1)
[ -f "$TAR" ] || { echo "Package build did not produce a tarball" >&2; exit 1; }

# Rolling dev-latest release. Delete the prior asset with this name so
# the upload does not collide; the tag stays pointed at the newest push.
ASSET_NAME=$(basename "$TAR")
gh release view dev-latest --repo "$REPO" >/dev/null 2>&1 \
  || gh release create dev-latest --repo "$REPO" --prerelease \
       --title "Dev — latest" --notes "Rolling dev-stage assets"

gh release delete-asset dev-latest "$ASSET_NAME" --repo "$REPO" --yes 2>/dev/null || true
gh release upload dev-latest "$TAR" --repo "$REPO"

# Also publish as an immutable snapshot so a downstream can pin.
SNAP_TAG=$(echo "$ASSET_NAME" | sed 's/\.tar\.zst$//')
gh release create "$SNAP_TAG" "$TAR" --repo "$REPO" --prerelease \
  --title "$SNAP_TAG" \
  --notes "Immutable snapshot of the osxcross toolchain built from Xcode SDK. Pinned SHA + SDK version in the filename."

echo
echo "Published: $ASSET_NAME"
echo "  rolling: https://github.com/$REPO/releases/tag/dev-latest"
echo "  snapshot: https://github.com/$REPO/releases/tag/$SNAP_TAG"

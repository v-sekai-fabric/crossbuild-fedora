#!/usr/bin/env bash
# Build the crossbuild-fedora image and push it to
# ghcr.io/v-sekai-fabric/crossbuild-fedora. Runs locally (no GHA);
# every workspace machine `podman pull`s from ghcr rather than
# rebuilding the image itself.
#
# Requires: podman logged in to ghcr.io
#   echo $GH_PAT | podman login ghcr.io -u <gh-user> --password-stdin
# The PAT needs `write:packages`.

set -euo pipefail

IMAGE=ghcr.io/v-sekai-fabric/crossbuild-fedora
HERE=$(cd "$(dirname "$0")/.." && pwd)

# Content-hash tag so a rebuild that changes the Containerfile lands
# under a new name; `latest` moves too. The hash covers every input
# the container definition depends on.
HASH=$(cat "$HERE/Containerfile" "$HERE/scripts/build-osxcross-package.sh" \
        "$HERE/scripts/build.sh" | sha256sum | cut -c1-12)

podman build \
  --platform linux/amd64 \
  -t "$IMAGE:$HASH" \
  -t "$IMAGE:latest" \
  -f "$HERE/Containerfile" \
  "$HERE"

podman push "$IMAGE:$HASH"
podman push "$IMAGE:latest"

echo
echo "Pushed:"
echo "  $IMAGE:$HASH"
echo "  $IMAGE:latest"

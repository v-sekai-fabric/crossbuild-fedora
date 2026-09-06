# crossbuild-fedora

One Fedora amd64 container that cross-builds mac / windows / linux
targets from any host that can run podman or docker. All local
builds in this workspace go through it; nothing runs in GitHub
Actions.

The container carries three toolchains:

- **linux-amd64**: Fedora's own `gcc` / `clang`
- **windows-amd64**: `mingw64-gcc` + `mingw64-g++` from Fedora's repos
- **macos-arm64 / macos-x86_64**: `osxcross` (patched clang + cctools),
  pre-built once and shipped as a release asset — the container
  downloads it on first run instead of rebuilding

`sccache` wraps every compiler and, when Bao supplies Tigris
credentials, writes to the shared `weftspun-sccache` S3 bucket
(20 GB cap) so every desk pulls from the same object cache. The
local `~/.cache/crossbuild-fedora/sccache` disk stays as the
offline fallback. `scons`' own `cache_path=` catches whole-object
hits above sccache, on the same host cache dir.

Fetch is automatic: with `BAO_ADDR` + `BAO_TOKEN` in the shell,
`build.sh` reads `secret/tigris/sccache` and passes the AWS env
into podman. Without them, the local disk cache is used silently.

## Where the image lives

`ghcr.io/v-sekai-fabric/crossbuild-fedora:latest` — pulled on first
`build.sh` run. Content-hash tags (`:<sha-first-12>`) alongside `latest`
give you a pinnable name when a shipping build should not float.
Pushes are local (see `scripts/push-image.sh`); there is no GHA on
this repo.

## Prereqs

- podman (Fedora / Linux) or docker (macOS with Colima / Rancher Desktop)
- ~30 GB free disk (osxcross toolchain + Xcode SDK + build caches)
- A Xcode Command Line Tools `.dmg` or Xcode `.xip` you legally have,
  once, when you build the osxcross package. After that the packaged
  toolchain is what everyone uses.

## Build a project

```sh
./scripts/build.sh macos-arm64 ../../3-interactor/entities-godot-sandbox
./scripts/build.sh windows-amd64 ../../3-interactor/entities-godot-sandbox
./scripts/build.sh linux-amd64 ../../3-interactor/entities-godot-sandbox
```

The script:

1. Builds (or reuses) the `crossbuild-fedora:latest` image
2. Downloads `osxcross-<tag>.tar.zst` from this repo's `dev-latest`
   release if the container doesn't already have it
3. Runs `scons` with the platform-appropriate flags and both caches
   mounted
4. Drops the built binary into `<project>/bin/`

## Build and publish the osxcross package (one-time per SDK version)

```sh
./scripts/build-osxcross-package.sh /path/to/Xcode_15.4.xip
```

Extracts the SDK, cross-compiles the osxcross toolchain, packages it
as `osxcross-<sdk-version>-<osxcross-sha>.tar.zst`, and uploads it to
this repo's `dev-latest` GitHub release. Every subsequent container
build pulls that asset instead of rebuilding osxcross.

## Why this container and not `docker.io/library/*`

- **Fedora** — the workspace already runs Fedora on the linux side of
  the hexagon; toolchain versions match what shipping targets already
  build against.
- **amd64** — mingw64 packages and osxcross both target amd64 hosts;
  running amd64 in an emulated slot on Apple Silicon is measurably
  slower but keeps one image for every developer.
- **Not a plain Ubuntu / Debian** — mingw64 support in Fedora repos is
  more current, and the container stays smaller than the equivalent
  apt image.

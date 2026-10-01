#!/usr/bin/env bash
# Builds the Keycard CAP from source in a throwaway container. Called by install.sh.
#
#   build-cap.sh <tag-or-branch>
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

REF=${1:?usage: build-cap.sh <tag-or-branch>}

step "Keycard applet, built from source ($REF)"

if [ -f "$WORK/keycard.cap" ] && [ "$(cat "$WORK/cap-source" 2>/dev/null)" = "build $REF" ]; then
  echo "already built (./flash.sh --cleanup forces a rebuild)"
  exit 0
fi

find_runtime() {
  local runtime installed=
  for runtime in docker podman nerdctl; do
    command -v "$runtime" >/dev/null || continue
    installed=$runtime
    if "$runtime" info >/dev/null 2>&1; then
      echo "$runtime"
      return
    fi
  done
  if [ -n "$installed" ]; then
    die "$installed is installed but not running. Start it and run again."
  fi
  die "building from source needs docker or podman. Install one and run again:
  https://docs.docker.com/get-docker/
  https://podman.io/docs/installation"
}

runtime=$(find_runtime)
echo "using $runtime"

# Written before the pull so an interrupted pull is still cleaned up.
if ! "$runtime" image inspect "$BUILD_IMAGE" >/dev/null 2>&1; then
  mkdir -p "$WORK"
  grep -qxF "$runtime $BUILD_IMAGE" "$PULLED_IMAGES" 2>/dev/null || echo "$runtime $BUILD_IMAGE" >>"$PULLED_IMAGES"
fi

mkdir -p "$WORK/build"
cp "$ROOT/scripts/container-build.sh" "$WORK/build/"

"$runtime" run --rm \
  -v "$WORK/build:/build$OS_VOLUME_SUFFIX" \
  -e REF="$REF" \
  -e SOURCE_REPO="$SOURCE_REPO" \
  -e OWNER="$(os_container_owner "$runtime")" \
  "$BUILD_IMAGE" bash /build/container-build.sh

cp "$WORK/build/src/build/javacard/im/status/keycard/javacard/keycard.cap" "$WORK/keycard.cap"
cp "$WORK/build/src/keycard-math/im/status/keycard/math/javacard/math.cap" "$WORK/math.cap"
echo "build $REF" >"$WORK/cap-source"

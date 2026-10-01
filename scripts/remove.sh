#!/usr/bin/env bash
# Undoes install.sh: deletes work/ and any container image that was pulled for a source build.
# Images that were on the machine before are left alone.
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

[ -d "$WORK" ] || exit 0

step "Removing what was installed"

image_left=0
if [ -f "$PULLED_IMAGES" ]; then
  while read -r runtime image; do
    "$runtime" image rm "$image" >/dev/null 2>&1 || true
    if ! "$runtime" info >/dev/null 2>&1 || "$runtime" image inspect "$image" >/dev/null 2>&1; then
      echo "warning: could not remove the image $image. Start $runtime and run: ./flash.sh --cleanup" >&2
      image_left=1
    else
      echo "removed image $image"
    fi
  done <"$PULLED_IMAGES"
fi

if [ "$image_left" = 1 ]; then
  # Keep the list so a later --cleanup still knows which image to remove.
  find "$WORK" -mindepth 1 -maxdepth 1 ! -name "$(basename "$PULLED_IMAGES")" -exec rm -rf {} +
  exit 1
fi

rm -rf "$WORK"
echo "removed $WORK"

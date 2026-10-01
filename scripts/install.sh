#!/usr/bin/env bash
# Puts everything the flash needs into work/. remove.sh undoes it.
#
#   install.sh               download the released Keycard CAP
#   install.sh --build       build the CAP from source in a container
#   install.sh --ref <ref>   same, from another tag or branch
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

BUILD=0
REF=$KEYCARD_VERSION
while [ $# -gt 0 ]; do
  case $1 in
    --build) BUILD=1 ;;
    --ref)
      [ $# -ge 2 ] || die "--ref needs a tag or branch"
      BUILD=1
      REF=$2
      shift
      ;;
    *) die "install.sh: unknown option $1" ;;
  esac
  shift
done

mkdir -p "$WORK"

step "GlobalPlatformPro (talks to the card manager)"
fetch "$GP_URL" "$WORK/gp.jar" "$GP_SHA256"

if [ "$BUILD" = 1 ]; then
  "$ROOT/scripts/build-cap.sh" "$REF"
else
  step "Keycard $KEYCARD_VERSION applet"
  rm -f "$WORK/cap-source"
  fetch "$CAP_URL" "$WORK/keycard.cap" "$CAP_SHA256"
  fetch "$MATH_URL" "$WORK/math.cap" "$MATH_SHA256"
fi

step "Java"
if java=$(find_java); then
  echo "using $java"
else
  echo "no JDK 17 or newer on this machine, putting a private one in work/"
  fetch "$JDK_BASE_URL/$OS_JDK_ARCHIVE" "$WORK/jdk.tar.gz" "$OS_JDK_SHA256"
  mkdir -p "$WORK/jdk"
  tar -xzf "$WORK/jdk.tar.gz" -C "$WORK/jdk" --strip-components 1
  rm "$WORK/jdk.tar.gz"
  java=$(find_java) || die "the downloaded JDK does not run on this machine"
  echo "using $java"
fi

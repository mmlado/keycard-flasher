# Settings and helpers shared by every script. Sourced, never run.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK="$ROOT/work"
PULLED_IMAGES="$WORK/pulled-images"

# GlobalPlatform key of Keycard development cards (status-keycard README).
GP_KEY=${GP_KEY:-c212e073ff8b4bbfaff4de8ab655221f}

KEYCARD_VERSION=4.0
PACKAGE_AID=A0000008040001
MATH_AID=A0000008040002

GP_URL=https://github.com/martinpaljak/GlobalPlatformPro/releases/download/v25.10.20/gp.jar
GP_SHA256=c88e0c5093032ec4571571f5397b6174e56bf632667950fa5bb716338534b122
CAP_URL=https://github.com/keycard-tech/status-keycard/releases/download/$KEYCARD_VERSION/keycard_v$KEYCARD_VERSION.cap
CAP_SHA256=c15a26d63c5ac1bdc6420b77879f58e85bd76133b847a0807d98cb43135e446e
MATH_URL=https://raw.githubusercontent.com/keycard-tech/status-keycard/$KEYCARD_VERSION/keycard-math/im/status/keycard/math/javacard/math.cap
MATH_SHA256=3a331eb96a6f4b58432a9f155d16c49df3049b4942eebafccb45c82644d3ac28

# The archive name and checksum for this machine are in macos.sh and linux.sh.
JDK_BASE_URL=https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20.1%2B1

SOURCE_REPO=https://github.com/keycard-tech/status-keycard
# status-keycard builds with JDK 11. Fully qualified because podman does not guess the registry.
BUILD_IMAGE=docker.io/library/eclipse-temurin:11-jdk

die() {
  echo "error: $*" >&2
  exit 1
}

step() {
  echo
  echo "== $*"
}

case "$(uname -s)" in
  Darwin) . "$ROOT/scripts/lib/macos.sh" ;;
  Linux) . "$ROOT/scripts/lib/linux.sh" ;;
  *) die "unsupported system: $(uname -s)" ;;
esac

# fetch <url> <destination> <sha256>
fetch() {
  local url=$1 dest=$2 sha256=$3
  if [ -f "$dest" ] && [ "$(os_sha256 "$dest")" = "$sha256" ]; then
    echo "$(basename "$dest") is already there"
    return
  fi
  echo "downloading $(basename "$dest")"
  # A stalled connection would otherwise hang forever: give up after 30s under 1 KB/s, then retry.
  curl -fL --progress-bar --connect-timeout 20 --speed-limit 1024 --speed-time 30 --retry 3 -o "$dest" "$url" ||
    die "could not download $url"
  if [ "$(os_sha256 "$dest")" != "$sha256" ]; then
    rm -f "$dest"
    die "checksum mismatch for $url"
  fi
}

# KeycardTool.java runs straight from source, which needs the compiler that only a JDK has.
java_is_usable() {
  local java=$1 major
  [ -x "$java" ] || return 1
  major=$("$java" -version 2>&1 | sed -n '1s/.*version "\([0-9]*\).*/\1/p')
  [ "${major:-0}" -ge 17 ] || return 1
  "$java" --list-modules 2>/dev/null | grep -q '^jdk.compiler@'
}

# Prints the java to use: the system one when it is good enough, else the private one in work/.
find_java() {
  local candidate
  while IFS= read -r candidate; do
    if java_is_usable "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done < <(
    os_system_java_candidates
    echo "$WORK/jdk/$OS_JDK_JAVA"
  )
  return 1
}

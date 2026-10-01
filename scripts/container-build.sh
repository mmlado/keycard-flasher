#!/usr/bin/env bash
# Runs inside the build container, never on the host. Started by build-cap.sh with /build mounted
# from work/build and REF, SOURCE_REPO and OWNER set.
set -euo pipefail

give_files_to_host_user() {
  if [ -n "${OWNER:-}" ]; then
    chown -R "$OWNER" /build
  fi
}
trap give_files_to_host_user EXIT

# Gradle's cache goes into the mounted folder so remove.sh deletes it with everything else.
export GRADLE_USER_HOME=/build/gradle-home
# Gradle's default heap is too small: compiling buildSrc fails with "Java heap space".
export GRADLE_OPTS=-Dorg.gradle.jvmargs=-Xmx1g
export DEBIAN_FRONTEND=noninteractive
# Without these git waits forever on a stalled connection: give up after 30s under 1 KB/s.
export GIT_HTTP_LOW_SPEED_LIMIT=1024
export GIT_HTTP_LOW_SPEED_TIME=30

retry() {
  local attempt
  for attempt in 1 2 3; do
    if "$@"; then
      return 0
    fi
    echo "attempt $attempt of 3 failed: $*" >&2
    sleep $((attempt * 15))
  done
  return 1
}

install_git() {
  apt-get update -qq && apt-get install -y -qq --no-install-recommends git ca-certificates >/dev/null
}

# Only the JavaCard SDKs are needed to build. The other submodule, jcardsim, is for the tests.
fetch_source() {
  rm -rf /build/src &&
    git -c advice.detachedHead=false clone --branch "$REF" --depth 1 "$SOURCE_REPO" /build/src &&
    git -C /build/src submodule update --init --depth 1 sdks
}

retry install_git
retry fetch_source

cd /build/src
./gradlew --no-daemon convertJavacard

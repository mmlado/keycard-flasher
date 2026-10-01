# macOS-only parts. Sourced by common.sh. linux.sh defines the same names.

case "$(uname -m)" in
  arm64)
    OS_JDK_ARCHIVE=OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.20.1_1.tar.gz
    OS_JDK_SHA256=196d13ba5f10414bef7f6a05a9b3f00edacb18ebacef2b99485db9e2ee18f0e8
    ;;
  x86_64)
    OS_JDK_ARCHIVE=OpenJDK17U-jdk_x64_mac_hotspot_17.0.20.1_1.tar.gz
    OS_JDK_SHA256=c01975da12ed4235250ff891fe8bba73a9e73037d444b269c9d0922b5dbc8e0a
    ;;
  *) die "unsupported Mac: $(uname -m)" ;;
esac

# Where java sits inside the unpacked JDK archive.
OS_JDK_JAVA=Contents/Home/bin/java

# Appended to the container volume mount.
OS_VOLUME_SUFFIX=

os_sha256() {
  shasum -a 256 "$1" | cut -d' ' -f1
}

os_system_java_candidates() {
  if [ -n "${JAVA_HOME:-}" ]; then
    echo "$JAVA_HOME/bin/java"
  fi
  local on_path
  on_path=$(command -v java || true)
  if [ "$on_path" = /usr/bin/java ]; then
    # /usr/bin/java is Apple's stub: with no JDK registered it opens an install dialog instead of failing.
    if /usr/libexec/java_home >/dev/null 2>&1; then
      echo "$(/usr/libexec/java_home)/bin/java"
    fi
  elif [ -n "$on_path" ]; then
    echo "$on_path"
  fi
}

# macOS has its smart card service built in.
os_check_reader_service() {
  :
}

# Container runtimes on macOS already map files in the mounted folder to this user.
os_container_owner() {
  :
}

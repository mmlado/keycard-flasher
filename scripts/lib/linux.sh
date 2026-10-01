# Linux-only parts. Sourced by common.sh. macos.sh defines the same names.

case "$(uname -m)" in
  aarch64 | arm64)
    OS_JDK_ARCHIVE=OpenJDK17U-jdk_aarch64_linux_hotspot_17.0.20.1_1.tar.gz
    OS_JDK_SHA256=457b57af8f9c93ec39080bb8c764f559dc8c89a6da1a39d718a400b7890d3e41
    ;;
  x86_64)
    OS_JDK_ARCHIVE=OpenJDK17U-jdk_x64_linux_hotspot_17.0.20.1_1.tar.gz
    OS_JDK_SHA256=3808d1d15e3ec6bd5b84057fb5d84c33d8a1536a258146bcea2e603fc726e08e
    ;;
  *) die "unsupported machine: $(uname -m)" ;;
esac

# Where java sits inside the unpacked JDK archive.
OS_JDK_JAVA=bin/java

# Appended to the container volume mount. Without the SELinux relabel the container cannot write to it.
OS_VOLUME_SUFFIX=:Z

os_sha256() {
  sha256sum "$1" | cut -d' ' -f1
}

os_system_java_candidates() {
  if [ -n "${JAVA_HOME:-}" ]; then
    echo "$JAVA_HOME/bin/java"
  fi
  command -v java || true
}

# The reader is reached through pcscd. It needs root to install, so that is left to the user.
os_check_reader_service() {
  if [ ! -S /run/pcscd/pcscd.comm ]; then
    die "the smart card service (pcscd) is not running. Install and start it, for example:
  sudo apt install pcscd && sudo systemctl enable --now pcscd.socket"
  fi
}

# os_container_owner <runtime>
# Rootful docker leaves root-owned files in the mounted folder, which remove.sh could not delete.
# Rootless runtimes already map the container's root to this user.
os_container_owner() {
  local runtime=$1
  if [ "$runtime" = podman ] && [ "$(id -u)" != 0 ]; then
    return
  fi
  if "$runtime" info 2>/dev/null | grep -qi rootless; then
    return
  fi
  echo "$(id -u):$(id -g)"
}

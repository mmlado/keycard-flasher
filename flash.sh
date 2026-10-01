#!/usr/bin/env bash
# Flashes the Keycard applet onto the development card in the reader.
# The work is done by the scripts in scripts/: install.sh, flash-card.sh, remove.sh.
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)/scripts"

usage() {
  cat <<EOF
Usage: ./flash.sh [options]

Installs what it needs into work/, flashes the card in the reader, then removes
everything it installed.

  (no option)   flash Keycard 4.0 from the released CAP file
  --build       build the CAP from source in a container (needs docker or podman)
  --ref <ref>   build from another tag or branch (implies --build)
  --keep        do not remove anything afterwards; use this when flashing several cards
  --cleanup     only remove what earlier runs installed
  --dry-run     do everything except touch a card
  --yes         do not ask before wiping a card that has a PIN set
  -h, --help    show this help

Several cards:
  ./flash.sh --keep      once per card
  ./flash.sh --cleanup   when done
EOF
}

INSTALL_ARGS=()
CARD_ARGS=()
KEEP=0
CLEANUP_ONLY=0
while [ $# -gt 0 ]; do
  case $1 in
    --build) INSTALL_ARGS+=(--build) ;;
    --ref)
      [ $# -ge 2 ] || { usage >&2; exit 2; }
      INSTALL_ARGS+=(--ref "$2")
      shift
      ;;
    --keep) KEEP=1 ;;
    --cleanup) CLEANUP_ONLY=1 ;;
    --dry-run) CARD_ARGS+=(--dry-run) ;;
    --yes) CARD_ARGS+=(--yes) ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$CLEANUP_ONLY" = 1 ]; then
  exec "$SCRIPTS/remove.sh"
fi

# Runs on failure too, so a broken run does not leave anything behind either.
if [ "$KEEP" = 0 ]; then
  trap '"$SCRIPTS/remove.sh"' EXIT
fi

# The ${array[@]+...} form is for macOS's bash 3.2, which treats an empty array as unset.
"$SCRIPTS/install.sh" ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}
"$SCRIPTS/flash-card.sh" ${CARD_ARGS[@]+"${CARD_ARGS[@]}"}

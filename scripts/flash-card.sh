#!/usr/bin/env bash
# Replaces the Keycard applet on the card in the reader and loads a test identity certificate.
# Needs install.sh to have run.
#
#   flash-card.sh             flash the card
#   flash-card.sh --yes       do not ask before wiping a card that is in use
#   flash-card.sh --dry-run   show the steps without touching a card
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

YES=0
DRY_RUN=0
while [ $# -gt 0 ]; do
  case $1 in
    --yes) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *) die "flash-card.sh: unknown option $1" ;;
  esac
  shift
done

JAVA=$(find_java) || die "no usable Java. Run scripts/install.sh first."
for file in gp.jar keycard.cap math.cap; do
  [ -f "$WORK/$file" ] || die "work/$file is missing. Run scripts/install.sh first."
done

gp() {
  "$JAVA" -jar "$WORK/gp.jar" --key "$GP_KEY" "$@"
}

tool() {
  "$JAVA" -cp "$WORK/gp.jar" "$ROOT/KeycardTool.java" "$@"
}

if [ "$DRY_RUN" = 1 ]; then
  step "Dry run: generating a test certificate, no card is touched"
  tool generate
  cat <<EOF

On a card this would:
  1. read the applet state (no login)
  2. log in to the card manager with the key $GP_KEY
  3. delete the Keycard package $PACKAGE_AID and the math package $MATH_AID, if present
  4. load math.cap and keycard.cap
  5. create the Keycard, NDEF, Cash and Ident instances
  6. store a test identity certificate and check the applet reports it
EOF
  exit 0
fi

os_check_reader_service

step "Reading the card"
state=$(tool status)
echo "Keycard applet: $state"
if [ "$state" = initialized ] && [ "$YES" = 0 ]; then
  echo "This card has a PIN set and may hold keys. Flashing erases them for good."
  answer=
  read -r -p "Type wipe to continue: " answer || true
  [ "$answer" = wipe ] || die "stopped, the card was not changed (--yes skips this question)"
fi

step "Logging in to the card manager"
# A rejected key counts toward the card's permanent lockout, so the first failure ends the run.
listing=$(gp -l) || die "could not log in. If the key was rejected, do NOT retry on this card:
repeated failures lock its card manager for good."

has_package() {
  grep -q "^PKG: $1 " <<<"$listing"
}

step "Removing the old applet"
# The Keycard package goes first because it depends on the math package.
if has_package "$PACKAGE_AID"; then
  gp --delete "$PACKAGE_AID" -f
  echo "deleted the Keycard package and its instances"
fi
if has_package "$MATH_AID"; then
  gp --delete "$MATH_AID"
  echo "deleted the math package"
fi

step "Loading the new applet"
gp --load "$WORK/math.cap"
gp --load "$WORK/keycard.cap"

step "Creating the instances"
gp --package "$PACKAGE_AID" --applet "${PACKAGE_AID}01" --create A00000080400010101 # Keycard
gp --package "$PACKAGE_AID" --applet "${PACKAGE_AID}02" --create D2760000850101     # NDEF
gp --package "$PACKAGE_AID" --applet "${PACKAGE_AID}03" --create A00000080400010301 # Cash
gp --package "$PACKAGE_AID" --applet "${PACKAGE_AID}04" --create A00000080400010401 # Ident

step "Loading a test identity certificate"
tool load-ident

step "Checking the result"
version=$(gp -l | awk -v pkg="PKG: $PACKAGE_AID " 'index($0, pkg) == 1 { found = 1; next } found && /Version:/ { print $2; exit }')
echo "Keycard package version on the card: ${version:-unknown}"
echo "Done. This card is ready."

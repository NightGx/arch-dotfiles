#!/usr/bin/env bash
# Add the style-switcher button to the illogical-impulse bar.
#
# Upstream owns UtilButtons.qml and overwrites it on every update, so this is
# written to be run again after ./tools/fetch-end4.sh. It is idempotent: a
# second run on an already-patched file changes nothing.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="${1:-$REPO/profiles/end4/config/quickshell/ii/modules/ii/bar}"
MARKER="hyprprofile: live style switcher"

say()  { printf '==> %s\n' "$*" >&2; }
die()  { printf 'err  %s\n' "$*" >&2; exit 1; }

[[ -d $TARGET_DIR ]] || die "bar module dir not found: $TARGET_DIR"
UTIL="$TARGET_DIR/UtilButtons.qml"
[[ -f $UTIL ]] || die "UtilButtons.qml not found in $TARGET_DIR"

say "installing StyleSwitcher.qml"
install -m 0644 "$REPO/modules/quickshell/StyleSwitcher.qml" "$TARGET_DIR/StyleSwitcher.qml"

if grep -qF "$MARKER" "$UTIL"; then
  say "UtilButtons.qml already patched"
  exit 0
fi

# The RowLayout's `anchors.centerIn: parent` is the one line in this file that
# is both unique and stable across upstream revisions, so it is the anchor.
grep -qE '^\s*anchors\.centerIn: parent\s*$' "$UTIL" ||
  die "could not find the insertion point in UtilButtons.qml - upstream layout changed, patch by hand"

tmp=$(mktemp)
awk -v marker="$MARKER" '
  { print }
  !done && /^[[:space:]]*anchors\.centerIn: parent[[:space:]]*$/ {
    print ""
    print "        // " marker
    print "        // Added by config_arch. Re-run tools/patch-quickshell-bar.sh"
    print "        // after updating the dots to put it back."
    print "        Loader {"
    print "            active: true"
    print "            visible: true"
    print "            sourceComponent: StyleSwitcher {"
    print "                Layout.alignment: Qt.AlignVCenter"
    print "            }"
    print "        }"
    done = 1
  }
' "$UTIL" > "$tmp"

# Never leave a half-written QML file behind: the bar refuses to load and the
# user is staring at an empty screen.
[[ -s $tmp ]] || { rm -f "$tmp"; die "patch produced an empty file, aborting"; }
grep -qF "$MARKER" "$tmp" || { rm -f "$tmp"; die "patch did not apply, aborting"; }

cp -f "$UTIL" "$UTIL.pre-hyprprofile"
mv "$tmp" "$UTIL"
chmod 0644 "$UTIL"

say "patched UtilButtons.qml (original kept as UtilButtons.qml.pre-hyprprofile)"

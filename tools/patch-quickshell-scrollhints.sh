#!/usr/bin/env bash
# Make the bar's scroll hints optional.
#
# illogical-impulse draws an up/icon/down column at the very left and right
# edges of the bar whenever you hover that half of it - brightness on the
# left, volume on the right. It is painted over the bar's own content and
# there is no setting for it upstream, so this adds one:
#
#   bar.scrollHints   in ~/.config/illogical-impulse/config.json
#
# Scrolling still changes brightness and volume; only the overlay is gated.
# Upstream owns both files and overwrites them on every update, so this is
# written to be run again after ./tools/fetch-end4.sh, and is idempotent.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
QS="${1:-$REPO/profiles/end4/config/quickshell/ii}"

say() { printf '==> %s\n' "$*" >&2; }
die() { printf 'err  %s\n' "$*" >&2; exit 1; }

CONFIG="$QS/modules/common/Config.qml"
HINT="$QS/modules/ii/bar/ScrollHint.qml"
[[ -f $CONFIG ]] || die "Config.qml not found: $CONFIG"
[[ -f $HINT   ]] || die "ScrollHint.qml not found: $HINT"

if grep -q 'property bool scrollHints' "$CONFIG"; then
  say "Config.qml already declares bar.scrollHints"
else
  grep -q 'property JsonObject bar: JsonObject {' "$CONFIG" ||
    die "could not find the bar block in Config.qml - upstream changed shape"
  python3 - "$CONFIG" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "            property JsonObject bar: JsonObject {"
new = old + "\n                property bool scrollHints: true // The up/icon/down column at each end of the bar"
open(p, "w").write(s.replace(old, new, 1))
PY
  say "declared bar.scrollHints in Config.qml"
fi

if grep -q 'Config.options.bar.scrollHints' "$HINT"; then
  say "ScrollHint.qml already honours it"
else
  grep -q 'property string tooltipText' "$HINT" ||
    die "ScrollHint.qml changed shape - patch by hand"
  python3 - "$HINT" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
m = re.search(r'^(\s*)property string tooltipText.*$', s, re.M)
indent = m.group(1)
add = (m.group(0) + "\n\n"
       + indent + "// Drawn on top of the bar's own content at the very left and right\n"
       + indent + "// edges, which is intrusive enough that it wants to be optional.\n"
       + indent + "visible: Config.options.bar.scrollHints")
open(p, "w").write(s[:m.start()] + add + s[m.end():])
PY
  say "gated the hint in ScrollHint.qml"
fi

printf '==> %s\n' "scroll hints are now switchable via bar.scrollHints"

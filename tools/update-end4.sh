#!/usr/bin/env bash
# Pull the latest illogical-impulse dots and re-apply our two local changes.
#
# Run this instead of fetch-end4.sh directly: an update overwrites
# UtilButtons.qml, where the bar's style button lives, and Config.qml /
# ScrollHint.qml, where the bar's scroll-hint overlay is made optional.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

"$HERE/fetch-end4.sh"
"$HERE/patch-quickshell-bar.sh"
"$HERE/patch-quickshell-scrollhints.sh"

printf '==> %s\n' "dots updated and re-patched"
printf '    apply with: hyprprofile set end4 --force\n'

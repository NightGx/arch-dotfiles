#!/usr/bin/env bash
# Runs install.sh against a throwaway HOME seeded with a copy of the real
# Arch config, and checks the result end to end.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# The real Arch config when it is mounted, the checked-in snapshot otherwise,
# so the suite runs on either side of the dual boot.
SEED="${SEED_CONFIG:-}"
if [[ -z $SEED ]]; then
  if [[ -d /mnt/new_arch/home/night/.config ]]; then SEED=/mnt/new_arch/home/night/.config
  else SEED="$REPO/tests/fixtures/config"; fi
fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export HYPRPROFILE_ROOT="$XDG_CONFIG_HOME/hypr-profiles"
export HYPRPROFILE_BIN="$HOME/.local/bin"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$HYPRPROFILE_BIN"

# The shell config Quickshell keeps its settings in. It is the user's own file,
# never a managed path, so the install has to edit it in place without
# disturbing anything it does not own.
mkdir -p "$XDG_CONFIG_HOME/illogical-impulse"
cat > "$XDG_CONFIG_HOME/illogical-impulse/config.json" <<'EOF'
{
  "bar": { "topLeftIcon": "spark" },
  "sidebar": { "cornerOpen": { "enable": true, "cornerRegionWidth": 250 } }
}
EOF

# Stand-ins for the commands each profile REQUIRES. hyprprofile now refuses to
# enter a profile whose shell is not installed, so without these the end4 half
# of this test could never run.
STUB="$T/bin"; mkdir -p "$STUB"
export STUBLOG="$T/stub-calls"; : > "$STUBLOG"
for c in qs matugen fuzzel hypridle cliphist wl-paste rofi kitty swww notify-send \
         gsettings pkill setsid linux-wallpaperengine; do
  printf '#!/bin/sh\necho "%s $*" >> "$STUBLOG"\nexit 0\n' "$c" > "$STUB/$c"
  chmod +x "$STUB/$c"
done
# setsid has to actually run the command, or nothing a hook detaches happens.
cat > "$STUB/setsid" <<'EOF'
#!/bin/sh
echo "setsid $*" >> "$STUBLOG"
[ "$1" = "--fork" ] && shift
exec "$@"
EOF
chmod +x "$STUB/setsid"
# hyprctl has to answer `version` and `configerrors` for the switch to get past
# its own sanity checks.
cat > "$STUB/hyprctl" <<'EOF'
#!/bin/sh
echo "hyprctl $*" >> "$STUBLOG"
case "$1" in
  version)      echo "Hyprland 0.56.2 built from branch"; ;;
  configerrors) echo "no errors"; ;;
esac
exit 0
EOF
chmod +x "$STUB/hyprctl"
export PATH="$STUB:$PATH"
# There is no compositor here, so every start hook sits in wait_for_wayland
# until it gives up. Cap that rather than paying ten seconds a switch.
export HYPRPROFILE_HOOK_TIMEOUT=5

# A real unix socket where a compositor's would be, so the profile hooks get
# past wait_for_wayland and the parts of them that matter actually run.
export XDG_RUNTIME_DIR="$T/run"; mkdir -p "$XDG_RUNTIME_DIR"
export WAYLAND_DISPLAY=wayland-test
python3 - <<'EOF'
import os, socket
s = socket.socket(socket.AF_UNIX)
s.bind(os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ["WAYLAND_DISPLAY"]))
s.listen(1)
os.set_inheritable(s.fileno(), False)
EOF

[[ -d $SEED ]] || { echo "SKIP: seed config $SEED not available"; exit 0; }
cp -a "$SEED"/. "$XDG_CONFIG_HOME"/ 2>/dev/null
echo "seeded $(ls "$XDG_CONFIG_HOME" | wc -l) entries into the fake HOME"

pass=0; fail=0
ck()    { local d=$1; shift; if "$@"; then echo "  PASS $d"; ((pass++)); else echo "  FAIL $d"; ((fail++)); fi; }
ck_eq() { if [[ $2 == "$3" ]]; then echo "  PASS $1"; ((pass++));
          else printf '  FAIL %s (want %q, got %q)\n' "$1" "$2" "$3"; ((fail++)); fi; }

echo "== dry run changes nothing =="
before=$(find "$XDG_CONFIG_HOME" -maxdepth 1 | sort | md5sum)
"$REPO/install.sh" --dry-run >/dev/null 2>&1
after=$(find "$XDG_CONFIG_HOME" -maxdepth 1 | sort | md5sum)
ck_eq "dry run left ~/.config untouched" "$before" "$after"

echo "== real install =="
out=$("$REPO/install.sh" 2>&1); rc=$?
ck_eq "install exited 0" "0" "$rc"
[[ $rc -ne 0 ]] && { echo "$out" | tail -20; }

echo "== the live config became a link into the profile =="
ck "~/.config/hypr is a symlink"  test -L "$XDG_CONFIG_HOME/hypr"
ck "hyprland.lua readable through the link" test -f "$XDG_CONFIG_HOME/hypr/hyprland.lua"
ck_eq "active profile is end4" "end4" "$("$HYPRPROFILE_BIN/hyprprofile" current)"
ck "hypr points at end4's lua" grep -q 'require("hyprland.lib")' "$XDG_CONFIG_HOME/hypr/hyprland.lua"

echo "== nothing was lost =="
# The config that was living at ~/.config before the install is not deleted or
# overwritten - the switcher moves it aside before putting its own link there.
ck "the original hypr config was moved aside, not destroyed" \
   bash -c 'ls "$HYPRPROFILE_ROOT"/backups/*/.config/hypr/hyprland.lua >/dev/null 2>&1'
ck "and it is the real thing, not a stub" \
   bash -c 'grep -q "2560x1440" "$HYPRPROFILE_ROOT"/backups/*/.config/hypr/hyprland.lua'
# end4 does not manage ~/.config/rofi, so it is neither linked nor moved - it
# just stays where it was, which is the other half of "nothing was lost".
ck "config the rice does not own is left alone" \
   test -f "$XDG_CONFIG_HOME/rofi/spotlight.rasi"
ck "and is a real dir, not a link into the profile" \
   bash -c '[[ ! -L "$XDG_CONFIG_HOME/rofi" ]]'

echo "== the Material 3 rice is fully in place =="
ck "quickshell config appeared" test -f "$XDG_CONFIG_HOME/quickshell/ii/shell.qml"
ck "the bar has the style button" \
   grep -q "hyprprofile: live style switcher" "$XDG_CONFIG_HOME/quickshell/ii/modules/ii/bar/UtilButtons.qml"
ck "matugen config appeared" test -f "$XDG_CONFIG_HOME/matugen/config.toml"
ck "end4 keybind file has the switcher" \
   grep -q 'Pick a look' "$XDG_CONFIG_HOME/hypr/custom/keybinds.lua"
ck "the look-cycling keybind is there" \
   grep -q 'look next' "$XDG_CONFIG_HOME/hypr/custom/keybinds.lua"
ck "and the picker blur rules" \
   grep -q 'namespace = "rofi"' "$XDG_CONFIG_HOME/hypr/custom/keybinds.lua"
ck "konsole data linked" test -L "$XDG_DATA_HOME/konsole"
ck "quickshell state dir left unmanaged" test ! -L "$XDG_STATE_HOME/quickshell"
ck_eq "state json names end4" "end4" \
  "$(sed -n 's/.*\"name\":\"\([^\"]*\)\".*/\1/p' "$HYPRPROFILE_ROOT/state/current.json")"

echo "== the wallpaper half is installed =="
ck "picker themes deployed" test -f "$HYPRPROFILE_ROOT/themes/hyprprofile.rasi"
ck "fuzzel picker theme deployed" test -f "$HYPRPROFILE_ROOT/themes/hyprprofile-fuzzel.ini"
ck "wallpaper library deployed" test -f "$HYPRPROFILE_ROOT/lib/wallpaper.sh"
ck "wallpapers copied in" test -f "$HYPRPROFILE_ROOT/wallpapers/index.conf"
n=$(ls "$HYPRPROFILE_ROOT"/wallpapers/*.jpg "$HYPRPROFILE_ROOT"/wallpapers/*.png 2>/dev/null | wc -l)
ck "there is more than one to pick from" test "$n" -ge 2
ck "each has a thumbnail for the picker" test -f "$HYPRPROFILE_ROOT/wallpapers/thumbs/illogical.png"
ck "wallpaper list works" \
   bash -c '"$HYPRPROFILE_BIN/hyprprofile" wallpaper list 2>&1 | grep -q "Sakura"'
ck "the rice ships a wallpaper backend" \
   test -x "$HYPRPROFILE_ROOT/profiles/end4/bin/set-wallpaper"

echo "== looks are installed =="
ck "the looks library is in place" test -x "$HYPRPROFILE_ROOT/lib/looks.sh"
ck_eq "all nine looks were copied" "9" \
  "$(find "$HYPRPROFILE_ROOT/looks" -mindepth 1 -maxdepth 1 -type d | wc -l)"
ck "the shared baseline came with them" test -f "$HYPRPROFILE_ROOT/looks/baseline.json"
ck "so did the menu order" test -f "$HYPRPROFILE_ROOT/looks/order.conf"
ck "every look has a clock patch" bash -c '
  for d in "$HYPRPROFILE_ROOT"/looks/*/; do [[ -f $d/patch.json ]] || exit 1; done'
ck "the switcher sees them" bash -c \
  '"$HYPRPROFILE_BIN/hyprprofile" look list 2>/dev/null | grep -q Sakura'

echo "== the bar overlays are turned off at install time =="
# Neither of these should need a look applied first - a plain install is
# enough, because both are things the user asked to be rid of.
if command -v jq >/dev/null 2>&1; then
  II="$XDG_CONFIG_HOME/illogical-impulse/config.json"
  ck_eq "the top-corner scroll strips are off" "false" \
    "$(jq -r '.sidebar.cornerOpen.enable' "$II")"
  ck_eq "the bar's scroll hints are off" "false" "$(jq -r '.bar.scrollHints' "$II")"
  ck_eq "and the user's own settings were kept" "spark" "$(jq -r '.bar.topLeftIcon' "$II")"
fi
ck "the shell declares the scroll-hint option" \
   grep -q 'property bool scrollHints' "$XDG_CONFIG_HOME/quickshell/ii/modules/common/Config.qml"
ck "and the hint honours it" \
   grep -q 'Config.options.bar.scrollHints' "$XDG_CONFIG_HOME/quickshell/ii/modules/ii/bar/ScrollHint.qml"

echo "== the profile hooks actually ran =="
ck "end4's start hook brought the shell up" grep -q 'qs -c ii' "$STUBLOG"
ck "and set the cursor theme" grep -q 'hyprctl setcursor Bibata' "$STUBLOG"

echo "== a wallpaper goes through the rice's own backend =="
: > "$STUBLOG"
"$HYPRPROFILE_BIN/hyprprofile" wallpaper tessellate >/dev/null 2>&1
ck_eq "the wallpaper was recorded" "tessellate" \
   "$("$HYPRPROFILE_BIN/hyprprofile" wallpaper current)"

echo "== an older keybind block is replaced, not left frozen =="
# The first install on this machine wrote an earlier version of the block.
# A plain "already present" check would keep it forever, so the newer bindings
# would never arrive.
L="$HYPRPROFILE_ROOT/profiles/end4/config/hypr/custom/keybinds.lua"
python3 - "$L" <<'EOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"-- ── hyprprofile ─.*?\n-- ─+\n", """-- ── hyprprofile ──────────────────────────────────────────────────────────
-- An older block, as an earlier install would have left it.
local hyprprofile = os.getenv("HOME") .. "/.local/bin/hyprprofile"
hl.bind("SUPER + Y", hl.dsp.exec_cmd(hyprprofile .. " menu"),
        { description = "Pick desktop style" })
-- ─────────────────────────────────────────────────────────────────────────
""", s, flags=re.S)
open(p, "w").write(s)
EOF
ck "the fixture really has the old block" grep -q 'An older block' "$L"
"$REPO/install.sh" >/dev/null 2>&1
ck "the old block is gone" bash -c '! grep -q "An older block" "$L"'
ck "the new bindings arrived" grep -q 'look next' "$L"
ck "so did the layer rules" grep -q 'namespace = "rofi"' "$L"
ck_eq "exactly one block" "1" "$(grep -c '^-- ── hyprprofile ─' "$L")"

echo "== re-running install is safe =="
"$REPO/install.sh" >/dev/null 2>&1
ck_eq "second install exited 0" "0" "$?"
ck_eq "keybind not duplicated" "1" "$(grep -c 'Pick a look' "$L")"
ck "the rice config still loads" grep -q 'require("hyprland.lib")' "$XDG_CONFIG_HOME/hypr/hyprland.lua"
ck_eq "the scroll-hint patch is not applied twice" "1" \
  "$(grep -c 'property bool scrollHints' "$HYPRPROFILE_ROOT/profiles/end4/config/quickshell/ii/modules/common/Config.qml")"
ck_eq "wallpapers not re-copied over user edits" "0" \
  "$(find "$HYPRPROFILE_ROOT/wallpapers" -name '*.rsync-partial' | wc -l)"

echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
exit $(( fail > 0 ))

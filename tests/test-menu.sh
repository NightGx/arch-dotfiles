#!/usr/bin/env bash
# Exercises the picker and the wallpaper half against a throwaway HOME.
#
# This is the part that failed silently in the field: the menu opened, a row
# was picked, and nothing happened. So the tests here care less about the
# happy path than about every way a selection can fail to map back to a row.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HP="$REPO/bin/hyprprofile"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export HYPRPROFILE_ROOT="$XDG_CONFIG_HOME/hypr-profiles"
export HYPRPROFILE_THEMES="$REPO/themes"
export HYPRPROFILE_WALLPAPERS="$HYPRPROFILE_ROOT/wallpapers"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

STUB="$T/bin"; mkdir -p "$STUB"
export PATH="$STUB:$PATH"
export STUB_LOG="$T/picker-input"
export NOTIFY_LOG="$T/notifications"

pass=0; fail=0
check()    { local d=$1; shift; if "$@"; then printf '  PASS %s\n' "$d"; pass=$((pass+1)); else printf '  FAIL %s\n' "$d"; fail=$((fail+1)); fi; }
check_eq() { if [[ $2 == "$3" ]]; then printf '  PASS %s\n' "$1"; pass=$((pass+1));
             else printf '  FAIL %s (expected %q, got %q)\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
check_not(){ if [[ $3 != *"$2"* ]]; then printf '  PASS %s\n' "$1"; pass=$((pass+1));
             else printf '  FAIL %s (unexpected %q)\n' "$1" "$2"; fail=$((fail+1)); fi; }
check_has(){ if [[ $3 == *"$2"* ]]; then printf '  PASS %s\n' "$1"; pass=$((pass+1));
             else printf '  FAIL %s (missing %q in %q)\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# ------------------------------------------------------------- stub pickers --
# rofi: records what it was fed, echoes back the row index in $STUB_PICK.
cat > "$STUB/rofi" <<'EOF'
#!/usr/bin/env bash
cat > "$STUB_LOG"
printf '%s' "$*" > "$STUB_LOG.args"
[[ -n ${STUB_PICK:-} ]] && printf '%s\n' "$STUB_PICK"
exit 0
EOF

# wofi: the launcher class that cannot return an index. It also *trims* the
# row, which is exactly how selection used to break.
cat > "$STUB/wofi" <<'EOF'
#!/usr/bin/env bash
mapfile -t rows
printf '%s\n' "${rows[@]}" > "$STUB_LOG"
[[ -n ${STUB_PICK:-} ]] || exit 0
line=${rows[$STUB_PICK]}
line=${line#"${line%%[![:space:]]*}"}     # strip leading whitespace
line=${line%"${line##*[![:space:]]}"}     # strip trailing whitespace
printf '%s\n' "$line"
EOF

cat > "$STUB/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${NOTIFY_LOG:?}"
EOF

# A command that exists only so a profile can REQUIRE it, and one that does not.
cat > "$STUB/riceshell" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUB"/*

# -------------------------------------------------------------- fixtures ----
mkprofile() { # mkprofile <name> <display> <accent> <picker> <requires...>
  local n=$1 disp=$2 acc=$3 pick=$4; shift 4
  local d="$HYPRPROFILE_ROOT/profiles/$n"
  mkdir -p "$d/config/hypr" "$d/hooks" "$d/bin"
  echo "-- $n" > "$d/config/hypr/hyprland.lua"
  {
    echo "DISPLAY_NAME=\"$disp\""
    echo "DESCRIPTION=\"$n\""
    echo "ACCENT=\"$acc\""
    echo "PICKER=\"$pick\""
    echo "CONFIG_PATHS=(hypr)"
    echo "REQUIRES=($*)"
  } > "$d/profile.conf"
  # A wallpaper backend that only records what it was asked to do.
  cat > "$d/bin/set-wallpaper" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$n" "\$1" >> "$T/applied"
EOF
  chmod +x "$d/bin/set-wallpaper"
}

mkprofile alpha "Clean"      "#8ab4f8" rofi bash
mkprofile beta  "Material 3" "#a3c9ff" rofi bash

mkdir -p "$HYPRPROFILE_WALLPAPERS/thumbs"
for w in aurora dunes; do
  printf 'x' > "$HYPRPROFILE_WALLPAPERS/$w.png"
  printf 'x' > "$HYPRPROFILE_WALLPAPERS/thumbs/$w.png"
done
cat > "$HYPRPROFILE_WALLPAPERS/index.conf" <<'EOF'
# comment line that must be ignored
aurora.png|Aurora|#7bccf3
dunes.png|Slate Dunes|#bf7a58
EOF

"$HP" set alpha >/dev/null 2>&1

echo "== the picker is fed one row per entry =="
STUB_PICK= "$HP" menu styles >/dev/null 2>&1
rows=$(wc -l < "$STUB_LOG")
check_eq "every style is listed" "2" "$rows"
# The rows carry a NUL before the icon field, which a command substitution
# would drop with a warning - swap it for a visible marker to assert on.
fed=$(tr '\0' '@' < "$STUB_LOG")
check_has "the active style carries a filled dot" '●' "$fed"
check_has "an inactive style carries a hollow dot" '○' "$fed"
check_has "the dot is coloured per entry" 'foreground="#8ab4f8"' "$fed"
check_has "the style's description is shown" 'alpha' "$fed"
# Pango is strict: an unquoted attribute makes it drop the whole row's markup.
check_not "attribute values are quoted" 'alpha=45' "$fed"

STUB_PICK= "$HP" menu wallpapers >/dev/null 2>&1
fed=$(tr '\0' '@' < "$STUB_LOG")
check_eq "every wallpaper is listed" "2" "$(wc -l < "$STUB_LOG")"
check_has "wallpapers are named from index.conf" 'Slate Dunes' "$fed"
check_has "the wallpaper accent colours its dot" 'foreground="#7bccf3"' "$fed"
check_has "rows carry their thumbnail as an icon" '@icon' "$fed"
args=$(cat "$STUB_LOG.args")
check_has "rofi is asked for an index, not a string" '-format i' "$args"
check_has "the shipped theme is used" 'hyprprofile.rasi' "$args"
check_has "the accent is injected at run time" 'accent:' "$args"

echo "== picking a style row switches to it =="
STUB_PICK=1 "$HP" menu styles >/dev/null 2>&1
check_eq "row 1 selected the second style" "beta" "$("$HP" current)"
STUB_PICK=0 "$HP" menu styles >/dev/null 2>&1
check_eq "row 0 selected the first style" "alpha" "$("$HP" current)"

echo "== picking a wallpaper row applies it through the profile =="
: > "$T/applied"
STUB_PICK=0 "$HP" menu wallpapers >/dev/null 2>&1
check_eq "the active profile's backend ran" "alpha $HYPRPROFILE_WALLPAPERS/aurora.png" "$(cat "$T/applied")"
check_eq "the choice is recorded" "aurora" "$("$HP" wallpaper current)"

STUB_PICK=1 "$HP" menu wallpapers >/dev/null 2>&1
check_eq "the next wallpaper row is a different image" "dunes" "$("$HP" wallpaper current)"

echo "== cancelling changes nothing =="
before=$("$HP" wallpaper current)
STUB_PICK= "$HP" menu wallpapers >/dev/null 2>&1
check_eq "an empty selection is a no-op" "$before" "$("$HP" wallpaper current)"

echo "== a theme rofi refuses does not swallow the menu =="
# A .rasi rofi will not parse makes it exit having drawn nothing. From a
# keybind that is indistinguishable from a broken switcher, so the menu has to
# notice and retry with rofi's own theme.
cat > "$STUB/rofi" <<'EOF'
#!/usr/bin/env bash
cat > "$STUB_LOG"
printf '%s' "$*" > "$STUB_LOG.args"
case "$*" in
  *-theme\ *) echo "Error: failed to parse theme" >&2; exit 1 ;;
esac
printf '%s
' "$STUB_ROFI_PICK"
EOF
chmod +x "$STUB/rofi"
: > "$T/notifications"
STUB_ROFI_PICK=1 "$HP" menu styles >/dev/null 2>&1
check_eq "the retry without the theme still switched" "beta" "$("$HP" current)"
check_has "and the user was told why" "rejected" "$(cat "$T/notifications")"
"$HP" set alpha --force >/dev/null 2>&1
# put the well-behaved stub back
cat > "$STUB/rofi" <<'EOF'
#!/usr/bin/env bash
cat > "$STUB_LOG"
printf '%s' "$*" > "$STUB_LOG.args"
[[ -n ${STUB_PICK:-} ]] && printf '%s
' "$STUB_PICK"
exit 0
EOF
chmod +x "$STUB/rofi"

echo "== a launcher that trims the row still maps back =="
# wofi returns text, not an index, and strips the leading spaces the dot sits
# in. Matching has to survive that.
export HYPRPROFILE_PICKER=wofi
"$HP" set alpha >/dev/null 2>&1
STUB_PICK=1 "$HP" menu styles >/dev/null 2>&1
check_eq "trimmed text still selects the right style" "beta" "$("$HP" current)"
STUB_PICK=0 "$HP" menu styles >/dev/null 2>&1
check_eq "and back again" "alpha" "$("$HP" current)"
unset HYPRPROFILE_PICKER

echo "== a style whose dependencies are missing is refused, not entered =="
mkprofile gamma "Broken" "#ff0000" rofi riceshell definitely-not-installed
out=$("$HP" set gamma 2>&1); rc=$?
check_eq "set refuses" "1" "$rc"
check_eq "and stays put" "alpha" "$("$HP" current)"
check_has "naming the missing command" "definitely-not-installed" "$out"
check "the user is told out of band" test -s "$NOTIFY_LOG"
out=$("$HP" set gamma --force 2>&1)
check_eq "--force overrides the refusal" "gamma" "$("$HP" current)"
"$HP" set alpha --force >/dev/null 2>&1

echo "== the menu marks a style it cannot enter =="
STUB_PICK= "$HP" menu styles >/dev/null 2>&1
check_has "unavailable styles say why" "needs definitely-not-installed" "$(cat "$STUB_LOG")"

echo "== wallpaper subcommands =="
"$HP" wallpaper aurora >/dev/null 2>&1
check_eq "set by id" "aurora" "$("$HP" wallpaper current)"
"$HP" wallpaper next >/dev/null 2>&1
check_eq "next cycles forward" "dunes" "$("$HP" wallpaper current)"
"$HP" wallpaper next >/dev/null 2>&1
check_eq "and wraps" "aurora" "$("$HP" wallpaper current)"
out=$("$HP" wallpaper list 2>&1)
check_has "list marks the active one" "* aurora" "$out"
check_has "list shows the display name" "Slate Dunes" "$out"
out=$("$HP" wallpaper no-such-image 2>&1); rc=$?
check_eq "an unknown id fails loudly" "1" "$rc"

echo "== a loose image dropped in the folder shows up =="
printf 'x' > "$HYPRPROFILE_WALLPAPERS/my_own-shot.jpg"
out=$("$HP" wallpaper list 2>&1)
check_has "un-indexed images are listed" "my_own-shot" "$out"
check_has "with a name derived from the filename" "My Own Shot" "$out"

echo "== published state describes both halves =="
"$HP" wallpaper aurora >/dev/null 2>&1
state=$(cat "$HYPRPROFILE_ROOT/state/current.json")
check_has "state names the profile" '"name":"alpha"' "$state"
check_has "state names the wallpaper" '"wallpaper":"aurora"' "$state"
check_has "state carries the wallpaper's display name" '"wallpaperName":"Aurora"' "$state"

echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
(( fail == 0 ))

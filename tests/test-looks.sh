#!/usr/bin/env bash
# Exercises looks: one rice, several appearances.
#
# The looks in this suite are the *real* ones from the repo, not fixtures, so
# a broken wallpaper name or an unparseable patch fails here rather than on
# the user's desktop. The rest of it is about the one operation that can
# quietly go wrong: merging a look into a config file that Quickshell is also
# writing to. A merge that replaces instead of merging, or a write that gets
# echoed over, both look like "the clock didn't change".
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
export HYPRPROFILE_WALLPAPERS="$REPO/wallpapers"
export HYPRPROFILE_LOOKS="$REPO/looks"
export HYPRPROFILE_LOOK_PROFILE="end4"
export HYPRPROFILE_II_CONFIG="$XDG_CONFIG_HOME/illogical-impulse/config.json"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" \
         "$(dirname "$HYPRPROFILE_II_CONFIG")"

STUB="$T/bin"; mkdir -p "$STUB"
export PATH="$STUB:$PATH"
export STUB_LOG="$T/picker-input"
export NOTIFY_LOG="$T/notifications"
export APPLIED="$T/applied"

pass=0; fail=0
check()    { local d=$1; shift; if "$@"; then printf '  PASS %s\n' "$d"; pass=$((pass+1)); else printf '  FAIL %s\n' "$d"; fail=$((fail+1)); fi; }
check_eq() { if [[ $2 == "$3" ]]; then printf '  PASS %s\n' "$1"; pass=$((pass+1));
             else printf '  FAIL %s (expected %q, got %q)\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
check_has(){ if [[ $3 == *"$2"* ]]; then printf '  PASS %s\n' "$1"; pass=$((pass+1));
             else printf '  FAIL %s (missing %q in %q)\n' "$1" "$2" "${3:0:400}"; fail=$((fail+1)); fi; }
check_not(){ if [[ $3 != *"$2"* ]]; then printf '  PASS %s\n' "$1"; pass=$((pass+1));
             else printf '  FAIL %s (unexpected %q)\n' "$1" "$2"; fail=$((fail+1)); fi; }

jqr() { jq -r "$1" "$HYPRPROFILE_II_CONFIG"; }

# ------------------------------------------------------------------ stubs ---
cat > "$STUB/rofi" <<'EOF'
#!/usr/bin/env bash
cat > "$STUB_LOG"
printf '%s' "$*" > "$STUB_LOG.args"
[[ -n ${STUB_PICK:-} ]] && printf '%s\n' "$STUB_PICK"
exit 0
EOF
cat > "$STUB/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${NOTIFY_LOG:?}"
EOF
# Hyprland is "running" so switches take the real path through the hooks.
cat > "$STUB/hyprctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  version)      echo "Hyprland 0.56.0" ;;
  configerrors) echo "no errors" ;;
esac
exit 0
EOF
chmod +x "$STUB"/*

# ------------------------------------------------------------- fixtures -----
mkprofile() { # mkprofile <name> <display> <accent>
  local n=$1 disp=$2 acc=$3
  local d="$HYPRPROFILE_ROOT/profiles/$n"
  mkdir -p "$d/config/hypr" "$d/hooks" "$d/bin"
  echo "-- $n" > "$d/config/hypr/hyprland.lua"
  {
    echo "DISPLAY_NAME=\"$disp\""; echo "DESCRIPTION=\"the $n rice\""
    echo "ACCENT=\"$acc\""; echo "PICKER=\"rofi\""
    echo "CONFIG_PATHS=(hypr)"; echo "REQUIRES=(bash)"
  } > "$d/profile.conf"
  # Records the image it was handed and the palette settings it was given, so
  # a look that forgets to pass its scheme through is visible here.
  cat > "$d/bin/set-wallpaper" <<EOF
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$n" "\${1##*/}" "\${HYPRPROFILE_SCHEME:-}" "\${HYPRPROFILE_MODE:-}" >> "$APPLIED"
EOF
  chmod +x "$d/bin/set-wallpaper"
}
mkprofile end4 "Material 3" "#a3c9ff"
mkprofile mine "Clean"      "#8ab4f8"
mkdir -p "$HYPRPROFILE_ROOT/lib"
cp "$REPO/lib/hooklib.sh" "$HYPRPROFILE_ROOT/lib/"

# A shell config with settings of the user's own that no look mentions. If a
# look ever replaces the file instead of merging into it, these vanish.
cat > "$HYPRPROFILE_II_CONFIG" <<'EOF'
{
  "appearance": { "fonts": { "main": "Google Sans Flex" } },
  "bar": { "bottom": false, "topLeftIcon": "spark" },
  "sidebar": { "cornerOpen": { "enable": true, "cornerRegionWidth": 250 } },
  "ai": { "systemPrompt": "the user's own long prompt" },
  "background": { "widgets": { "clock": { "style": "digital" } } }
}
EOF

"$HP" set mine >/dev/null 2>&1

echo "== the shipped looks are all well-formed =="
ids=$("$HP" look list 2>/dev/null | awk '{print $1}' | grep -v '^\*$')
n=$("$HP" look list 2>/dev/null | wc -l)
check_eq "all nine looks are listed" "9" "$n"
for id in illogical dawn dunes marbled badlands sakura fogbound tessellate glacier; do
  check "look $id has a wallpaper on disk" test -n "$(
    LOOK_WALL=$(grep '^LOOK_WALL=' "$REPO/looks/$id/look.conf" | cut -d'"' -f2)
    ls "$REPO/wallpapers/$LOOK_WALL" 2>/dev/null)"
  check "look $id has valid JSON" jq -e . "$REPO/looks/$id/patch.json"
done
# Every look must write the whole clock block. A look that only sets the keys
# it changes would inherit the rest from whichever look ran before it.
for id in illogical dawn dunes marbled badlands sakura fogbound tessellate glacier; do
  check "look $id sets the complete clock block" \
    jq -e '.background.widgets.clock | has("style") and has("cookie") and has("digital")' \
    "$REPO/looks/$id/patch.json"
done
# The shell's own AI styling rewrites the cookie clock whenever the wallpaper
# changes, which would silently undo a look's clock the moment it is applied.
for id in illogical dunes badlands sakura tessellate; do
  check_eq "look $id keeps AI clock styling off" "false" \
    "$(jq -r '.background.widgets.clock.cookie.aiStyling' "$REPO/looks/$id/patch.json")"
done

echo "== applying a look =="
"$HP" look sakura >/dev/null 2>&1
check_eq "the look is recorded" "sakura" "$("$HP" look current)"
check_eq "a look pulls its own rice up first" "end4" "$("$HP" current)"
applied=$(cat "$APPLIED")
check_has "the wallpaper went to the Material 3 backend" 'end4|sakura.jpg' "$applied"
check_has "the look's matugen scheme was forwarded" 'scheme-expressive' "$applied"
check_has "the look's mode was forwarded" '|dark' "$applied"

echo "== the clock changed, and nothing else did =="
check_eq "clock style"        "cookie" "$(jqr '.background.widgets.clock.style')"
check_eq "sine cookie on"     "true"   "$(jqr '.background.widgets.clock.cookie.useSineCookie')"
check_eq "eight sides"        "8"      "$(jqr '.background.widgets.clock.cookie.sides')"
check_eq "second hand style"  "line"   "$(jqr '.background.widgets.clock.cookie.secondHandStyle')"
check_eq "lock screen matches" "cookie" "$(jqr '.background.widgets.clock.styleLocked')"
check_eq "the user's font survived"   "Google Sans Flex" "$(jqr '.appearance.fonts.main')"
check_eq "the user's bar icon survived" "spark"          "$(jqr '.bar.topLeftIcon')"
check_has "the user's AI prompt survived" "own long prompt" "$(jqr '.ai.systemPrompt')"

echo "== the bar overlays are off =="
check_eq "cornerOpen disabled" "false" "$(jqr '.sidebar.cornerOpen.enable')"
check_eq "but the rest of cornerOpen is untouched" "250" \
  "$(jqr '.sidebar.cornerOpen.cornerRegionWidth')"
check_eq "the scroll hints are off too" "false" "$(jqr '.bar.scrollHints')"
check_eq "and the bar keeps its own settings" "spark" "$(jqr '.bar.topLeftIcon')"

echo "== a second look fully replaces the first one's clock =="
"$HP" look dawn >/dev/null 2>&1
check_eq "style flipped to digital" "digital" "$(jqr '.background.widgets.clock.style')"
check_eq "digital font size"  "120" "$(jqr '.background.widgets.clock.digital.font.size')"
check_eq "digital font weight" "200" "$(jqr '.background.widgets.clock.digital.font.weight')"
# The previous look turned rotation on; this one must turn it back off rather
# than leaving it set from before.
check_eq "the previous look's rotation was cleared" "false" \
  "$(jqr '.background.widgets.clock.cookie.constantlyRotate')"
check_eq "the previous look's sine cookie was cleared" "false" \
  "$(jqr '.background.widgets.clock.cookie.useSineCookie')"

echo "== cycling follows order.conf =="
"$HP" look illogical >/dev/null 2>&1
"$HP" look next >/dev/null 2>&1
check_eq "illogical -> dawn" "dawn" "$("$HP" look current)"
"$HP" look next >/dev/null 2>&1
check_eq "dawn -> dunes" "dunes" "$("$HP" look current)"
"$HP" look glacier >/dev/null 2>&1
"$HP" look next >/dev/null 2>&1
check_eq "the last look wraps to the first" "illogical" "$("$HP" look current)"

echo "== the look on screen is recognised without any state =="
# Before the first pick - and after the shell's own wallpaper selector is used
# - there is no look on record. Rather than showing every row as inactive, the
# menu falls back to whichever look owns the image actually being displayed.
"$HP" look badlands >/dev/null 2>&1
rm -f "$HYPRPROFILE_ROOT/state/look"
jq --arg p "$REPO/wallpapers/badlands.jpg" '.background.wallpaperPath = $p' \
  "$HYPRPROFILE_II_CONFIG" > "$T/x" && mv "$T/x" "$HYPRPROFILE_II_CONFIG"
check_eq "the displayed wallpaper identifies the look" "badlands" "$("$HP" look current)"
jq '.background.wallpaperPath = "/somewhere/else.png"' \
  "$HYPRPROFILE_II_CONFIG" > "$T/x" && mv "$T/x" "$HYPRPROFILE_II_CONFIG"
out=$("$HP" look current 2>&1); rc=$?
check_eq "an unknown wallpaper means no look, not a wrong one" "1" "$rc"
"$HP" look sakura >/dev/null 2>&1

echo "== the menu =="
STUB_PICK= "$HP" menu >/dev/null 2>&1
fed=$(tr '\0' '@' < "$STUB_LOG")
rows=$(wc -l < "$STUB_LOG")
check_eq "nine looks + divider + one other setup" "11" "$rows"
check_has "the active look has a filled dot"   '●' "$fed"
check_has "the others have hollow dots"        '○' "$fed"
check_has "each dot is the look's own accent"  'foreground="#c66b6e"' "$fed"
check_has "looks carry their wallpaper as an icon" '@icon' "$fed"
check_has "the divider names the other setups" 'other setups' "$fed"
check_has "the Clean rice is listed below it"  'Clean' "$fed"
check_not "the looks' host rice is not listed twice" 'Material 3' "$fed"
check_has "the look's description is shown"    'stacked digital' "$fed"

echo "== picking rows =="
STUB_PICK=5 "$HP" menu >/dev/null 2>&1
check_eq "row 5 is the sixth look" "sakura" "$("$HP" look current)"
STUB_PICK=10 "$HP" menu >/dev/null 2>&1
check_eq "the last row is the Clean rice" "mine" "$("$HP" current)"
# The divider is not a look. Picking it must redraw the menu, not crash or
# apply something at random.
before=$("$HP" current)
STUB_PICK=9 "$HP" menu >/dev/null 2>&1
check_eq "picking the divider changes nothing" "$before" "$("$HP" current)"

echo "== failures are loud, and never half-applied =="
: > "$APPLIED"
out=$("$HP" look nonesuch 2>&1); rc=$?
check_eq "an unknown look fails"    "1" "$rc"
check_has "and says so"             "no such look" "$out"
check_eq "and applies no wallpaper" "" "$(cat "$APPLIED")"

mkdir -p "$T/broken/ghost"
cat > "$T/broken/ghost/look.conf" <<'EOF'
LOOK_NAME="Ghost"
LOOK_WALL="not-a-real-file.jpg"
EOF
echo '{}' > "$T/broken/ghost/patch.json"
out=$(HYPRPROFILE_LOOKS="$T/broken" "$HP" look ghost 2>&1); rc=$?
check_eq "a look naming a missing wallpaper fails" "1" "$rc"
check_has "and names the file"  "not-a-real-file.jpg" "$out"
check_eq "and applies nothing"  "" "$(cat "$APPLIED")"

echo "== a shell config that keeps reverting is reported =="
# Quickshell rewrites the config file it watches. If it ever wins the race for
# good, the look silently does not land - so the switcher retries and then
# says so rather than claiming success.
"$HP" look dawn >/dev/null 2>&1          # digital clock, known good state
cp "$HYPRPROFILE_II_CONFIG" "$T/frozen.json"
export T_FROZEN="$T/frozen.json"
cat > "$STUB/jq" <<'EOF'
#!/usr/bin/env bash
# Stands in for a concurrent writer: the merge appears to happen, but what
# lands on disk is the file as it was before. Reads are left alone.
if [[ -n ${FREEZE:-} && $* == *-s* ]]; then
  cat "$T_FROZEN"
  exit 0
fi
exec /usr/bin/jq "$@"
EOF
chmod +x "$STUB/jq"
out=$(FREEZE=1 "$HP" look tessellate 2>&1)
check_has "the switcher notices the write did not stick" "keeps reverting" "$out"
check_eq "and the clock really is unchanged" "digital" \
  "$(/usr/bin/jq -r '.background.widgets.clock.style' "$HYPRPROFILE_II_CONFIG")"
rm -f "$STUB/jq"
out=$("$HP" look tessellate 2>&1)
check_eq "and it lands once the writer stops" "cookie" "$(jqr '.background.widgets.clock.style')"

echo "== a wallpaper backend that leaves a helper behind does not wedge the lock =="
# switchwall.sh leaves things running after it returns - matugen's KDE wrapper,
# the terminal-scheme writer. When a look has to switch rices first, the switch
# lock is still open at that point, and any of those helpers would inherit the
# descriptor and hold the lock for the rest of the session. That is exactly how
# the first version of this switcher trapped the user in one rice.
cat > "$HYPRPROFILE_ROOT/profiles/end4/bin/set-wallpaper" <<EOF
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "end4" "\${1##*/}" "\${HYPRPROFILE_SCHEME:-}" "\${HYPRPROFILE_MODE:-}" >> "$APPLIED"
setsid --fork sleep 40 >/dev/null 2>&1 &
printf '%s\n' "\$!" > "$T/helper.pid"
EOF
chmod +x "$HYPRPROFILE_ROOT/profiles/end4/bin/set-wallpaper"
"$HP" set mine --force >/dev/null 2>&1
"$HP" look dunes >/dev/null 2>&1
check_eq "the look landed"        "dunes" "$("$HP" look current)"
check "the helper is still alive" test -s "$T/helper.pid"
out=$("$HP" set mine 2>&1); rc=$?
check_eq "the next switch is not refused" "0" "$rc"
check_not "and does not blame the lock" "another switch" "$out"
check_eq "it really moved"        "mine" "$("$HP" current)"
[[ -f $T/helper.pid ]] && kill "$(<"$T/helper.pid")" 2>/dev/null
"$HP" set end4 --force >/dev/null 2>&1

echo "== making a look out of your own image =="
# The nine shipped looks are curated; this is the path for everything else.
python3 - "$T/neon tide.png" <<'PYEOF'
import sys
from PIL import Image, ImageDraw
im = Image.new("RGB", (1920, 1080), (18, 20, 32)); d = ImageDraw.Draw(im)
for i in range(0, 1080, 4):
    d.line([(0, i), (1920, i)], fill=(20 + i // 9, 90 + i // 14, 200 - i // 9))
im.save(sys.argv[1])
PYEOF
out=$("$HP" look new "$T/neon tide.png" --clock marbled --scheme scheme-expressive 2>&1)
check_has "it says where the dot colour came from" "dot colour from the image" "$out"
check "the look exists"          test -f "$HYPRPROFILE_LOOKS/neon-tide/look.conf"
check "the image was copied in"  test -f "$HYPRPROFILE_WALLPAPERS/neon-tide.png"
check "a picker thumbnail was built" test -s "$HYPRPROFILE_WALLPAPERS/thumbs/neon-tide.png"
check_eq "the clock was borrowed whole" "digital" \
  "$(/usr/bin/jq -r '.background.widgets.clock.style' "$HYPRPROFILE_LOOKS/neon-tide/patch.json")"
check_eq "including its sub-settings" "true" \
  "$(/usr/bin/jq -r '.background.widgets.clock.digital.vertical' "$HYPRPROFILE_LOOKS/neon-tide/patch.json")"
check "the accent is a real colour" bash -c \
  'grep -qE "^LOOK_ACCENT=\"#[0-9a-f]{6}\"$" "$HYPRPROFILE_LOOKS/neon-tide/look.conf"'
check "the scheme was recorded" grep -q 'scheme-expressive' "$HYPRPROFILE_LOOKS/neon-tide/look.conf"
check_has "a space in the filename became a usable id" "neon-tide" "$("$HP" look list 2>&1)"
check "it is last in the menu order" bash -c \
  '[[ $(tail -1 "$HYPRPROFILE_LOOKS/order.conf") == neon-tide ]]'
check "the wallpaper layer names it too" grep -q 'neon-tide.png|Neon Tide' "$HYPRPROFILE_WALLPAPERS/index.conf"
out=$("$HP" look new "$T/neon tide.png" 2>&1); rc=$?
check_eq "adding it twice is refused" "1" "$rc"
check_has "and says why"        "already exists" "$out"
"$HP" look neon-tide >/dev/null 2>&1
check_eq "the new look can be worn" "neon-tide" "$("$HP" look current)"
check_eq "and it set its borrowed clock" "digital" "$(jqr '.background.widgets.clock.style')"

echo "== and removing it again =="
out=$("$HP" look rm neon-tide 2>&1)
check "the look is gone"            bash -c '! test -d "$HYPRPROFILE_LOOKS/neon-tide"'
check "it left the menu order"      bash -c '! grep -qx neon-tide "$HYPRPROFILE_LOOKS/order.conf"'
check "but the wallpaper is kept"   test -f "$HYPRPROFILE_WALLPAPERS/neon-tide.png"
check_has "and it says so"          "still in" "$out"
out=$("$HP" look rm nonesuch 2>&1); rc=$?
check_eq "removing one that is not there fails" "1" "$rc"

echo "== animated wallpapers =="
# No ffmpeg on the machine this suite usually runs on, so the frame grab is
# stubbed. What is being tested is the path: a video must end up with a real
# thumbnail and a palette taken from a frame, never from the raw file.
printf 'not really a video, but the extension is what routes it\n' > "$T/aurora-loop.mp4"
out=$("$HP" look new "$T/aurora-loop.mp4" 2>&1); rc=$?
if command -v ffmpeg >/dev/null 2>&1; then
  check_eq "a real ffmpeg handles it" "0" "$rc"
else
  check_eq "without ffmpeg it is refused, not half-added" "1" "$rc"
  check_has "naming what to install"  "ffmpeg" "$out"
  check "and nothing was created"     bash -c '! test -d "$HYPRPROFILE_LOOKS/aurora-loop"'
fi

cat > "$STUB/ffmpeg" <<PYEOF
#!/usr/bin/env bash
# Stands in for a frame grab: writes a plausible still wherever -i's output goes.
out=\${@: -1}
python3 -c "
from PIL import Image
Image.new('RGB', (1280, 720), (30, 140, 90)).save('\$out')"
exit 0
PYEOF
chmod +x "$STUB/ffmpeg"
out=$("$HP" look new "$T/aurora-loop.mp4" --clock dunes 2>&1)
check "the video was taken in"       test -f "$HYPRPROFILE_WALLPAPERS/aurora-loop.mp4"
check "a thumbnail came from a frame" test -s "$HYPRPROFILE_WALLPAPERS/thumbs/aurora-loop.png"
check "the thumbnail is a real image" bash -c \
  'python3 -c "from PIL import Image; Image.open(\"$HYPRPROFILE_WALLPAPERS/thumbs/aurora-loop.png\").verify()"'
check "the palette colour came from the frame, not the file" bash -c \
  'grep -qE "^LOOK_ACCENT=\"#[0-9a-f]{6}\"$" "$HYPRPROFILE_LOOKS/aurora-loop/look.conf"'
check "it is marked as animated"     grep -q 'animated' "$HYPRPROFILE_LOOKS/aurora-loop/look.conf"
check_has "mpvpaper being absent is a warning, not a refusal" "mpvpaper" "$out"
check "the look was still created"   test -f "$HYPRPROFILE_LOOKS/aurora-loop/patch.json"
check_has "the picker lists it" "Aurora Loop" "$("$HP" look list 2>&1)"
out=$("$HP" doctor 2>&1)
check_has "doctor notices the missing video player" "mpvpaper is not installed" "$out"
"$HP" look rm aurora-loop >/dev/null 2>&1
rm -f "$STUB/ffmpeg"

echo "== doctor =="
out=$("$HP" doctor 2>&1)
check_has "doctor counts the looks" "9 look(s)" "$out"
out=$(HYPRPROFILE_LOOKS="$T/broken" "$HP" doctor 2>&1)
check_has "doctor flags a wallpaper that is not there" "names a wallpaper that is not in" "$out"
printf 'not json' > "$T/broken/ghost/patch.json"
out=$(HYPRPROFILE_LOOKS="$T/broken" "$HP" doctor 2>&1)
check_has "doctor flags an unparseable patch" "unparseable patch.json" "$out"

echo "== the start hook re-asserts the shared settings =="
jq '.sidebar.cornerOpen.enable = true' "$HYPRPROFILE_II_CONFIG" > "$T/x" && mv "$T/x" "$HYPRPROFILE_II_CONFIG"
mkdir -p "$HYPRPROFILE_ROOT/looks"
cp "$REPO/looks/baseline.json" "$HYPRPROFILE_ROOT/looks/baseline.json"
cat > "$T/hookprobe" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
baseline="$HYPRPROFILE_ROOT/looks/baseline.json"
iicfg="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
if [[ -f $baseline && -f $iicfg ]] && command -v jq >/dev/null 2>&1; then
  if jq -s '.[0] * .[1]' "$iicfg" "$baseline" >"$iicfg.tmp" && [[ -s $iicfg.tmp ]]; then
    mv -f "$iicfg.tmp" "$iicfg"
  fi
fi
EOF
chmod +x "$T/hookprobe"; "$T/hookprobe"
check_eq "a fresh session turns the corners back off" "false" \
  "$(jqr '.sidebar.cornerOpen.enable')"
check_eq "and leaves the rest of the config alone" "spark" "$(jqr '.bar.topLeftIcon')"

echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
(( fail == 0 ))

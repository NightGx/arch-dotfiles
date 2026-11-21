#!/usr/bin/env bash
# Looks - one rice, several appearances.
#
# A "look" is not another desktop. It is the same Material 3 config wearing
# different clothes: a wallpaper, the Material You palette derived from that
# wallpaper, and a desktop clock style. Everything else - the bar, the
# sidebars, the launcher, the keybinds - is identical across every look, which
# is the whole point: switching one is a repaint, not a rebuild.
#
# That makes a look far cheaper than a profile switch. No symlink farm, no
# hyprctl reload, no restarting the shell. Quickshell watches its config file
# and re-reads it, so a look lands in well under a second.
#
# Sourced by bin/hyprprofile, which has already defined ROOT / PROFILES_DIR /
# STATE_DIR / CONFIG_HOME and the info/warn/note/die helpers.

LOOKS_DIR="${HYPRPROFILE_LOOKS:-$ROOT/looks}"
LOOK_STATE="$STATE_DIR/look"
LOOK_BASELINE="$LOOKS_DIR/baseline.json"

# The one profile looks apply to. Looks are that rice's wardrobe; the Clean
# profile has no bar and no clock widget, so it has nothing to dress.
LOOK_PROFILE="${HYPRPROFILE_LOOK_PROFILE:-end4}"

II_CONFIG="${HYPRPROFILE_II_CONFIG:-$CONFIG_HOME/illogical-impulse/config.json}"

# ------------------------------------------------------------ enumeration ---

look_exists() { [[ -f "$LOOKS_DIR/$1/look.conf" ]]; }

# Ids in menu order: order.conf first (one id per line, # comments allowed),
# then anything else on disk, sorted, so dropping in a new folder is enough to
# make it appear.
look_ids() {
  local seen=() id d s dup
  if [[ -f $LOOKS_DIR/order.conf ]]; then
    while read -r id _; do
      [[ -n ${id:-} && ${id:0:1} != '#' ]] || continue
      look_exists "$id" || continue
      seen+=("$id"); printf '%s\n' "$id"
    done <"$LOOKS_DIR/order.conf"
  fi
  shopt -s nullglob
  for d in "$LOOKS_DIR"/*/; do
    id=${d%/}; id=${id##*/}
    look_exists "$id" || continue
    dup=0; for s in ${seen+"${seen[@]}"}; do [[ $s == "$id" ]] && { dup=1; break; }; done
    (( dup )) || printf '%s\n' "$id"
  done
  shopt -u nullglob
}

# Fills LOOK_* from looks/<id>/look.conf. Defaults first, so a look.conf that
# leaves something out still produces a complete, usable look.
look_load() {
  local id=$1
  look_exists "$id" || return 1
  LOOK_ID=$id
  LOOK_NAME=$id
  LOOK_DESC=""
  LOOK_WALL=""
  LOOK_ACCENT="#8ab4f8"
  LOOK_SCHEME="scheme-tonal-spot"
  LOOK_MODE="dark"
  # shellcheck disable=SC1090
  source "$LOOKS_DIR/$id/look.conf"
  return 0
}

look_patch_of() { printf '%s\n' "$LOOKS_DIR/$1/patch.json"; }

# Absolute path of a look's wallpaper, or nothing when it names one that is
# not on disk.
look_wall_path() {
  local id=$1
  ( look_load "$id" || exit 1
    [[ -n $LOOK_WALL ]] || exit 1
    if [[ $LOOK_WALL == /* ]]; then
      [[ -f $LOOK_WALL ]] && printf '%s\n' "$LOOK_WALL"
    else
      [[ -f "$WALLPAPER_DIR/$LOOK_WALL" ]] && printf '%s\n' "$WALLPAPER_DIR/$LOOK_WALL"
    fi )
}

# id <TAB> name <TAB> accent <TAB> wallpaper <TAB> thumb <TAB> description
look_entries() {
  local id path thumb
  while read -r id; do
    [[ -n $id ]] || continue
    ( look_load "$id" || exit 0
      path=$(look_wall_path "$id") || path=
      thumb=$([[ -n ${LOOK_WALL:-} ]] && wp_thumb_of "$(wp_id_of "$LOOK_WALL")" || printf '')
      [[ -f ${thumb:-} ]] || thumb=$path
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$LOOK_NAME" "$LOOK_ACCENT" "$path" "$thumb" "$LOOK_DESC" )
  done < <(look_ids)
}

look_current() {
  if [[ -f $LOOK_STATE ]]; then
    local v; v=$(<"$LOOK_STATE")
    [[ -n $v ]] && look_exists "$v" && { printf '%s\n' "$v"; return 0; }
  fi
  # No look on record - which is the case before the first one is picked, and
  # again if the wallpaper was changed through the shell's own selector. Fall
  # back to whichever look owns the image actually on screen, so the menu
  # still shows a filled dot rather than claiming nothing is in use.
  local shown id path
  shown=$(ii_get 'background.wallpaperPath') || return 1
  [[ -n $shown ]] || return 1
  while IFS=$'\t' read -r id _ _ path _; do
    [[ -n $path && $path == "$shown" ]] && { printf '%s\n' "$id"; return 0; }
  done < <(look_entries)
  return 1
}

look_name_of() {
  local want=$1 id name
  while IFS=$'\t' read -r id name _; do
    [[ $id == "$want" ]] && { printf '%s\n' "$name"; return 0; }
  done < <(look_entries)
  printf '%s\n' "$want"
}

# ------------------------------------------------- illogical-impulse config --
#
# Quickshell keeps its settings in one JSON file and watches it, so a look is
# applied by merging a small patch into that file. Two rules make this safe:
#
#   * merge, never replace - the file also holds the user's own settings, and
#     a look only owns the handful of keys it names;
#   * write via a temp file and rename, which is exactly how end-4's own
#     switchwall.sh writes it, so Quickshell's file watcher reacts the same way.

ii_have_merger() { command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; }

# Deep-merge every patch file into config.json, left to right.
ii_merge() {
  local tmp rc=0
  (( $# )) || return 0
  [[ -f $II_CONFIG ]] || {
    mkdir -p "$(dirname "$II_CONFIG")"
    printf '{}\n' >"$II_CONFIG"
  }
  tmp="$II_CONFIG.hyprprofile.tmp"

  if command -v jq >/dev/null 2>&1; then
    # jq's * merges objects recursively and replaces scalars and arrays, which
    # is what a patch should do.
    jq -s 'reduce .[] as $x ({}; . * $x)' "$II_CONFIG" "$@" >"$tmp" || rc=$?
  else
    python3 - "$II_CONFIG" "$tmp" "$@" <<'PY' || rc=$?
import json, sys
base_p, out_p, *patches = sys.argv[1:]
def merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict):
            merge(a[k], v)
        else:
            a[k] = v
    return a
with open(base_p) as f:
    data = json.load(f)
for p in patches:
    with open(p) as f:
        merge(data, json.load(f))
with open(out_p, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
  fi

  if (( rc )) || [[ ! -s $tmp ]]; then
    rm -f "$tmp"
    warn "could not merge the look into ${II_CONFIG/#$HOME/\~} (jq/python3 failed)"
    return 1
  fi
  mv -f "$tmp" "$II_CONFIG"
  return 0
}

# Read one dotted key out of config.json. Used to check a patch actually stuck.
ii_get() {
  local key=$1
  [[ -f $II_CONFIG ]] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" 'getpath($k | split("."))? // empty' "$II_CONFIG" 2>/dev/null
  else
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    if not isinstance(d, dict) or k not in d: sys.exit(1)
    d = d[k]
print(json.dumps(d) if isinstance(d, (dict, list)) else d)' "$II_CONFIG" "$key" 2>/dev/null
  fi
}

# Merge, then read back a key the patch set and try again if it did not land.
#
# Quickshell reloads the file when it changes and writes its own copy back a
# beat later, so a write that lands inside that window can be echoed over. It
# is a narrow race and a cheap one to lose, so rather than reason about the
# timing we check and repeat.
ii_apply_verified() { # ii_apply_verified <canary-key> <expected> <patch>...
  local key=$1 want=$2; shift 2
  local try got
  for try in 1 2 3; do
    ii_merge "$@" || return 1
    got=$(ii_get "$key")
    [[ $got == "$want" ]] && return 0
    log "look: $key was \"$got\", wanted \"$want\" - retry $try"
    sleep 0.4
  done
  warn "the shell config keeps reverting $key - is something else writing it?"
  return 1
}

# ----------------------------------------------------------------- apply ----

look_apply() {
  local id=$1 cur img rc=0
  look_exists "$id" || die "no such look: $id (try: hyprprofile look list)"
  look_load "$id"

  img=$(look_wall_path "$id")
  [[ -n $img ]] || die "$LOOK_NAME names a wallpaper that is not there: $LOOK_WALL"

  ii_have_merger ||
    die "looks need jq (or python3) to edit the shell config - install jq"

  # A look dresses one rice. If another one is up, put that rice on first;
  # nothing below would have anywhere to land otherwise.
  cur=$(current_profile) || cur=
  if [[ $cur != "$LOOK_PROFILE" ]]; then
    profile_exists "$LOOK_PROFILE" ||
      die "looks need the $LOOK_PROFILE profile, which is not installed"
    info "$LOOK_NAME is a $LOOK_PROFILE look - switching there first"
    cmd_set "$LOOK_PROFILE" || return 1
    cur=$LOOK_PROFILE
  fi

  info "applying look: $LOOK_NAME"

  # 1. Wallpaper and palette, through end-4's own pipeline: it paints, runs
  #    matugen with the look's scheme, rebuilds the terminal colours and pokes
  #    the Qt/KDE side. Re-doing any of that here would only drift from it.
  HYPRPROFILE_SCHEME=$LOOK_SCHEME HYPRPROFILE_MODE=$LOOK_MODE \
    wp_apply "$(wp_id_of "$LOOK_WALL")" || rc=$?

  # 2. The clock, plus the settings every look shares. This goes last: it is
  #    the write we most need to survive, and switchwall.sh edits the same
  #    file on its way through.
  local -a patches=()
  [[ -f $LOOK_BASELINE ]] && patches+=("$LOOK_BASELINE")
  patches+=("$(look_patch_of "$id")")
  ii_apply_verified 'background.widgets.clock.style' \
    "$(ii_patch_style "$id")" "${patches[@]}" || rc=1

  printf '%s\n' "$id" >"$LOOK_STATE"
  log "look $id rc=$rc"
  ok "look: $LOOK_NAME"
  notify "Look: $LOOK_NAME" "${LOOK_DESC:-wallpaper, colours and clock updated}"
  return 0
}

# The clock style a look's patch asks for - the canary ii_apply_verified reads
# back to prove the merge landed.
ii_patch_style() {
  local p; p=$(look_patch_of "$1")
  [[ -f $p ]] || { printf 'cookie\n'; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -r '.background.widgets.clock.style // "cookie"' "$p" 2>/dev/null
  else
    python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("background",{}).get("widgets",{}).get("clock",{}).get("style","cookie"))' "$p" 2>/dev/null
  fi
}

# ---------------------------------------------------------------- authoring --

# Turn any image or video into a look: copy it in, build the picker
# thumbnail, work out its dot colour, borrow a clock, and add it to the menu.
#
# The clock is borrowed rather than invented because a clock style is a dozen
# interlocking settings; naming an existing look is a far better interface
# than asking for twelve values, and it keeps every look's patch complete.
look_new() {
  local src="" id="" name="" accent="" scheme="scheme-tonal-spot" mode="dark"
  local clock_from="illogical" apply=0 force=0

  while (( $# )); do
    case $1 in
      --name)   name=$2;       shift 2 ;;
      --id)     id=$2;         shift 2 ;;
      --clock)  clock_from=$2; shift 2 ;;
      --scheme) scheme=$2;     shift 2 ;;
      --accent) accent=$2;     shift 2 ;;
      --mode)   mode=$2;       shift 2 ;;
      --apply)  apply=1;       shift ;;
      --force)  force=1;       shift ;;
      -*)       die "unknown option for look new: $1" ;;
      *)        [[ -z $src ]] && src=$1 || die "one image at a time"; shift ;;
    esac
  done

  [[ -n $src ]] || die "usage: hyprprofile look new <image|video> [--name X] [--clock <look>] [--scheme <s>] [--apply]"
  [[ -f $src ]] || die "no such file: $src"
  declare -F ing_accent >/dev/null ||
    die "looks need lib/ingest.sh to add a wallpaper - reinstall with ./install.sh"
  ing_have || die "needs ImageMagick or python-pillow to build the thumbnail"

  # A video needs ffmpeg to yield a frame; without one there is no thumbnail
  # and no palette, so say that now rather than half-adding it.
  if ing_is_video "$src"; then
    command -v ffmpeg   >/dev/null 2>&1 || die "video wallpapers need ffmpeg (sudo pacman -S ffmpeg)"
    command -v mpvpaper >/dev/null 2>&1 ||
      warn "mpvpaper is not installed - the video will not play (sudo pacman -S mpvpaper)"
  fi

  [[ -n $id ]]   || id=$(ing_slug "$src")
  [[ -n $name ]] || name=$(ing_pretty "$id")
  look_exists "$id" && (( force == 0 )) &&
    die "a look called $id already exists (use --force to replace it)"

  # Two statements, not one: in `local a=$1 b=$a` the second assignment is
  # expanded before the first has taken effect.
  local ext=${src##*.}
  local dest="$WALLPAPER_DIR/$id.${ext,,}"
  mkdir -p "$WALLPAPER_DIR" "$WALLPAPER_DIR/thumbs"
  if [[ $(readlink -m "$src") != $(readlink -m "$dest") ]]; then
    cp -f "$src" "$dest" || die "could not copy $src into $WALLPAPER_DIR"
    info "copied $(basename "$src") -> ${dest/#$HOME/\~}"
  fi

  info "building the picker thumbnail"
  ing_thumb "$dest" "$WALLPAPER_DIR/thumbs/$id.png" ||
    warn "could not build a thumbnail - the picker will fall back to the full file"

  if [[ -z $accent ]]; then
    accent=$(ing_accent "$dest"); accent=${accent:-#8ab4f8}
    info "dot colour from the image: $accent"
  fi
  [[ $accent == \#* ]] || accent="#$accent"

  # Keep index.conf in step so the wallpaper layer names it the same way.
  local index="$WALLPAPER_DIR/index.conf"
  [[ -f $index ]] || printf '# <file>|<display name>|<accent colour for the picker dot>\n' >"$index"
  if ! grep -q "^$id\.${ext,,}|" "$index" 2>/dev/null; then
    printf '%s|%s|%s\n' "$id.${ext,,}" "$name" "$accent" >>"$index"
  fi

  local kind=""
  ing_is_video "$dest" && kind="animated, "

  local dir="$LOOKS_DIR/$id"
  mkdir -p "$dir"
  cat >"$dir/look.conf" <<EOF
# $name - added by \`hyprprofile look new\`
LOOK_NAME="$name"
LOOK_DESC="${kind}clock borrowed from $clock_from"
LOOK_WALL="$id.${ext,,}"
LOOK_ACCENT="$accent"
LOOK_SCHEME="$scheme"
LOOK_MODE="$mode"
EOF

  if look_exists "$clock_from" && [[ -f $LOOKS_DIR/$clock_from/patch.json ]]; then
    cp -f "$LOOKS_DIR/$clock_from/patch.json" "$dir/patch.json"
  else
    warn "no look called $clock_from to borrow a clock from - using the stock cookie clock"
    cat >"$dir/patch.json" <<'EOF'
{ "background": { "widgets": { "clock": {
  "enable": true, "style": "cookie", "styleLocked": "cookie",
  "showOnlyWhenLocked": false, "placementStrategy": "leastBusy", "x": 100, "y": 100,
  "cookie": { "aiStyling": false, "sides": 14, "dialNumberStyle": "full",
    "hourHandStyle": "fill", "minuteHandStyle": "medium", "secondHandStyle": "dot",
    "dateStyle": "bubble", "timeIndicators": true, "hourMarks": false,
    "dateInClock": true, "constantlyRotate": false, "useSineCookie": false },
  "digital": { "adaptiveAlignment": true, "showDate": true, "animateChange": true,
    "vertical": false, "font": { "family": "Google Sans Flex", "weight": 350,
    "width": 100, "size": 90, "roundness": 0 } }
} } } }
EOF
  fi

  # Put it at the end of the menu unless it is already listed.
  local order="$LOOKS_DIR/order.conf"
  [[ -f $order ]] || printf '# Menu order. One look id per line.\n' >"$order"
  grep -qx "$id" "$order" 2>/dev/null || printf '%s\n' "$id" >>"$order"

  ok "added look: $name  ($id)"
  log "look new $id from $src"
  (( apply )) && look_apply "$id"
  return 0
}

# Remove a look from the menu. The wallpaper itself is left in place - it is
# shared with the wallpaper layer and may well be in use.
look_rm() {
  local id=${1:-}
  [[ -n $id ]] || die "usage: hyprprofile look rm <id>"
  look_exists "$id" || die "no such look: $id"
  rm -rf "${LOOKS_DIR:?}/$id"
  local order="$LOOKS_DIR/order.conf"
  if [[ -f $order ]]; then
    grep -vx "$id" "$order" >"$order.tmp" && mv "$order.tmp" "$order"
  fi
  [[ $(look_current 2>/dev/null) == "$id" ]] && rm -f "$LOOK_STATE"
  ok "removed look: $id  (its wallpaper is still in $WALLPAPER_DIR)"
  log "look rm $id"
}

look_next() {
  local ids=() id cur i
  mapfile -t ids < <(look_ids)
  (( ${#ids[@]} )) || die "no looks in $LOOKS_DIR"
  cur=$(look_current) || cur=
  for i in "${!ids[@]}"; do
    if [[ ${ids[i]} == "$cur" ]]; then
      look_apply "${ids[(i + 1) % ${#ids[@]}]}"
      return
    fi
  done
  look_apply "${ids[0]}"
}

look_list() {
  local cur id name accent path thumb desc any=0 mark colour
  cur=$(look_current) || cur=
  while IFS=$'\t' read -r id name accent path thumb desc; do
    any=1
    mark="  "; colour="$C_RST"
    [[ $id == "$cur" ]] && { mark="* "; colour="$C_GRN"; }
    printf '%s%s%-14s%s %-18s %s%s%s\n' \
      "$colour" "$mark" "$id" "$C_RST" "$name" "$C_DIM" "$desc" "$C_RST"
  done < <(look_entries)
  (( any )) || warn "no looks in $LOOKS_DIR"
}

#!/usr/bin/env bash
# Wallpaper + palette handling for hyprprofile.
#
# Picking a wallpaper sets the desktop image AND regenerates the Material You
# palette from it, through whatever mechanism the active profile provides.
# Each profile ships bin/set-wallpaper; if it does not, the generic painter
# below is used.
#
# Looks are the layer above this: a look is a wallpaper plus the scheme used to
# derive the palette plus a clock style. This file knows nothing about them.
#
# Sourced by bin/hyprprofile, which has already defined ROOT / PROFILES_DIR /
# STATE_DIR and the info/warn/die helpers.

WALLPAPER_DIR="${HYPRPROFILE_WALLPAPERS:-$ROOT/wallpapers}"
WALLPAPER_INDEX="$WALLPAPER_DIR/index.conf"
WALLPAPER_THUMBS="$WALLPAPER_DIR/thumbs"
WALLPAPER_STATE="$STATE_DIR/wallpaper"

wp_is_image() {
  case ${1,,} in
    *.jpg|*.jpeg|*.png|*.webp|*.bmp|*.gif|*.mp4|*.webm|*.mkv|*.mov) return 0 ;;
    *) return 1 ;;
  esac
}

wp_id_of() { local b=${1##*/}; printf '%s\n' "${b%.*}"; }

# Prettify a bare filename when index.conf has no entry for it:
# "my_cool-wall.jpg" -> "My Cool Wall"
wp_pretty() {
  local s=${1//[_-]/ }
  s=$(printf '%s\n' "$s" | sed -E 's/(^| )([a-z])/\1\u\2/g')
  printf '%s\n' "$s"
}

wp_thumb_of() {
  local id=$1 t
  for t in "$WALLPAPER_THUMBS/$id".{jpg,png,jpeg,webp}; do
    [[ -f $t ]] && { printf '%s\n' "$t"; return 0; }
  done
  # No pre-built thumbnail: the picker can use the full image, it just costs
  # more to decode.
  wp_path_of "$id"
}

wp_path_of() {
  local id=$1 f
  for f in "$WALLPAPER_DIR/$id".{jpg,jpeg,png,webp,bmp,gif,mp4,webm,mkv,mov}; do
    [[ -f $f ]] && { printf '%s\n' "$f"; return 0; }
  done
  # Also accept a full path, so `hyprprofile wallpaper ~/pic.png` works.
  [[ -f $id ]] && { printf '%s\n' "$id"; return 0; }
  return 1
}

# Every selectable wallpaper as: id <TAB> name <TAB> accent <TAB> path <TAB> thumb
# Indexed entries keep index.conf's order; anything else in the folder follows,
# sorted, so dropping a new image in is enough to make it appear.
wp_entries() {
  local seen=() line file name accent path id f

  if [[ -f $WALLPAPER_INDEX ]]; then
    while IFS='|' read -r file name accent; do
      [[ -n ${file:-} ]] || continue
      [[ ${file:0:1} == '#' ]] && continue
      path="$WALLPAPER_DIR/$file"
      [[ -f $path ]] || continue
      id=$(wp_id_of "$file")
      seen+=("$id")
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$id" "${name:-$(wp_pretty "$id")}" "${accent:-#8ab4f8}" "$path" "$(wp_thumb_of "$id")"
    done <"$WALLPAPER_INDEX"
  fi

  shopt -s nullglob nocaseglob
  for f in "$WALLPAPER_DIR"/*; do
    [[ -f $f ]] || continue
    wp_is_image "$f" || continue
    id=$(wp_id_of "$f")
    local dup=0 s
    for s in ${seen+"${seen[@]}"}; do [[ $s == "$id" ]] && { dup=1; break; }; done
    (( dup )) && continue
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$id" "$(wp_pretty "$id")" "#8ab4f8" "$f" "$(wp_thumb_of "$id")"
  done
  shopt -u nullglob nocaseglob
}

wp_current() {
  [[ -f $WALLPAPER_STATE ]] || return 1
  local v; v=$(<"$WALLPAPER_STATE"); [[ -n $v ]] || return 1
  printf '%s\n' "$v"
}

wp_name_of() {
  local want=$1 id name
  while IFS=$'\t' read -r id name _; do
    [[ $id == "$want" ]] && { printf '%s\n' "$name"; return 0; }
  done < <(wp_entries)
  printf '%s\n' "$(wp_pretty "$want")"
}

# ------------------------------------------------------------- painters ----
# Used only when the active profile ships no bin/set-wallpaper of its own.

wp_paint_generic() {
  local img=$1
  if command -v swww >/dev/null 2>&1; then
    swww query >/dev/null 2>&1 || { swww-daemon >/dev/null 2>&1 & sleep 0.6; }
    swww img "$img" --transition-type grow --transition-fps 60 --transition-duration 1 >/dev/null 2>&1 && return 0
  fi
  if command -v hyprpaper >/dev/null 2>&1; then
    pgrep -u "$UID" -x hyprpaper >/dev/null 2>&1 || { setsid --fork hyprpaper >/dev/null 2>&1 & sleep 0.6; }
    hyprctl hyprpaper preload "$img"  >/dev/null 2>&1
    hyprctl hyprpaper wallpaper ",$img" >/dev/null 2>&1 && return 0
  fi
  return 1
}

wp_colors_generic() {
  local img=$1
  command -v matugen >/dev/null 2>&1 || return 1
  matugen image "$img" >/dev/null 2>&1
}

# ---------------------------------------------------------------- apply ----

wp_apply() {
  local id=$1 cur img hook rc=0
  cur=$(current_profile) || cur=

  img=$(wp_path_of "$id") || die "no such wallpaper: $id (try: hyprprofile wallpaper list)"

  hook="$PROFILES_DIR/${cur:-}/bin/set-wallpaper"
  if [[ -n $cur && -x $hook ]]; then
    info "applying wallpaper through the $cur profile"
    # A look also names how matugen should harmonise the palette it derives
    # from the image; a bare `wallpaper` call leaves both blank and the
    # profile picks its own default.
    HYPRPROFILE_ROOT="$ROOT" HYPRPROFILE_NAME="$cur" \
      HYPRPROFILE_DIR="$PROFILES_DIR/$cur" \
      HYPRPROFILE_SCHEME="${HYPRPROFILE_SCHEME:-}" \
      HYPRPROFILE_MODE="${HYPRPROFILE_MODE:-}" \
      "$hook" "$img" >>"$LOG_FILE" 2>&1 9>&- || rc=$?
  else
    wp_paint_generic  "$img" || warn "no wallpaper daemon found (install swww or hyprpaper)"
    wp_colors_generic "$img" || note "matugen not available - colours left alone"
    hypr_running && hyprctl reload >/dev/null 2>&1
  fi

  printf '%s\n' "$id" >"$WALLPAPER_STATE"
  log "wallpaper $id (profile ${cur:-none}) rc=$rc"
  (( rc == 0 )) || warn "the $cur wallpaper hook exited $rc (see $LOG_FILE)"
  ok "wallpaper: $(wp_name_of "$id")"
  notify "Wallpaper: $(wp_name_of "$id")" "Colours regenerated from the image"
  return 0
}

wp_next() {
  local ids=() id cur i
  while IFS=$'\t' read -r id _; do ids+=("$id"); done < <(wp_entries)
  (( ${#ids[@]} )) || die "no wallpapers in $WALLPAPER_DIR"
  cur=$(wp_current) || cur=
  for i in "${!ids[@]}"; do
    if [[ ${ids[i]} == "$cur" ]]; then
      wp_apply "${ids[(i + 1) % ${#ids[@]}]}"
      return
    fi
  done
  wp_apply "${ids[0]}"
}

wp_list() {
  local cur id name accent path
  cur=$(wp_current) || cur=
  local any=0
  while IFS=$'\t' read -r id name accent path _; do
    any=1
    local mark="  "; local colour="$C_RST"
    [[ $id == "$cur" ]] && { mark="* "; colour="$C_GRN"; }
    printf '%s%s%-22s%s %s%s%s\n' "$colour" "$mark" "$id" "$C_RST" "$C_DIM" "$name" "$C_RST"
  done < <(wp_entries)
  (( any )) || warn "no wallpapers in $WALLPAPER_DIR"
}

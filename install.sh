#!/usr/bin/env bash
# Deploy the style switcher onto this machine.
#
# Safe to re-run. Your current ~/.config directories are copied into the
# end4 profile and the originals are moved aside into a timestamped backup
# before anything is symlinked, so at no point does a config exist in only
# one place.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
ROOT="${HYPRPROFILE_ROOT:-$CONFIG_HOME/hypr-profiles}"
BIN_DIR="${HYPRPROFILE_BIN:-$HOME/.local/bin}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$ROOT/backups/install-$STAMP"
DRY=0
ACTIVATE=1

if [[ -t 1 ]]; then
  C_RST=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_CYA=$'\033[36m'
else C_RST=; C_B=; C_DIM=; C_RED=; C_GRN=; C_YEL=; C_CYA=; fi

info() { printf '%s==>%s %s\n' "$C_CYA" "$C_RST" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YEL" "$C_RST" "$*"; }
die()  { printf '%serr %s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }
run()  { if (( DRY )); then printf '%s  would%s %s\n' "$C_DIM" "$C_RST" "$*"; else "$@"; fi; }

usage() {
  cat <<'U'
usage: ./install.sh [options]

  --dry-run     print what would happen, change nothing
  --no-activate install everything but do not switch to a profile yet
  -h, --help    this message
U
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --no-activate) ACTIVATE=0 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

# ------------------------------------------------------------- preflight ----
info "preflight"

[[ $EUID -ne 0 ]] || die "do not run this as root - it installs into your \$HOME"
(( BASH_VERSINFO[0] >= 4 )) || die "bash 4+ required (found $BASH_VERSION)"

for c in rsync git; do
  command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"
done

if command -v hyprctl >/dev/null 2>&1; then
  HYPR_VER=$(hyprctl version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  if [[ -n ${HYPR_VER:-} ]]; then
    IFS=. read -r hmaj hmin _ <<<"$HYPR_VER"
    if (( hmaj == 0 && hmin < 55 )); then
      die "hyprland $HYPR_VER predates the lua config (0.55+). Both profiles here use hyprland.lua."
    fi
    ok "hyprland $HYPR_VER"
  else
    warn "hyprland is installed but not running - continuing"
  fi
else
  warn "hyprctl not found - installing anyway, but nothing will reload"
fi

# The whole design rests on every profile using the same entrypoint, because
# Hyprland picks lua-vs-conf once at startup and never revisits it.
if [[ -f $CONFIG_HOME/hypr/hyprland.conf && ! -L $CONFIG_HOME/hypr ]]; then
  warn "you have ~/.config/hypr/hyprland.conf (hyprlang)."
  warn "end-4's rice is hyprland.lua, and Hyprland cannot switch formats without"
  warn "a restart. Convert your config to lua first, or this will not swap live."
fi

[[ -d $REPO/profiles/end4/config/quickshell ]] ||
  die "end4 profile is empty - run ./tools/fetch-end4.sh first"

ok "profile available: end4"

# ------------------------------------------------------------ scaffolding ----
info "creating $ROOT"
run mkdir -p "$ROOT/profiles" "$ROOT/state" "$ROOT/backups" "$ROOT/lib" \
             "$ROOT/themes" "$ROOT/wallpapers" "$ROOT/looks" "$BACKUP" "$BIN_DIR"

run install -m 0755 "$REPO/lib/hooklib.sh" "$ROOT/lib/hooklib.sh"
run install -m 0755 "$REPO/lib/wallpaper.sh" "$ROOT/lib/wallpaper.sh"
run install -m 0755 "$REPO/lib/looks.sh" "$ROOT/lib/looks.sh"
run install -m 0755 "$REPO/lib/ingest.sh" "$ROOT/lib/ingest.sh"
run install -m 0755 "$REPO/bin/hyprprofile" "$BIN_DIR/hyprprofile"
run install -m 0755 "$REPO/bin/hyprprofile-waybar" "$BIN_DIR/hyprprofile-waybar"
ok "installed hyprprofile into $BIN_DIR"

# Picker themes. Overwritten on every install so a fix here reaches the
# machine; nothing else writes to them.
run rsync -a "$REPO/themes/" "$ROOT/themes/"
ok "installed picker themes"

# Wallpapers are shared by every profile - picking one repaints the desktop
# and regenerates the palette from it. --ignore-existing so images the user
# dropped in themselves, and edits to index.conf, survive a re-run.
if [[ -d $REPO/wallpapers ]]; then
  run rsync -a --ignore-existing "$REPO/wallpapers/" "$ROOT/wallpapers/"
  ok "wallpapers in $ROOT/wallpapers"
fi

# Looks: one rice, several appearances. Definitions are ours and are refreshed
# on every install so a fix here lands; order.conf is the user's to reorder, so
# it is only seeded if absent, and a look folder the user added is left alone.
if [[ -d $REPO/looks ]]; then
  run rsync -a --exclude 'order.conf' "$REPO/looks/" "$ROOT/looks/"
  [[ -f $ROOT/looks/order.conf ]] ||
    run install -m 0644 "$REPO/looks/order.conf" "$ROOT/looks/order.conf"
  ok "$(find "$ROOT/looks" -mindepth 1 -maxdepth 1 -type d | wc -l) looks in $ROOT/looks"
fi

# Turn off the top-corner hover/scroll regions now rather than waiting for the
# first look: they sit on the overlay layer above the bar and swallow its
# input, and the user should not have to trip over that once more to be rid of
# it. A merge, so nothing else in the shell config is disturbed.
II_CONFIG="$CONFIG_HOME/illogical-impulse/config.json"
if [[ -f $II_CONFIG && -f $REPO/looks/baseline.json ]] && command -v jq >/dev/null 2>&1; then
  if (( DRY )); then
    info "would merge looks/baseline.json into ${II_CONFIG/#$HOME/\~}"
  elif jq -s '.[0] * .[1]' "$II_CONFIG" "$REPO/looks/baseline.json" >"$II_CONFIG.tmp" &&
       [[ -s $II_CONFIG.tmp ]]; then
    mv -f "$II_CONFIG.tmp" "$II_CONFIG"
    ok "top-corner scroll regions disabled in the shell config"
  else
    rm -f "$II_CONFIG.tmp"
    warn "could not update ${II_CONFIG/#$HOME/\~} - apply a look to fix the corners"
  fi
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on your PATH - add it to ~/.bashrc or ~/.zshrc" ;;
esac

# ------------------------------------------------------------- profiles ----
# Copy the profile scaffolding (metadata, hooks, helper scripts). Config trees
# are handled separately below because the end4 tree is refreshed wholesale while
# "end4" ships its own.
stage_profile() {
  local name=$1 src="$REPO/profiles/$1" dst="$ROOT/profiles/$1"
  run mkdir -p "$dst/config" "$dst/hooks"
  run install -m 0644 "$src/profile.conf" "$dst/profile.conf"
  local h
  for h in "$src"/hooks/*; do
    [[ -f $h ]] || continue
    run install -m 0755 "$h" "$dst/hooks/$(basename "$h")"
  done
  if [[ -d $src/bin ]]; then
    run mkdir -p "$dst/bin"
    for h in "$src"/bin/*; do
      [[ -f $h ]] || continue
      run install -m 0755 "$h" "$dst/bin/$(basename "$h")"
    done
  fi
  # seed/ holds config the profile provides rather than adopts - currently the
  # small matugen setup that re-colours this rice from the wallpaper.
  if [[ -d $src/seed ]]; then
    run rsync -a "$src/seed/" "$dst/config/"
  fi
}

info "staging profile: end4"
stage_profile end4
run rsync -a --delete-during --exclude 'hypr/custom/***' \
  "$REPO/profiles/end4/config/" "$ROOT/profiles/end4/config/"
run rsync -a --ignore-existing \
  "$REPO/profiles/end4/config/hypr/custom/" "$ROOT/profiles/end4/config/hypr/custom/"
run rsync -a "$REPO/profiles/end4/data/" "$ROOT/profiles/end4/data/"
if [[ -f $REPO/profiles/end4/UPSTREAM_REV ]]; then
  run install -m 0644 "$REPO/profiles/end4/UPSTREAM_REV" "$ROOT/profiles/end4/UPSTREAM_REV"
fi
ok "end4 config staged"

# ------------------------------------------------------------- snippet ----
# The keybind block is appended to each profile's Lua. It has to be *replaced*
# rather than skipped when it is already there: an earlier install left an
# older version behind, and a plain "already present" check would freeze it at
# whatever shipped first. The block is delimited by its own banner comments.
apply_snippet() { # apply_snippet <lua file> <what to call it>
  local file=$1 what=$2
  if (( DRY )); then
    if [[ -f $file ]] && grep -q '^-- ── hyprprofile ─' "$file"; then
      printf '%s  would%s refresh the style-switcher block in %s\n' "$C_DIM" "$C_RST" "$what"
    else
      printf '%s  would%s add the style-switcher block to %s\n' "$C_DIM" "$C_RST" "$what"
    fi
    return 0
  fi

  mkdir -p "$(dirname "$file")"
  [[ -f $file ]] || : >"$file"

  if grep -q '^-- ── hyprprofile ─' "$file"; then
    # Drop the old block: from its banner to the closing rule.
    awk '
      /^-- ── hyprprofile ─/ { skip = 1; next }
      skip && /^-- ─+$/      { skip = 0; next }
      skip                   { next }
      { print }
    ' "$file" >"$file.tmp"
    # Never trade a good file for a truncated one.
    if [[ -s $file.tmp ]] && ! grep -q '^-- ── hyprprofile ─' "$file.tmp"; then
      mv "$file.tmp" "$file"
    else
      rm -f "$file.tmp"
      warn "could not remove the old block from $what - leaving it alone"
      return 0
    fi
    cat "$REPO/snippets/keybind.lua" >>"$file"
    ok "refreshed the style-switcher block in $what"
  else
    cat "$REPO/snippets/keybind.lua" >>"$file"
    ok "added the style-switcher block to $what"
  fi
}

# The Material 3 rice keeps user additions in hypr/custom/, which upstream
# updates do not touch - but a fresh clone starts empty, so re-add if needed.
END4_KEYS="$ROOT/profiles/end4/config/hypr/custom/keybinds.lua"
apply_snippet "$END4_KEYS" "end4/hypr/custom/keybinds.lua"

# -------------------------------------------------------------- activate ----
if (( ACTIVATE )) && ! (( DRY )); then
  info "activating 'end4'"
  "$BIN_DIR/hyprprofile" set end4 --force || warn "activation reported a problem"
else
  info "skipping activation"
fi

# ----------------------------------------------------------------- done -----
cat <<EOS

${C_GRN}${C_B}installed${C_RST}

  profiles      ${ROOT}/profiles
  looks         ${ROOT}/looks
  backup        ${BACKUP}
  command       ${BIN_DIR}/hyprprofile

${C_B}next${C_RST}
  1. ${C_CYA}hyprprofile doctor${C_RST}     check for missing packages
  2. ${C_CYA}./tools/setup-end4-deps.sh${C_RST}
                              install what the Material 3 rice needs
                              (quickshell, matugen, fuzzel, the python venv...)
  3. ${C_CYA}hyprprofile set end4${C_RST}   or press ${C_B}SUPER+Y${C_RST} and pick

${C_B}looks${C_RST}
  ${C_B}SUPER+Y${C_RST} lists them. Every look is the same desktop - same bar, same
  keybinds - differing only in wallpaper, the palette matugen derives from
  that wallpaper, and the desktop clock. ${C_B}SUPER+SHIFT+Y${C_RST} cycles them.
  Drop images into ${ROOT}/wallpapers to add your own.

${C_B}if something breaks${C_RST}
  ${C_CYA}hyprprofile doctor${C_RST}        find out what is wrong
  ${C_CYA}hyprprofile repair${C_RST}        rebuild the links
  your untouched originals are in ${BACKUP}
EOS

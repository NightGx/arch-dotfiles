#!/usr/bin/env bash
# Index the wallpapers folder: build the picker thumbnails and work out the
# dot colour for each image.
#
# Run it after dropping new images into wallpapers/ (or into
# ~/.config/hypr-profiles/wallpapers with --root). Existing index.conf entries
# are kept as they are, so a name or colour you edited by hand survives.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$HERE/wallpapers"

usage() {
  cat <<'U'
usage: ./tools/fetch-wallpapers.sh [options]

  --dir <path>   index this folder instead of ./wallpapers
  --root         index the installed folder (~/.config/hypr-profiles/wallpapers)
  --force        rebuild thumbnails and colours for every image
  -h, --help     this message
U
}

FORCE=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --dir)   DIR=$2; shift ;;
    --root)  DIR="${HYPRPROFILE_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr-profiles}/wallpapers" ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

say()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merr \033[0m %s\n' "$*" >&2; exit 1; }

[[ -d $DIR ]] || die "no such folder: $DIR"

# Thumbnails, dot colours and video frame extraction all live in the library
# the switcher also uses, so `fetch-wallpapers.sh` and `hyprprofile look new`
# can never disagree about what a wallpaper's colour is.
# shellcheck disable=SC1091
source "$HERE/lib/ingest.sh"
ing_have || die "needs ImageMagick or python-pillow (sudo pacman -S imagemagick)"

accent_of() { ing_accent "$1"; }
thumb_of()  { ing_thumb "$1" "$2"; }

INDEX="$DIR/index.conf"
THUMBS="$DIR/thumbs"
mkdir -p "$THUMBS"

pretty() { ing_pretty "$1"; }

# Keep the header and every entry whose file is still there.
declare -A HAVE=()
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
if [[ -f $INDEX ]]; then
  while IFS= read -r line; do
    if [[ -z $line || ${line:0:1} == '#' ]]; then printf '%s\n' "$line" >>"$tmp"; continue; fi
    file=${line%%|*}
    if [[ -f $DIR/$file ]]; then
      HAVE[$file]=1
      printf '%s\n' "$line" >>"$tmp"
    else
      warn "dropping $file - no longer in the folder"
    fi
  done <"$INDEX"
else
  {
    printf '# <file>|<display name>|<accent colour for the picker dot>\n'
    printf '# Managed by tools/fetch-wallpapers.sh; add your own images below.\n'
  } >>"$tmp"
fi

added=0 thumbed=0
shopt -s nullglob nocaseglob
for f in "$DIR"/*.{jpg,jpeg,png,webp,bmp}; do
  [[ -f $f ]] || continue
  base=${f##*/}
  slug=${base%.*}

  if [[ $FORCE == 1 || ! -f $THUMBS/$slug.png ]]; then
    thumb_of "$f" "$THUMBS/$slug.png"
    thumbed=$(( thumbed + 1 ))
  fi

  if [[ -z ${HAVE[$base]:-} ]]; then
    colour=$(accent_of "$f"); colour=${colour:-#8ab4f8}
    printf '%s|%s|%s\n' "$base" "$(pretty "$slug")" "$colour" >>"$tmp"
    added=$(( added + 1 ))
    say "indexed $base  $(pretty "$slug")  $colour"
  elif (( FORCE )); then
    # Refresh the colour, keep whatever name is in the file - it may have been
    # edited by hand, and the derived one is only ever a first guess.
    colour=$(accent_of "$f"); colour=${colour:-#8ab4f8}
    awk -v file="$base" -v col="$colour" -F'|' '
      $1 == file { printf "%s|%s|%s\n", $1, $2, col; next } { print }' "$tmp" >"$tmp.new"
    mv "$tmp.new" "$tmp"
    say "recoloured $base -> $colour"
  fi
done
shopt -u nullglob nocaseglob

# Drop thumbnails whose image is gone.
for t in "$THUMBS"/*.png; do
  [[ -f $t ]] || continue
  s=${t##*/}; s=${s%.png}
  found=0
  for e in "$DIR/$s".{jpg,jpeg,png,webp,bmp}; do [[ -f $e ]] && { found=1; break; }; done
  (( found )) || { rm -f "$t"; warn "removed stale thumbnail $s.png"; }
done

mv "$tmp" "$INDEX"; trap - EXIT
say "$added new, $thumbed thumbnail(s) built -> $INDEX"
say "the picker reads this folder directly; nothing else to do"

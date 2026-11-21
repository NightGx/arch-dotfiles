#!/usr/bin/env bash
# Populate profiles/end4/config from upstream end-4/dots-hyprland.
#
# Only the config files are taken. Package installation is a separate step
# (tools/setup-end4-deps.sh) because it needs pacman and an Arch host.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO_DIR/profiles/end4/config"
DATA_DEST="$REPO_DIR/profiles/end4/data"
CACHE="${END4_CACHE:-$REPO_DIR/.cache/dots-hyprland}"
UPSTREAM="https://github.com/end-4/dots-hyprland.git"
REF="${END4_REF:-main}"

say() { printf '==> %s\n' "$*" >&2; }

if [[ -d $CACHE/.git ]]; then
  say "updating $CACHE"
  git -C "$CACHE" fetch --depth 1 origin "$REF"
  git -C "$CACHE" checkout -q FETCH_HEAD
else
  say "cloning $UPSTREAM ($REF)"
  mkdir -p "$(dirname "$CACHE")"
  git clone --depth 1 --branch "$REF" "$UPSTREAM" "$CACHE"
fi

# The bar pulls in a rounded-polygon QML library as a submodule; without it
# Quickshell fails to load half the widgets.
say "fetching submodules"
git -C "$CACHE" submodule update --init --recursive --depth 1

say "staging config into $DEST"
mkdir -p "$DEST" "$DATA_DEST"

# Everything under dots/.config, flattened one level: each entry becomes a
# path the end4 profile owns.
#
# hypr/custom is upstream's designated "your edits go here" directory and is
# also where the style-switcher keybind lives, so it is held back from the
# delete pass and only gap-filled.
rsync -a --delete-during --exclude '.git' --exclude '.gitmodules' \
  --exclude 'hypr/custom/***' \
  "$CACHE/dots/.config/" "$DEST/"

rsync -a --ignore-existing \
  "$CACHE/dots/.config/hypr/custom/" "$DEST/hypr/custom/"

rsync -a --delete-during "$CACHE/dots/.local/share/konsole/" "$DATA_DEST/konsole/"
mkdir -p "$DATA_DEST/icons"
cp -f "$CACHE/dots/.local/share/icons/illogical-impulse.svg" "$DATA_DEST/icons/" 2>/dev/null || true

# kxmlgui5 ships in the repo but may be absent on some refs.
if [[ -d $CACHE/dots/.local/share/kxmlgui5 ]]; then
  rsync -a --delete-during "$CACHE/dots/.local/share/kxmlgui5/" "$DATA_DEST/kxmlgui5/"
fi

printf '%s\n' "$(git -C "$CACHE" rev-parse HEAD)" > "$REPO_DIR/profiles/end4/UPSTREAM_REV"

say "done: $(du -sh "$DEST" | cut -f1) staged, upstream $(cut -c1-8 < "$REPO_DIR/profiles/end4/UPSTREAM_REV")"

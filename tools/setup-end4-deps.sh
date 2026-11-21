#!/usr/bin/env bash
# Install what the Material 3 profile needs: packages, the python venv
# Quickshell's config runs on, and the group/service setup.
#
# This runs upstream's own installer, restricted to the two steps that do not
# touch config files - `install-deps` and `install-setups`. The config files
# are already staged in the end4 profile, and letting upstream copy them would
# overwrite ~/.config directly, which is exactly what the profile system is
# there to prevent.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${END4_CACHE:-$REPO/.cache/dots-hyprland}"

say()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn\033[0m %s\n' "$*"; }
die()  { printf '\033[31merr \033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "run this as your normal user - it calls sudo itself"
command -v pacman >/dev/null 2>&1 || die "this needs Arch (pacman not found)"
[[ -d $CACHE ]] || die "upstream not fetched yet - run ./tools/fetch-end4.sh first"

cat <<'NOTE'

This runs end-4's own dependency installer. It will:

  - install packages with pacman and an AUR helper (quickshell-git, matugen,
    fuzzel, hypridle, cliphist, easyeffects, fonts, Kvantum themes, ...)
  - build a python venv at ~/.local/state/quickshell/.venv
  - add you to the video, i2c and input groups
  - enable the ydotool and bluetooth services
  - load the i2c-dev kernel module at boot
  - install mpvpaper and ffmpeg, so a video can be used as a wallpaper

It does NOT copy any config files - those are already staged in the end4
profile, and hyprprofile links them in when you switch.

NOTE

read -rp "continue? [y/N] " reply
[[ $reply =~ ^[yY]$ ]] || { say "cancelled"; exit 0; }

cd "$CACHE"

say "installing dependencies"
./setup install-deps

say "running setup steps (venv, groups, services)"
./setup install-setups

# Not among end-4's own dependencies, but switchwall.sh reaches for both the
# moment a wallpaper is a video: mpvpaper draws it, and ffmpeg pulls the frame
# the palette and the picker thumbnail are made from. Without them a video
# wallpaper fails quietly.
want=()
command -v mpvpaper >/dev/null 2>&1 || want+=(mpvpaper)
command -v ffmpeg   >/dev/null 2>&1 || want+=(ffmpeg)
if (( ${#want[@]} )); then
  say "installing ${want[*]} (for animated wallpapers)"
  sudo pacman -S --needed --noconfirm "${want[@]}" ||
    warn "could not install ${want[*]} - video wallpapers will not work until you do"
fi

say "done"
cat <<'NEXT'

Two things need a fresh login to take effect: the group membership
(video/i2c/input) and the i2c-dev module. Everything else is live now.

  hyprprofile doctor      confirm nothing is missing
  hyprprofile set end4    switch

NEXT

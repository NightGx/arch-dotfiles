# tests/fixtures

A snapshot of the Arch `~/.config` layout, just complete enough to run
`tests/test-install.sh` anywhere - including on a machine where the Arch
partition is not mounted.

`hypr/hyprland.lua` is the real pre-install config, kept verbatim because the
install rewrites it (the wallpaper autostart, the inert trailing block, the
keybind append) and the tests assert on those rewrites. Everything else is a
stand-in: only its presence and path matter.

Override with `SEED_CONFIG=/path/to/.config tests/test-install.sh` to run
against a real config instead.

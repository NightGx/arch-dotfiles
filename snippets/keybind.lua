
-- ── hyprprofile ──────────────────────────────────────────────────────────
-- Live look switcher.
--   SUPER+Y        pick a look
--   SUPER+SHIFT+Y  cycle to the next look
--   SUPER+ALT+Y    cycle to the next wallpaper, keeping the current clock
-- No combination on Y is bound by the rice itself.
local hyprprofile = os.getenv("HOME") .. "/.local/bin/hyprprofile"
hl.bind("SUPER + Y",         hl.dsp.exec_cmd(hyprprofile .. " menu"),
        { description = "Pick a look" })
hl.bind("SUPER + SHIFT + Y", hl.dsp.exec_cmd(hyprprofile .. " look next"),
        { description = "Next look" })
hl.bind("SUPER + ALT + Y",   hl.dsp.exec_cmd(hyprprofile .. " wallpaper next"),
        { description = "Next wallpaper" })

-- The picker is drawn translucent, which only looks right with something
-- blurred behind it. "launcher" is fuzzel's namespace (already handled by the
-- Material 3 rice, harmless to repeat); "rofi" is rofi's.
hl.layer_rule({ match = { namespace = "rofi" },     blur = true })
hl.layer_rule({ match = { namespace = "rofi" },     ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "launcher" }, blur = true })
hl.layer_rule({ match = { namespace = "launcher" }, ignore_alpha = 0.5 })

-- Colours matugen derives from the current wallpaper. Regenerated on every
-- wallpaper change and re-read by `hyprctl reload`; absent until the first
-- wallpaper is picked, and absent entirely in rices that theme themselves.
local hyprprofile_colors = os.getenv("HOME") .. "/.config/hypr/hyprprofile-colors.lua"
local _f = io.open(hyprprofile_colors, "r")
if _f then
    _f:close()
    dofile(hyprprofile_colors)
end
-- ─────────────────────────────────────────────────────────────────────────

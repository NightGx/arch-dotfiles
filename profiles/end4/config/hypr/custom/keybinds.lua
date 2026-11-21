hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- ── hyprprofile ──────────────────────────────────────────────────────────
-- Live style switcher. SUPER+Y opens the picker; SUPER+SHIFT+Y cycles.
-- Both combos are free in this rice and in the other one, so the binding
-- means the same thing whichever style is active.
local hyprprofile = os.getenv("HOME") .. "/.local/bin/hyprprofile"
hl.bind("SUPER + Y",         hl.dsp.exec_cmd(hyprprofile .. " menu"),
        { description = "Pick desktop style" })
hl.bind("SUPER + SHIFT + Y", hl.dsp.exec_cmd(hyprprofile .. " next"),
        { description = "Next desktop style" })
-- ─────────────────────────────────────────────────────────────────────────

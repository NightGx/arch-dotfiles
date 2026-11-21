-- Monitor layout.
--
-- These override the catch-all `output = ""` / `mode = "preferred"` rule in
-- hyprland/general.lua, which is what leaves each screen on whatever its EDID
-- claims it can do. On the right-hand panel that claim is wrong.

-- DP-2 - Samsung Odyssey G5 (LS27CG552EU), right-hand screen.
-- Its EDID advertises 2560x1440@165 and the link will not hold it: it trains,
-- drops, retrains, and the screen blinks on and off without stopping. 144 was
-- tested by hand with `hyprctl eval` and is stable, so it is pinned here.
-- If the link ever gets fixed - a better DP cable, or "DisplayPort Ver." set
-- to 1.4 in the monitor's own OSD - put 165.00 back and see.
hl.monitor({ output = "DP-2", mode = "2560x1440@144.00", position = "2560x0", scale = 1 })

-- DP-1 - Samsung Odyssey G7 (LC27G7xT), left-hand screen. 240 Hz is real on
-- this panel and has been running without trouble.
hl.monitor({ output = "DP-1", mode = "2560x1440@240.00", position = "0x0",    scale = 1 })

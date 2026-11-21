# Notes on the existing config

Things found while reading `~/.config/hypr/hyprland.lua` on the Arch install.
None of these are changed by the installer except where stated — the point of
the profile system is that your rice keeps looking exactly like it does now.

## The last 20 lines of hyprland.lua are inert

The file ends with what looks like hyprlang pasted into a Lua file:

```lua
decoration = {
    rounding = 18,
    blur = { enabled = true, size = 14, passes = 4, ... },
    shadow = { enabled = true, range = 18, render_power = 3 },
}

env = QT_QPA_PLATFORMTHEME,qt6ct
env = QT_QPA_PLATFORMTHEME_QT5,qt5ct

animations = { enabled = true }
```

These are valid Lua, which is why nothing errors — but they assign plain
global variables. Hyprland takes configuration through `hl.config({...})` and
environment through `hl.env(...)`, so none of it reaches the compositor.

Two consequences:

- **Your decoration settings are not the ones you think.** The values actually
  in effect are the earlier `hl.config({ decoration = ... })` call: `rounding
  = 10`, `blur.size = 3`, `blur.passes = 1` — not 18 / 14 / 4. Check with
  `hyprctl getoption decoration:rounding`.
- **`QT_QPA_PLATFORMTHEME` is never set.** `QT_QPA_PLATFORMTHEME` and `qt6ct`
  are undefined globals, so that line evaluates to `env = nil`. You have qt6ct
  configured (Fusion, darker palette) but Qt apps are not being told to use
  it. Check with `hyprctl getoption` / `printenv QT_QPA_PLATFORMTHEME` inside
  the session.

**This is fixed by the installer** (`tools/fix-inert-config.sh`), at your
request. The transform wraps the existing blocks rather than retyping them, so
the values that end up applied are exactly the ones already written:

```lua
hl.config({
    decoration = {
        rounding = 18,
        blur   = { enabled = true, size = 14, passes = 4,
                   ignore_opacity = true, new_optimizations = true },
        shadow = { enabled = true, range = 18, render_power = 3 },
    },
})

hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_QPA_PLATFORMTHEME_QT5", "qt5ct")
```

**So your desktop will look different after installing**: rounder corners
(10 → 18), much heavier blur (size 3/1 pass → 14/4 passes) and deeper shadows.
That is a real GPU cost on two 1440p screens — if you don't like it, the
pre-transform file is kept next to it:

```sh
cd ~/.config/hypr-profiles/profiles/mine/config/hypr
cp hyprland.lua.pre-hyprprofile hyprland.lua
hyprctl reload
```

`hl.env` only affects processes started afterwards, so Qt apps already open
need a restart before they pick up qt6ct.

## The wallpaper script re-ran on every reload — this one *is* changed

```lua
hl.exec_cmd("/home/night/scriptPerso/wallpaperScript.sh")
```

At top level rather than inside `hl.on("hyprland.start", ...)`, this fires on
every `hyprctl reload`, and the script ends in `exec linux-wallpaperengine`,
so each reload left another copy running. That was survivable when reloads
were rare; the switcher reloads on every switch, so it would have stacked up
fast.

The installer comments this line out and the `mine` profile's start hook calls
`profiles/mine/bin/wallpaper.sh` instead — same command line and the same two
wallpaper IDs on DP-1/DP-2, but it kills any instance already running first.
Your original `~/scriptPerso/wallpaperScript.sh` is untouched.

If you had duplicates piling up before, `pkill linux-wallpaperengine` once
after installing clears them.

## Settings that live outside any config directory

Three things end-4's installer sets are global session state, not files in
`~/.config`, so the symlink swap cannot carry them:

- `gsettings … interface font-name` and `color-scheme` (dconf)
- `kwriteconfig6 … widgetStyle Darkly` (kdeglobals — actually profiled, but
  the write happens at install time)

Both profiles' start hooks set these explicitly so they follow the switch:
`end4` applies Google Sans Flex + Darkly, `mine` resets the font and keeps
`prefer-dark`.

## Package overlap

Your Arch install has none of the Material 3 rice's dependencies yet — no
`quickshell`, `matugen`, `fuzzel`, `hypridle`, `cliphist`, or `easyeffects`.
`tools/setup-end4-deps.sh` installs them via upstream's own package lists.
Nothing there conflicts with what the Clean profile uses (`rofi`, `kitty`,
`dolphin`, `linux-wallpaperengine`), so both rices work after one dep install.

---

# Bugs found in the switcher itself

Written down after the first live run on Arch, where the picker opened but
choosing anything did nothing. Each has a regression test in `tests/`.

## The switch lock leaked into every daemon a hook started

**This was the one that made the menu look broken.**

`cmd_set` takes an exclusive `flock` on file descriptor 9 so two switches
cannot interleave. A start hook then launches the rice's components —
`linux-wallpaperengine` for the Clean profile, `qs -c ii` for Material 3 —
detached, so they outlive the hook. Detached or not, they inherit fd 9.

`linux-wallpaperengine` runs for as long as your session does. So after the
very first switch, the lock was held forever by the wallpaper process, and
every subsequent `hyprprofile set` hit:

```
err  another switch is in progress
```

…and exited. From a keybind, stderr goes nowhere. The picker opened, you chose
the other style, and nothing whatsoever happened.

Fixed in three places: `run_hook` closes fd 9 before exec'ing the hook,
`spawn`/`spawn_sh` close it on the processes they detach, and the lock now
waits 8 seconds rather than failing instantly, so double-tapping the keybind
queues instead of erroring. Test: *"a hook that leaves a daemon behind does not
wedge the next switch"* in `test-switch.sh`.

## Failures were invisible

Every error path was `printf … >&2`. The picker is launched from a keybind, so
there is no terminal attached and every one of those messages went to
`/dev/null`. Any failure — a missing dependency, a bad config, the lock above —
was indistinguishable from a working switcher that had decided to do nothing.

`die()` and `warn()` now raise a desktop notification when stdout is not a
terminal. A separate `note()` was added for the genuinely uninteresting
messages ("profile declares `Trolltech.conf` but has no such file"), because a
switch that fires four toasts about files you never had is worse than silence.

## Selection was matched back by display string

The picker rendered rows like `●  Material 3` and then matched the launcher's
answer against that exact string to work out which profile you meant. Several
launchers trim leading whitespace, and any that re-render the row break the
match outright — at which point the switch silently did nothing.

Rows are now identified by **index**: `rofi -format i`, `fuzzel --index`. For
launchers with no index mode (wofi, tofi, dmenu) there is a normalising
fallback that strips the dot and collapses whitespace before comparing.

## Nothing stopped you entering a rice that was not installed

`hyprprofile set end4` would happily swap every config path over to a rice
whose Quickshell, matugen and fuzzel were not installed yet, leaving a desktop
with no bar, no launcher, and no obvious way back.

`cmd_set` now refuses when a profile's `REQUIRES` are missing, names them, and
tells you how to install them. `--force` still overrides. The picker marks such
styles `(needs …)` rather than hiding them.

## A config Hyprland rejected left you stranded

When `hyprctl reload` cannot parse the new config, Hyprland keeps running the
old one. The switcher treated that as success: the files had been swapped, so
you were "on" a profile whose config had never loaded.

After every reload the switcher now reads `hyprctl configerrors`, and rolls
back to the previous profile if there are any — with a notification saying so.
`doctor` reports live config errors too.

## `pgrep -f` matched far too much

`stop_match` and `spawn_once` matched on the whole command line of every
process owned by you. An editor open on `hypridle.conf`, or a terminal running
`qs -c ii ipc call …`, matched the pattern — so `stop_match` would kill it, and
`spawn_once` would decide the component was already running and never start it.

Both now exclude the switcher's own process tree, which is where the false
matches actually came from.

## A theme rofi cannot parse swallowed the whole menu

A syntax error in a `.rasi` makes rofi exit having drawn nothing. Now the
switcher notices, says so, and re-opens the menu with rofi's own theme instead
of leaving you with a keybind that appears dead.

## Picking a wallpaper was undone by the next style switch

The Clean profile's start hook restarted `linux-wallpaperengine`
unconditionally, so switching to Material 3 and back put the animated
backgrounds over whatever static wallpaper you had chosen. The hook now reads
`state/wallpaper` and restores whichever kind you last picked.

## Smaller ones

- `load_profile` did not reset `PICKER` / `ACCENT` between profiles, so one
  profile's value could leak into the next.
- `publish_state` could be called with no active profile and died instead of
  doing nothing.
- The `--force` path of the wallpaper indexer built a `sed` expression with
  unbalanced delimiters; it is an `awk` rewrite now.
- `run_hook`'s `(( waited++ ))` returns 1 the first time round, which is only
  harmless because the script does not use `set -e`. Written as
  `waited=$(( waited + 1 ))` so it stays harmless if that ever changes.

## Looks: one rice, several appearances

The first version of the switcher answered the wrong question. It swapped
whole rices, when what was wanted was one rice with several appearances —
same bar, same keybinds, same launcher, differing only in wallpaper, the
palette derived from it, and the desktop clock.

That turns out to be a much cheaper operation than a profile switch, and the
implementation reflects it. A look is applied by:

1. switching to `end4` first, if another rice is up;
2. handing the image and the look's matugen scheme to end-4's own
   `switchwall.sh`;
3. merging a small JSON patch into `~/.config/illogical-impulse/config.json`.

No symlink farm, no `hyprctl reload`, no restarting the shell — Quickshell
watches that config file and re-reads it.

### Why the whole clock block, every time

`patch.json` merges rather than replaces, which is what protects the user's
own settings in that file. But it means a key one look sets and the next one
omits would *linger*. Sakura turns `constantlyRotate` on; if Dawn did not
explicitly turn it back off, Dawn-after-Sakura would look different from
Dawn-after-Dunes. So every look writes the complete `background.widgets.clock`
object. `test-looks.sh` asserts that for all nine, and separately asserts that
switching Sakura → Dawn clears the rotation.

### aiStyling would have silently undone every look

`CookieClock.qml` has `setClockPreset(category)`, which rewrites six clock
properties whenever the wallpaper changes — but only when
`background.widgets.clock.cookie.aiStyling` is true. It is false by default,
and if it were ever switched on it would quietly override whatever clock a
look had just set, on the very same operation. Every look therefore pins it to
false, and there is a test for that.

### The shell writes to the file we write to

`Config.qml` uses a `FileView` with `watchChanges: true` and, on
`onAdapterUpdated`, writes its in-memory copy *back* to disk. A write that
lands inside that window can be echoed over. Rather than reason about the
timing, `ii_apply_verified` merges, reads the clock style back, and retries up
to three times before reporting failure — because a look that silently did not
apply is exactly the class of bug that made the first version look broken.

The write itself uses temp-file-plus-rename, which is what `switchwall.sh`
already does to the same file, so Quickshell's watcher reacts to it the same
way.

## Bugs found while building the looks layer

**The divider could hang the menu.** Picking the `──  other setups  ──` row
re-opens the picker so a mis-click is not a dead end. With a launcher that
keeps returning the same row, that recursed forever. Found by the test suite
hanging, not by inspection. Now capped at four re-entries.

**An unquoted Pango attribute.** The profile rows were built with
`<span alpha="45%">` inside a double-quoted shell string, so the shell ate the
inner quotes and Pango received `<span alpha=45%>` — strict enough to drop the
whole row's markup. Now built with `printf`, and `test-menu.sh` asserts the
attribute is quoted.

## The top-corner input strips

`sidebar.cornerOpen` places a 250 × 5 px region in each top corner at
`WlrLayer.Overlay`, above the bar: hover opens a sidebar, scroll changes
brightness (left) or volume (right). It overlays a quarter of the bar's width
on each side and takes its input.

Turned off in `looks/baseline.json`, applied at install, on every switch into
`end4`, and by every look. The other `cornerOpen` keys are left alone. The
sidebars remain reachable from the bar's end buttons and from SUPER+A / SUPER+N,
which is where `hyprland/keybinds.lua` already binds them.

### The lock leak had a second home

`cmd_set` takes the switch lock on fd 9 and, on the success path, never gave
it back — harmless for a one-shot CLI, which drops it on exit.

`look` broke that assumption. Applying a look from the other rice switches
profiles *first* and then keeps working: it runs the wallpaper backend, and
`switchwall.sh` leaves helpers running behind it (matugen's KDE wrapper, the
terminal-scheme writer, the upscale prompt). Each of those inherits fd 9 and
holds the switch lock for the rest of the session — the same failure that made
the first version trap the user in one rice, in a new place.

Fixed at both ends: `cmd_set` calls `unlock` (`flock -u 9; exec 9>&-`) on every
path that returns, and `wp_apply` runs the profile's backend with `9>&-`.
`test-looks.sh` covers it, and the test was checked against a deliberately
un-fixed copy of the tree, where it reproduces the original symptom exactly:
*"another switch is still running"*.

## The scroll hints were the "top right and left" thing

The first attempt at this fixed the wrong overlay. `sidebar.cornerOpen` was a
real problem and is still worth having off, but it is invisible — and the
report was of something *visible* at the very top-left and top-right.

That is `ScrollHint.qml`: hovering either half of the bar reveals a column of
**↑ / icon / ↓** at the very edge, `light_mode` on the left and `volume_up` on
the right, drawn over the bar's own content. Brightness left, sound right —
exactly as described. There is no upstream setting for it, so
`tools/patch-quickshell-scrollhints.sh` adds `bar.scrollHints` to `Config.qml`
and gates the `Revealer` on it. Scroll-to-change still works; only the overlay
is hidden.

Lesson: "at the very top right and left" was a precise description of where
the thing was drawn, and the invisible corner regions matched the location but
not the word *visible*. Match every part of a report, not the part that fits
the first candidate found.

## The blinking monitor, and what the doctor got wrong

The right-hand screen — `DP-2` at `2560x0`, a Samsung Odyssey G5 LS27CG552EU —
kept cutting out and coming back. That symptom has one shape: the GPU drives a
mode the sink cannot lock onto, the link trains, fails, drops and retrains,
forever.

The mode it could not hold was its own advertised native one. `2560x1440@165`
blinks; `2560x1440@144` is stable. Both were checked by hand:

```fish
hyprctl eval 'hl.monitor({ output = "DP-2", mode = "2560x1440@144.00", position = "2560x0", scale = 1 })'
```

On Hyprland 0.55+ `hyprctl keyword` answers *"keyword can't work with
non-legacy parsers"* — `eval` is the runtime equivalent, and like `keyword` it
is wiped by `hyprctl reload` and by reboot. The fix only sticks in
`hypr/custom/general.lua`, which `hyprland.lua` requires and which `install.sh`
preserves on purpose (`--exclude 'hypr/custom/***'`, then `--ignore-existing`).

### The false positive

The first `monitor-doctor.sh` compared each mode's bandwidth against a static
table of DP 1.2 (17.3 Gbit/s) and HDMI 2.0 (14.4) ceilings, and called anything
above them broken. On the *left* monitor — an Odyssey G7 running a genuine
240 Hz over a DP 1.4 link, 22.5 against a real ceiling of 25.9 — it reported a
fault that did not exist and recommended pinning a healthy panel to 144 Hz.

`hyprctl` does not expose the negotiated link rate, so the script had no way to
know which ceiling applied. Arithmetic against a guessed ceiling can never
prove a mode *fine*; at best it proves one impossible. The rewrite asks three
questions that have answers:

1. **Is the running mode in the monitor's own `availableModes`?** A mode that
   is not advertised is being forced, and forcing is how you get a blink.
2. **What did the link actually negotiate?** amdgpu publishes lane count and
   rate code in `/sys/kernel/debug/dri/*/DP-*/link_settings` — `0x0a` HBR,
   `0x14` HBR2, `0x1e` HBR3. Lanes × rate × 8b/10b is a measured ceiling, not
   a guessed one. It is root-only, so the script asks with `sudo -n` and
   degrades to "not known" rather than inventing a number.
3. **Has Hyprland been losing the output?** `Removed monitor X` / `Monitor X
   added` pairs in `$XDG_RUNTIME_DIR/hypr/*/hyprland.log` *are* the blink,
   written down.

Utilisation is still printed, because 89% of a link is worth knowing, but it is
labelled "not a fault on its own" and it no longer drives the recommendation.
Only the three signals above set the flag that produces a step-down line.

### DDC/CI, the outstanding suspect

The bar's brightness slider drives external monitors over DDC/CI, which rides
the DisplayPort AUX channel (`services/Brightness.qml` shells out to
`ddcutil`). `~/.cache/ddcutil/dsa` records ddcutil's dynamic sleep adjustment
per i2c bus, and on this machine one bus sat at backoff step 10 of 10 — the
maximum — across a hundred transactions in a two-minute session. That is a
monitor answering badly on the same channel the link runs on. The doctor prints
that table now; `pkill -f 'qs -c ii'` takes DDC out of the picture for a minute
if it needs ruling out.

## The Clean profile is gone

Removed at the user's request - it was the source of the monitor rule above,
and the looks layer made a second whole rice redundant. `install.sh` no longer
adopts the live `~/.config` into a profile; it stages `end4`, and the switcher's
own `rescue` moves anything already at a managed path into `backups/<stamp>/`.
Paths the rice does not claim are simply left alone.

Gone with it: the `@wallpaperengine` entry, the Wallpaper Engine relaunch in
the start hook, mine's matugen seed and the gtk/kitty `@import`/`include`
wiring that fed it. `SUPER+ALT+Y` now cycles wallpapers instead of switching
rices.

## Authoring looks, and animated wallpapers

`hyprprofile look new <file>` makes a look out of anything: it copies the file
in, builds the picker thumbnail, derives the dot colour from the picture,
borrows a clock from an existing look and appends it to the menu.

**The clock is borrowed, not invented.** A clock style is a dozen interlocking
settings, and every look has to write the complete block (see above), so
asking the user for twelve values would be a bad interface *and* an easy way
to produce an incomplete patch. `--clock <look-id>` copies a patch that is
known to be whole.

**Videos are stills with an extra step.** `lib/ingest.sh` resolves anything to
a frame first — ffmpeg, three seconds in, falling back to the first frame for
short clips — and everything downstream (thumbnail, dot colour) runs on that.
So an animated wallpaper is themed from what it actually looks like. mpvpaper
draws it; end-4's `switchwall.sh` already had that path and writes a restore
script so it survives a reload.

The two dependencies fail differently on purpose: without **ffmpeg** the
command refuses, because a look with no thumbnail and no palette is worse than
no look; without **mpvpaper** it warns and proceeds, because everything except
playback still works and the package can be installed later.

### Two bash traps this hit

`local ext=${src##*.} dest="$WALLPAPER_DIR/$id.${ext,,}"` — a single `local`
with two assignments. The second is expanded *before* the first takes effect,
so `ext` was unset; under `set -u` that aborted the command. Split into two
statements.

`bash -c '"$HP" look list | grep -q x'` in the test suite — `$HP` is not
exported, so inside `bash -c` it expanded to nothing and the assertion failed
for a reason that had nothing to do with the code under test. Use the value,
not a subshell that cannot see it.

### One shared implementation

`tools/fetch-wallpapers.sh` had its own copies of the thumbnail and dot-colour
routines. Now both it and `hyprprofile look new` source `lib/ingest.sh`, so
they cannot disagree about what a wallpaper's colour is. The move was checked
by running the original algorithm inline against the library's on the same
image: both give `#c46562`.

#!/usr/bin/env bash
# Exercises hyprprofile's link/unlink/flip logic against a throwaway HOME.
set -uo pipefail
HP="$(cd "$(dirname "$0")/.." && pwd)/bin/hyprprofile"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export HYPRPROFILE_ROOT="$XDG_CONFIG_HOME/hypr-profiles"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

# doctor checks that a launcher exists, so give it one. Nothing is ever run
# through it here; the picker itself is covered by test-menu.sh.
STUB="$T/bin"; mkdir -p "$STUB"
printf '#!/bin/sh\nexit 0\n' > "$STUB/fuzzel"; chmod +x "$STUB/fuzzel"
# Start hooks only run when a compositor is up, so stand one in - otherwise
# the half of the switch that launches a rice's components is never exercised.
cat > "$STUB/hyprctl" <<'EOF'
#!/bin/sh
case "$1" in
  version)      echo "Hyprland 0.56.2 built from branch";;
  configerrors) echo "no errors";;
esac
exit 0
EOF
chmod +x "$STUB/hyprctl"
export PATH="$STUB:$PATH"
export HYPRPROFILE_HOOK_TIMEOUT=3

pass=0; fail=0
check() { # check <desc> <cond...>
  local d=$1; shift
  if "$@"; then printf '  PASS %s\n' "$d"; ((pass++))
  else printf '  FAIL %s\n' "$d"; ((fail++)); fi
}
check_eq() { # check_eq <desc> <expected> <actual>
  if [[ $2 == "$3" ]]; then printf '  PASS %s\n' "$1"; ((pass++))
  else printf '  FAIL %s (expected %q, got %q)\n' "$1" "$2" "$3"; ((fail++)); fi
}

mkprofile() { # mkprofile <name> <entrypoint-ext> <paths...>
  local n=$1 ext=$2; shift 2
  local d="$HYPRPROFILE_ROOT/profiles/$n"
  mkdir -p "$d/config/hypr" "$d/hooks"
  echo "-- $n" > "$d/config/hypr/hyprland.$ext"
  local p
  for p in "$@"; do mkdir -p "$d/config/$p"; echo "$n" > "$d/config/$p/marker"; done
  {
    echo "DISPLAY_NAME=\"$n rice\""
    echo "DESCRIPTION=\"test profile $n\""
    echo "CONFIG_PATHS=(hypr $*)"
    echo "REQUIRES=(bash)"
  } > "$d/profile.conf"
}

echo "== setup =="
mkprofile alpha lua rofi kitty
mkprofile beta  lua quickshell kitty

echo "== initial switch to alpha =="
"$HP" set alpha >/dev/null 2>&1
check_eq "active is alpha" "alpha" "$("$HP" current)"
check "~/.config/hypr is a symlink" test -L "$XDG_CONFIG_HOME/hypr"
check_eq "hypr resolves into alpha" "alpha" "$(cat "$XDG_CONFIG_HOME/hypr/../rofi/marker" 2>/dev/null)"
check "alpha-only dir rofi linked" test -L "$XDG_CONFIG_HOME/rofi"
check "beta-only dir quickshell absent" test ! -e "$XDG_CONFIG_HOME/quickshell"
check_eq "shared dir kitty shows alpha" "alpha" "$(cat "$XDG_CONFIG_HOME/kitty/marker")"

echo "== switch to beta =="
"$HP" set beta >/dev/null 2>&1
check_eq "active is beta" "beta" "$("$HP" current)"
check "alpha-only dir rofi removed" test ! -e "$XDG_CONFIG_HOME/rofi"
check "beta-only dir quickshell linked" test -L "$XDG_CONFIG_HOME/quickshell"
check_eq "shared dir kitty now shows beta" "beta" "$(cat "$XDG_CONFIG_HOME/kitty/marker")"
check_eq "hyprland entrypoint follows" "-- beta" "$(cat "$XDG_CONFIG_HOME/hypr/hyprland.lua")"

echo "== back =="
"$HP" back >/dev/null 2>&1
check_eq "back returns to alpha" "alpha" "$("$HP" current)"
check_eq "kitty shows alpha again" "alpha" "$(cat "$XDG_CONFIG_HOME/kitty/marker")"

echo "== next cycles =="
"$HP" next >/dev/null 2>&1
check_eq "next moves to beta" "beta" "$("$HP" current)"
"$HP" next >/dev/null 2>&1
check_eq "next wraps to alpha" "alpha" "$("$HP" current)"

echo "== pre-existing real dir is rescued, not destroyed =="
rm -f "$XDG_CONFIG_HOME/quickshell"
mkdir -p "$XDG_CONFIG_HOME/quickshell"
echo "precious" > "$XDG_CONFIG_HOME/quickshell/user-data"
"$HP" set beta >/dev/null 2>&1
check "quickshell is now our link" test -L "$XDG_CONFIG_HOME/quickshell"
check_eq "user data was backed up" "precious" \
  "$(cat "$HYPRPROFILE_ROOT"/backups/*/.config/quickshell/user-data 2>/dev/null)"

echo "== idempotence =="
"$HP" set beta >/dev/null 2>&1
check_eq "re-setting same profile is a no-op" "beta" "$("$HP" current)"
"$HP" set beta --force >/dev/null 2>&1
check_eq "--force re-applies cleanly" "beta" "$("$HP" current)"
check "kitty link still valid after force" test -f "$XDG_CONFIG_HOME/kitty/marker"

echo "== a hook that leaves a daemon behind does not wedge the next switch =="
# The switch holds a flock. Anything a start hook detaches inherits that fd
# unless it is closed, and then holds the lock for as long as it lives - which
# for a wallpaper daemon or a shell is forever. Every later switch is then
# refused, silently, and the picker looks broken.
mkdir -p "$HYPRPROFILE_ROOT/lib"
cp "$(dirname "$HP")/../lib/hooklib.sh" "$HYPRPROFILE_ROOT/lib/hooklib.sh"
cat > "$HYPRPROFILE_ROOT/profiles/alpha/hooks/start" <<'EOF'
#!/usr/bin/env bash
source "$HYPRPROFILE_ROOT/lib/hooklib.sh"
# Stands in for a wallpaper daemon or a shell: detached, and outliving the
# hook that started it. It records its pid so the test can end it precisely
# rather than pattern-killing processes on a real machine.
PIDFILE="$HYPRPROFILE_ROOT/state/daemon.pid"
spawn_sh "printf '%s\n' \$\$ > \"$PIDFILE\"; exec tail -f /dev/null"
EOF
chmod +x "$HYPRPROFILE_ROOT/profiles/alpha/hooks/start"

"$HP" set beta  >/dev/null 2>&1
"$HP" set alpha >/dev/null 2>&1          # leaves the fake daemon running
sleep 0.5
check "the fake daemon is running" test -s "$HYPRPROFILE_ROOT/state/daemon.pid"
out=$("$HP" set beta 2>&1); rc=$?
check_eq "the switch after a daemon-leaving hook succeeds" "0" "$rc"
check_eq "and actually took effect" "beta" "$("$HP" current)"
check "no lock complaint" bash -c '[[ $1 != *"switch is still running"* ]]' _ "$out"
kill "$(<"$HYPRPROFILE_ROOT/state/daemon.pid")" 2>/dev/null
rm -f "$HYPRPROFILE_ROOT/profiles/alpha/hooks/start" "$HYPRPROFILE_ROOT/state/daemon.pid"
"$HP" set alpha >/dev/null 2>&1

echo "== doctor accepts a consistent set =="
"$HP" doctor >/dev/null 2>&1
check_eq "doctor exits 0 when healthy" "0" "$?"

echo "== doctor rejects mixed entrypoints =="
mkprofile gamma conf
"$HP" doctor >/dev/null 2>&1
check_eq "doctor exits 1 on lua/conf mix" "1" "$?"

echo "== repair heals a clobbered link =="
rm -rf "$HYPRPROFILE_ROOT/profiles/gamma"
rm -f "$XDG_CONFIG_HOME/kitty"
"$HP" repair >/dev/null 2>&1
check "repair restored kitty" test -L "$XDG_CONFIG_HOME/kitty"

echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
exit $(( fail > 0 ))

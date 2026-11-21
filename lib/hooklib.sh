#!/usr/bin/env bash
# Sourced by profile start/stop hooks. Provides the two things every hook
# needs: launching a component so it outlives the hook, and stopping one
# without taking unrelated processes down with it.

# Launch detached. The hook process is killed after HYPRPROFILE_HOOK_TIMEOUT,
# so anything long-lived has to be in its own session.
spawn() {
  if ! command -v "${1%% *}" >/dev/null 2>&1 && [[ ! -x ${1%% *} ]]; then
    printf 'spawn: %s not found, skipping\n' "${1%% *}" >&2
    return 0
  fi
  # 9>&- so a long-lived component cannot keep hyprprofile's switch lock open.
  setsid --fork "$@" >/dev/null 2>&1 9>&- &
  disown 2>/dev/null || true
}

# Same, but the argument is a shell command line rather than argv.
spawn_sh() {
  setsid --fork bash -lc "$1" >/dev/null 2>&1 9>&- &
  disown 2>/dev/null || true
}

# Every pid between us and init. `pgrep -f` matches on the whole command line,
# so a shell that merely mentions the pattern - this hook, hyprprofile itself,
# the terminal that launched it - would otherwise be a candidate for killing.
_ancestors() {
  local p=$$ out=()
  while [[ -n $p && $p != 0 && $p != 1 ]]; do
    out+=("$p")
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') || break
  done
  printf '%s\n' ${out+"${out[@]}"}
}

# Pids matching the pattern, minus ourselves and everyone who spawned us.
_matching() {
  local pat=$1 skip pid
  skip=" $(_ancestors | tr '\n' ' ') "
  while read -r pid; do
    [[ -n $pid ]] || continue
    [[ $skip == *" $pid "* ]] && continue
    printf '%s\n' "$pid"
  done < <(pgrep -u "$UID" -f -- "$pat" 2>/dev/null)
}

# Start something only if no matching process is already running. Used for
# components that a `hyprctl reload` may have re-launched on its own.
#
# Matching ignores our own process tree for the same reason stop_match does:
# a hook, or the terminal that ran hyprprofile, can easily have the pattern
# somewhere in its command line, and then the component would never start.
spawn_once() { # spawn_once <pgrep-pattern> <command...>
  local pat=$1; shift
  [[ -n $(_matching "$pat") ]] && return 0
  spawn "$@"
}

spawn_once_sh() { # spawn_once_sh <pgrep-pattern> <command line>
  local pat=$1; shift
  [[ -n $(_matching "$pat") ]] && return 0
  spawn_sh "$1"
}

# Stop by full-command-line match, TERM first and KILL only if it hangs on.
# Scoped to the current user so a shared machine stays sane.
stop_match() {
  local pat=$1 pids
  pids=$(_matching "$pat" | tr '\n' ' ')
  [[ -n ${pids// /} ]] || return 0
  kill -TERM $pids 2>/dev/null
  local i
  for i in {1..20}; do
    [[ -z $(_matching "$pat") ]] && return 0
    sleep 0.1
  done
  pids=$(_matching "$pat" | tr '\n' ' ')
  [[ -n ${pids// /} ]] && kill -KILL $pids 2>/dev/null
  return 0
}

# Wait for the compositor socket. At login the hook can run before Hyprland is
# ready; on a live switch this returns immediately.
wait_for_wayland() {
  local tries=${1:-50} s
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  [[ -n ${WAYLAND_DISPLAY:-} && -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]] && return 0
  while (( tries-- > 0 )); do
    for s in "$XDG_RUNTIME_DIR"/wayland-*; do
      [[ $s == *.lock ]] && continue
      if [[ -S $s ]]; then export WAYLAND_DISPLAY="${s##*/}"; return 0; fi
    done
    sleep 0.2
  done
  return 1
}

#!/usr/bin/env bash
# Why is a monitor blinking?
#
# A display that keeps cutting out and coming back is the link failing to
# train: the GPU drives a mode the sink cannot lock onto, the monitor drops,
# Hyprland re-adds it, repeat. This finds out whether that is what is
# happening, from evidence rather than from a table of standards.
#
# The previous version of this script guessed: it compared the mode's
# bandwidth against DP 1.2 and HDMI 2.0 ceilings and called anything above
# them broken. That is wrong on a DP 1.4 link - it flagged a perfectly healthy
# 240 Hz panel. Three real signals replace the guess:
#
#   1. is the running mode one the monitor actually advertises?
#   2. what did the link *negotiate* (lanes and rate, from the amdgpu debugfs)?
#   3. has Hyprland actually been adding and removing this output?
#
# Run it from inside a Hyprland session:
#     ./tools/monitor-doctor.sh              # report to the terminal
#     ./tools/monitor-doctor.sh --report     # and to a file you can paste
set -uo pipefail

REPORT=
[[ ${1:-} == --report ]] && REPORT=${2:-/tmp/monitor-doctor.txt}
if [[ -n $REPORT ]]; then
  exec > >(tee "$REPORT") 2>&1
  trap 'echo; echo "written to $REPORT"' EXIT
fi

command -v hyprctl >/dev/null 2>&1 || { echo "needs to run inside Hyprland"; exit 1; }
command -v jq      >/dev/null 2>&1 || { echo "needs jq: sudo pacman -S jq"; exit 1; }

if [[ -t 1 && -z $REPORT ]]; then
  B=$'\033[1m'; N=$'\033[0m'; R=$'\033[31m'; Y=$'\033[33m'; G=$'\033[32m'; D=$'\033[2m'
else
  B= N= R= Y= G= D=
fi

say()  { printf '%s\n' "$*"; }
head2() { printf '\n%s== %s ==%s\n' "$B" "$1" "$N"; }

# ------------------------------------------------------------------ links --
# The one authoritative answer to "how much can this cable carry right now" is
# what the link negotiated, and amdgpu puts it in debugfs. It is root-only, so
# ask once, non-interactively, and carry on without it if that is refused.
declare -A LANES RATE
read_links() {
  local base=/sys/kernel/debug/dri
  local dump
  dump=$(sudo -n sh -c '
      for f in /sys/kernel/debug/dri/*/DP-*/link_settings; do
        [ -f "$f" ] || continue
        printf "%s|%s\n" "$(basename "$(dirname "$f")")" "$(sed -n "/^Current/p" "$f" | tr -s " ")"
      done' 2>/dev/null) || return 1
  [[ -n $dump ]] || return 1
  local line name rest
  while IFS='|' read -r name rest; do
    [[ -n $name ]] || continue
    # "Current:  4  0x14  0"  ->  lanes, rate code
    local l r
    l=$(grep -oE '[0-9]+' <<<"$rest" | head -1)
    r=$(grep -oiE '0x[0-9a-f]+' <<<"$rest" | head -1)
    [[ -n ${l:-} && -n ${r:-} ]] && { LANES[$name]=$l; RATE[$name]=$r; }
  done <<<"$dump"
  return 0
}

# Per-lane rate in Gbit/s, and the line-code efficiency that goes with it.
rate_gbps() {
  case ${1,,} in
    0x06) echo "1.62 0.8"  ;;   # RBR
    0x0a) echo "2.70 0.8"  ;;   # HBR
    0x14) echo "5.40 0.8"  ;;   # HBR2
    0x1e) echo "8.10 0.8"  ;;   # HBR3
    0x01) echo "10.0 0.9697" ;; # UHBR10
    0x02) echo "13.5 0.9697" ;; # UHBR13.5
    0x04) echo "20.0 0.9697" ;; # UHBR20
    *)    echo ""          ;;
  esac
}
rate_name() {
  case ${1,,} in
    0x06) echo "RBR"  ;; 0x0a) echo "HBR" ;; 0x14) echo "HBR2 (DP 1.2)" ;;
    0x1e) echo "HBR3 (DP 1.4)" ;; 0x01) echo "UHBR10" ;; 0x02) echo "UHBR13.5" ;;
    0x04) echo "UHBR20" ;; *) echo "unknown code" ;;
  esac
}

HAVE_LINKS=0
if read_links; then
  HAVE_LINKS=1
else
  say "${D}(no negotiated link data - run with sudo rights, or:"
  say "  sudo sh -c 'cat /sys/kernel/debug/dri/*/DP-*/link_settings'${N}"
fi

# --------------------------------------------------------------- the logs --
# "Removed monitor X" / "Monitor X added" pairs are the blink, written down.
LOG=$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$UID}"/hypr/*/hyprland.log 2>/dev/null | head -1)

MON=$(hyprctl monitors -j)
SUGGEST=

head2 "outputs"
while read -r m; do
  name=$(jq -r '.name'        <<<"$m")
  desc=$(jq -r '.description' <<<"$m")
  w=$(jq -r '.width'          <<<"$m")
  h=$(jq -r '.height'         <<<"$m")
  hz=$(jq -r '.refreshRate'   <<<"$m")
  x=$(jq -r '.x'              <<<"$m")
  y=$(jq -r '.y'              <<<"$m")
  vrr=$(jq -r '.vrr'          <<<"$m")
  dis=$(jq -r '.disabled'     <<<"$m")
  modes=$(jq -r '.availableModes[]?' <<<"$m")

  printf '\n%s%s%s  %s\n' "$B" "$name" "$N" "$desc"
  printf '  running   %sx%s @ %.2f Hz   at %s,%s   vrr=%s disabled=%s\n' \
    "$w" "$h" "$hz" "$x" "$y" "$vrr" "$dis"

  # 1. Is the running mode one the monitor advertises? A mode that is not in
  #    the EDID list is being forced, and forcing is how you get a blink.
  hz_r=$(printf '%.0f' "$hz")
  if [[ -z $modes ]]; then
    printf '  modes     %s(none reported)%s\n' "$D" "$N"
  elif grep -qE "^${w}x${h}@${hz_r}(\.[0-9]+)?Hz$" <<<"$modes" \
    || awk -v w="$w" -v h="$h" -v r="$hz" '
         { split($0, a, /[x@]/); gsub(/Hz/, "", a[3])
           if (a[1]==w && a[2]==h && (a[3]-r < 0.6 && r-a[3] < 0.6)) found=1 }
         END { exit !found }' <<<"$modes"; then
    printf '  modes     %sok%s   the running mode is advertised by the monitor\n' "$G" "$N"
  else
    flag=1
    printf '  modes     %sFORCED%s  %sx%s@%s is not in this monitor'\''s mode list -\n' \
      "$R" "$N" "$w" "$h" "$hz_r"
    printf '            that alone will make it blink. Advertised:\n'
    printf '%s\n' "$modes" | sed 's/^/              /'
  fi

  # 2. What the mode costs, against what the link actually negotiated.
  need=$(awk -v w="$w" -v h="$h" -v r="$hz" 'BEGIN{printf "%.1f", w*h*r*24*1.06/1e9}')
  printf '  needs     ~%s Gbit/s at 8-bit %s(estimate, CVT-R2 blanking)%s\n' "$need" "$D" "$N"

  if (( HAVE_LINKS )) && [[ -n ${LANES[$name]:-} ]]; then
    read -r per eff <<<"$(rate_gbps "${RATE[$name]}")"
    if [[ -n ${per:-} ]]; then
      cap=$(awk -v l="${LANES[$name]}" -v p="$per" -v e="$eff" 'BEGIN{printf "%.1f", l*p*e}')
      printf '  link      %s lanes x %s Gbit/s, %s -> %s Gbit/s of payload\n' \
        "${LANES[$name]}" "$per" "$(rate_name "${RATE[$name]}")" "$cap"
      # Arithmetic can prove a mode impossible. It cannot prove one fine: a
      # high utilisation number is not a fault, and the last version of this
      # script called a healthy 240 Hz panel broken on exactly that mistake.
      # So: shout only when the mode does not fit, otherwise state the number
      # and let the disconnect count below do the diagnosing.
      pct=$(awk -v n="$need" -v c="$cap" 'BEGIN{printf "%d", n/c*100}')
      if (( $(awk -v n="$need" -v c="$cap" 'BEGIN{print (n>c)?1:0}') )); then
        flag=1
        printf '  verdict   %sover the negotiated link%s - it cannot carry this mode\n' "$R" "$N"
      else
        printf '  verdict   fits, using %s%% of it %s(not a fault on its own)%s\n' "$pct" "$D" "$N"
      fi
    else
      printf '  link      %s lanes, rate code %s %s(unrecognised)%s\n' \
        "${LANES[$name]}" "${RATE[$name]}" "$D" "$N"
    fi
  else
    printf '  link      %snot known - cannot say whether the cable can carry it%s\n' "$D" "$N"
  fi

  # 3. Has Hyprland been losing this output? This is the blink itself.
  if [[ -n $LOG ]]; then
    gone=$(grep -c "Removed monitor $name" "$LOG" 2>/dev/null || echo 0)
    back=$(grep -cE "[Mm]onitor $name .*(added|connected)" "$LOG" 2>/dev/null || echo 0)
    if (( gone > 1 )); then
      flag=1
      printf '  log       %s%s disconnect events%s in this session (%s re-adds) - it is dropping\n' \
        "$R" "$gone" "$N" "$back"
    else
      printf '  log       %s disconnects this session\n' "$gone"
    fi
  fi

  # The line to paste, keyed by description so a boot that renumbers the
  # connectors cannot apply it to the wrong screen.
  best=$(printf '%s\n' "$modes" | awk -v w="$w" -v h="$h" '
      { split($0, a, /[x@]/); gsub(/Hz/, "", a[3])
        if (a[1]==w && a[2]==h && a[3]+0 < 160 && a[3]+0 > best) { best=a[3]+0 } }
      END { if (best) printf "%dx%d@%.2f", w, h, best }')
  if [[ ${flag:-} == 1 && -n $best ]]; then
    printf '  %sconfig%s    %sthis one is misbehaving; the line that steps it down:%s\n' "$D" "$N" "$Y" "$N"
    printf '            hl.monitor({ output = "desc:%s", mode = "%s", position = "%sx%s", scale = 1 })\n' \
      "$desc" "$best" "$x" "$y"
    SUGGEST+="$name "
  else
    printf '  %sconfig%s    hl.monitor({ output = "desc:%s", mode = "%dx%d@%.2f", position = "%sx%s", scale = 1 })\n' \
      "$D" "$N" "$desc" "$w" "$h" "$hz" "$x" "$y"
  fi
  flag=
done < <(jq -c '.[]' <<<"$MON")

# ----------------------------------------------------------------- ddc/ci --
head2 "DDC/CI (the bar's brightness slider talks to the monitors over the DP AUX channel)"
if command -v ddcutil >/dev/null 2>&1; then
  dsa=${XDG_CACHE_HOME:-$HOME/.cache}/ddcutil/dsa
  if [[ -f $dsa ]]; then
    say "  ${D}retry profile per i2c bus (high 'step' = ddcutil backing off = flaky bus)${N}"
    awk '/^i2c-/ { n=gsub(/\{/,"{"); split($0,f," ");
                   printf "    %-8s %3d transactions, current backoff step %s of 10\n", f[1], n, f[3] }' "$dsa"
    say "  ${D}a monitor whose bus needs the maximum backoff is answering badly on AUX.${N}"
    say "  ${D}To rule DDC out entirely, stop the shell for a minute and watch:${N}"
    say "    pkill -f 'qs -c ii'   # the blink should be unaffected if DDC is innocent"
  else
    say "  no ddcutil cache yet ($dsa)"
  fi
else
  say "  ddcutil not installed - the shell is using brightnessctl, DDC is not in play"
fi

# ------------------------------------------------------------------ where --
head2 "where the fix goes"
say "  ~/.config/hypr/custom/general.lua   (loaded from hyprland.lua, survives install.sh)"
say "  then: hyprctl reload && hyprctl monitors | grep -E 'Monitor|@'"
if [[ -n $SUGGEST ]]; then
  say ""
  say "  ${Y}Misbehaving: $SUGGEST${N}"
  say "  Paste its config line above into that file, reload, and see whether the"
  say "  blinking stops. If it does, the mode was the fault; if it does not, the"
  say "  next suspects are the DP cable, the monitor's own OSD (DisplayPort Ver.,"
  say "  Input Signal Plus), and DDC/CI above."
fi

head2 "raw"
say "$MON" | jq '[.[] | {name, description, width, height, refreshRate, x, y, scale, vrr, disabled, availableModes}]'

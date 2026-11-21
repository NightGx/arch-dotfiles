#!/usr/bin/env bash
# Revive the inert trailing block in a hyprland.lua.
#
# A Lua config that ends with bare `decoration = {...}` / `env = X,Y` /
# `animations = {...}` assigns plain globals: valid Lua, but Hyprland reads
# config through hl.config() and hl.env(), so none of it applies. This wraps
# those blocks in the real calls.
#
# The existing values are carried across verbatim rather than retyped, so the
# result is exactly what the dead block was asking for. Idempotent.
set -euo pipefail

FILE="${1:?usage: fix-inert-config.sh <hyprland.lua>}"
MARKER="hyprprofile: revived"

[[ -f $FILE ]] || { printf 'err  no such file: %s\n' "$FILE" >&2; exit 1; }

if grep -qF "$MARKER" "$FILE"; then
  printf '==> %s already fixed\n' "$FILE" >&2
  exit 0
fi

# Nothing to do if there is no top-level assignment to fix.
if ! grep -qE '^(decoration|animations) = \{|^env = [A-Za-z_]' "$FILE"; then
  printf '==> nothing inert found in %s\n' "$FILE" >&2
  exit 0
fi

tmp=$(mktemp)
awk -v marker="$MARKER" '
  BEGIN { in_block = 0; fixed = 0 }

  # A top-level `name = {` for a Hyprland config section. Anything indented is
  # a table field and must be left alone.
  /^(decoration|animations|general|input|misc|dwindle|master|binds) = \{$/ && !in_block {
    print "-- " marker " this block: it was a bare Lua global and never"
    print "-- reached the compositor. hl.config() is what Hyprland reads."
    print "hl.config({"
    print "    " $0
    in_block = 1
    fixed = 1
    next
  }

  # Closing brace of that block, at column 0.
  in_block && /^\}$/ {
    print "    }"
    print "})"
    in_block = 0
    next
  }

  # Body of the block: indent one more level to sit inside hl.config({.
  # Blank lines stay blank rather than becoming four spaces.
  in_block { print ($0 == "" ? "" : "    " $0); next }

  # `env = NAME,value` - hyprlang syntax that parses as Lua but assigns nil.
  /^env = [A-Za-z_][A-Za-z0-9_]*,/ {
    line = $0
    sub(/^env = /, "", line)
    split(line, parts, ",")
    name = parts[1]
    value = substr(line, length(name) + 2)
    gsub(/^[ \t]+|[ \t]+$/, "", value)
    printf "hl.env(\"%s\", \"%s\") -- %s from `env = %s`\n", name, value, marker, line
    fixed = 1
    next
  }

  { print }

  END { if (!fixed) exit 3 }
' "$FILE" > "$tmp" || {
  rc=$?
  rm -f "$tmp"
  [[ $rc -eq 3 ]] && { printf '==> nothing to change\n' >&2; exit 0; }
  printf 'err  awk failed (%d)\n' "$rc" >&2; exit 1
}

[[ -s $tmp ]] || { rm -f "$tmp"; printf 'err  produced an empty file, aborting\n' >&2; exit 1; }
grep -qF "$MARKER" "$tmp" || { rm -f "$tmp"; printf 'err  transform did not apply, aborting\n' >&2; exit 1; }

# Braces must still balance, or Hyprland gets an unparseable config.
open=$(grep -o '{' "$tmp" | wc -l); close=$(grep -o '}' "$tmp" | wc -l)
[[ $open -eq $close ]] || {
  rm -f "$tmp"
  printf 'err  brace count went from balanced to %d/%d, aborting\n' "$open" "$close" >&2
  exit 1
}

cp -f "$FILE" "$FILE.pre-hyprprofile"
mv "$tmp" "$FILE"
chmod 0644 "$FILE"
printf '==> revived the inert block in %s (original kept as %s)\n' \
  "$FILE" "$(basename "$FILE").pre-hyprprofile" >&2

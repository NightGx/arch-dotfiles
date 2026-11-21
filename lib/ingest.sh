#!/usr/bin/env bash
# Taking a new wallpaper in: thumbnail, dot colour, index entry.
#
# Shared by tools/fetch-wallpapers.sh (which walks the whole folder) and by
# `hyprprofile look new` (which takes one file). Videos are handled the same
# way as stills - a frame is pulled out first and everything downstream works
# on that, so an animated wallpaper gets a real thumbnail in the picker and a
# palette derived from what it actually looks like.

# ImageMagick 7 calls it `magick`, 6 calls it `convert`. Pillow does the same
# job where ImageMagick is not installed - both run the same maths.
ING_IM=()
if   command -v magick  >/dev/null 2>&1; then ING_IM=(magick)
elif command -v convert >/dev/null 2>&1; then ING_IM=(convert)
fi
ING_PIL=0
python3 -c 'import PIL' >/dev/null 2>&1 && ING_PIL=1

ing_have() { (( ${#ING_IM[@]} || ING_PIL )); }

ing_is_video() {
  case ${1,,} in *.mp4|*.webm|*.mkv|*.avi|*.mov) return 0 ;; *) return 1 ;; esac
}

# A representative frame, three seconds in - far enough past a fade-in to be
# the actual look of the thing. Falls back to the first frame for clips that
# are shorter than that.
ing_frame() { # ing_frame <video> <out.png>
  command -v ffmpeg >/dev/null 2>&1 || return 1
  ffmpeg -y -loglevel error -ss 3 -i "$1" -frames:v 1 -vf scale=1280:-1 "$2" 2>/dev/null && [[ -s $2 ]] && return 0
  ffmpeg -y -loglevel error -i "$1" -frames:v 1 -vf scale=1280:-1 "$2" 2>/dev/null && [[ -s $2 ]]
}

# Resolve anything to a still we can measure. Prints the path; when it made a
# temporary file it prints it and the caller is expected to clean up via
# ING_TMP_STILL.
ING_TMP_STILL=""
ing_still_of() {
  ING_TMP_STILL=""
  if ing_is_video "$1"; then
    local t; t=$(mktemp --suffix=.png)
    if ing_frame "$1" "$t"; then ING_TMP_STILL=$t; printf '%s\n' "$t"; return 0; fi
    rm -f "$t"; return 1
  fi
  printf '%s\n' "$1"
}
ing_still_cleanup() { [[ -n ${ING_TMP_STILL:-} ]] && rm -f "$ING_TMP_STILL"; ING_TMP_STILL=""; }

# The colour used for an entry's dot in the picker: the most saturated colour
# that still covers a real share of the image, pulled towards a lightness that
# stays legible on a dark menu.
ing_accent() {
  local src still
  still=$(ing_still_of "$1") || { printf '#8ab4f8\n'; return 0; }
  if (( ${#ING_IM[@]} )); then _ing_accent_im "$still"; else _ing_accent_pil "$still"; fi
  ing_still_cleanup
}

_ing_accent_im() {
  "${ING_IM[@]}" "$1" -resize 160x90\! -colors 16 -format '%c' histogram:info:- 2>/dev/null |
  awk '
    function max3(a,b,c){ return a>b ? (a>c?a:c) : (b>c?b:c) }
    function min3(a,b,c){ return a<b ? (a<c?a:c) : (b<c?b:c) }
    {
      if (match($0, /\(([ 0-9]+),([ 0-9]+),([ 0-9]+)/, m) == 0) next
      split($0, f, ":"); n = f[1] + 0
      r = m[1]/255; g = m[2]/255; b = m[3]/255
      mx = max3(r,g,b); mn = min3(r,g,b)
      l = (mx + mn) / 2
      d = mx - mn
      s = (d == 0) ? 0 : (l > 0.5 ? d/(2-mx-mn) : d/(mx+mn))
      score = (s ^ 1.6) * (1 - (l>0.55 ? l-0.55 : 0.55-l) * 1.4) * (n ^ 0.35)
      if (score > best) { best = score; bs = s; bl = l
        if (d == 0) h = 0
        else if (mx == r) h = ((g-b)/d)
        else if (mx == g) h = 2 + (b-r)/d
        else              h = 4 + (r-g)/d
        bh = h / 6; if (bh < 0) bh += 1
      }
    }
    END {
      if (best == "") { print "#8ab4f8"; exit }
      l = bl < 0.55 ? 0.55 : (bl > 0.72 ? 0.72 : bl)
      s = bs < 0.45 ? 0.45 : (bs > 0.95 ? 0.95 : bs)
      q = (l < 0.5) ? l*(1+s) : l+s-l*s
      p = 2*l - q
      for (i = 0; i < 3; i++) {
        t = bh + (1 - i) / 3.0
        if (t < 0) t += 1; if (t > 1) t -= 1
        if      (t < 1/6.0) v = p + (q-p)*6*t
        else if (t < 1/2.0) v = q
        else if (t < 2/3.0) v = p + (q-p)*(2/3.0 - t)*6
        else                v = p
        c[i] = int(v*255 + 0.5)
      }
      printf "#%02x%02x%02x\n", c[0], c[1], c[2]
    }'
}

_ing_accent_pil() {
  python3 - "$1" <<'PYEOF'
import colorsys, sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB").resize((160, 90), Image.LANCZOS)
q = im.quantize(colors=16, method=Image.MEDIANCUT).convert("RGB")
counts = {}
for px in q.getdata():
    counts[px] = counts.get(px, 0) + 1
best, score_best = None, -1
for (r, g, b), n in counts.items():
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    score = (s ** 1.6) * (1 - abs(l - 0.55) * 1.4) * (n ** 0.35)
    if score > score_best:
        score_best, best = score, (h, l, s)
if best is None:
    print("#8ab4f8"); raise SystemExit
h, l, s = best
l = min(max(l, 0.55), 0.72)
s = min(max(s, 0.45), 0.95)
r, g, b = colorsys.hls_to_rgb(h, l, s)
print("#%02x%02x%02x" % (int(r * 255 + 0.5), int(g * 255 + 0.5), int(b * 255 + 0.5)))
PYEOF
}

ing_thumb() { # ing_thumb <source> <destination.png>
  local still
  still=$(ing_still_of "$1") || return 1
  local rc=0
  if (( ${#ING_IM[@]} )); then
    "${ING_IM[@]}" "$still" -auto-orient -thumbnail 320x320 -strip "$2" || rc=$?
  else
    python3 - "$still" "$2" <<'PYEOF' || rc=$?
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
im.thumbnail((320, 320), Image.LANCZOS)
im.save(sys.argv[2], optimize=True)
PYEOF
  fi
  ing_still_cleanup
  return $rc
}

# "my_cool-wall" -> "My Cool Wall"
ing_pretty() {
  printf '%s\n' "${1//[_-]/ }" | sed -E 's/(^| )([a-z])/\1\u\2/g'
}

ing_slug() { local b=${1##*/}; b=${b%.*}; printf '%s\n' "${b//[^A-Za-z0-9._-]/-}"; }

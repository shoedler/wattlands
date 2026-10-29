#!/usr/bin/env bash
# Builds the r6 base (build/v3mock/r6/base.png): the reference's tank re-pixelled. ImageMagick + Godot.
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."
d=build/v3mock/r6
mkdir -p "$d"
source tools/env.sh >/dev/null
gd() { env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/godot.sh --headless --path . -s assets/tank/v3/tools_src/r6_base.gd -- "$1" 2>&1 | grep -E "prep|clean|ERROR|error" || true; }
magick assets/tank/v3/tools_src/src/tank_4rider.png -filter Box -resize 90% -unsharp 0x0.7+1.0+0 "$d/s90.png"
gd prep
# the curated palette: the image's own 44 darks, browns, rusts and lamp tones, plus the fixed accents
magick "$d/prep.png" -background black -alpha remove +dither -colors 44 -unique-colors "$d/pal_auto.png"
magick -size 1x1 xc:"#050302" xc:"#0b0705" xc:"#140c08" xc:"#2e140c" xc:"#42200f" xc:"#fff6d8" xc:"#ffd98a" \
  xc:"#e3a24a" xc:"#b08a4a" xc:"#6a5236" xc:"#dff0ff" xc:"#9fd0ff" xc:"#4a78a8" xc:"#ff4a30" xc:"#8a2a1c" \
  xc:"#40ff70" xc:"#1c7a3a" xc:"#2e4a3a" xc:"#5a7a62" +append "$d/pal_cur.png"
magick "$d/pal_auto.png" "$d/pal_cur.png" +append "$d/palette.png"
magick "$d/prep.png" +dither -remap "$d/palette.png" "$d/q.png"
gd clean
magick "$d/base.png" -alpha off -unique-colors -format "palette colours: %w\n" info:

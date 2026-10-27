#!/usr/bin/env bash
# Assembles the r3 GIFs from build/v3mock/tank/r3/frames/<name>/f###.png (ImageMagick).
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."
out=build/v3mock/tank/${1:-r3}
command -v magick >/dev/null || { echo "gifs_r3.sh: magick not on PATH; the frame strips are the deliverable"; exit 0; }
gif() {
  [ -d "$out/frames/$1" ] || return 0
  magick -delay "$2" -loop 0 "$out/frames/$1"/f*.png +dither -layers Optimize "$out/$3"
  echo "$out/$3"
}
gif drive 8 drive.gif
gif tilt 7 tilt_a.gif
gif loader 10 loader_closeup.gif
gif secbox 8 secondaries_closeup.gif
gif fire 6 fire_closeup.gif

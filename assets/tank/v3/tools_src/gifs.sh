#!/usr/bin/env bash
# Assembles the GIFs of the v3 tank mock from the frame folders mock_v3.gd wrote
# (build/v3mock/tank/frames/<name>/f###.png). Needs ImageMagick (magick) on PATH.
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."
out=build/v3mock/tank
command -v magick >/dev/null || { echo "gifs.sh: magick not on PATH; the frame strips are the deliverable"; exit 0; }
gif() { # <frames dir> <delay in 1/100 s> <out name>
  [ -d "$out/frames/$1" ] || return 0
  magick -delay "$2" -loop 0 "$out/frames/$1"/f*.png +dither -layers Optimize "$out/$3"
  echo "$out/$3"
}
for o in A B C; do
  gif "drive_$o" 8 "drive_$o.gif"
  for m in a b c; do gif "tilt_${o}_$m" 7 "tilt_${o}_$m.gif"; done
done
gif loader 10 loader_closeup.gif
gif bays 8 bays_A.gif

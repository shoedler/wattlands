#!/usr/bin/env bash
# Rebuilds the Hangar's backdrop in assets/tank/hangar/ (room.png, end.png, door.png, gate.png, shutter.png).
# Godot only, no fal, no source image (docs/ART_PIPELINE.md: Tank bakes its art with its own scripts).
#   bash assets/tank/hangar/tools_src/hangar_bake.sh
# Then import: tools/godot.sh --headless --path . --import
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."
source tools/env.sh >/dev/null
mkdir -p build/tank/hangar_art
set +e
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/godot.sh --timeout=600 --headless --path . \
	-s assets/tank/hangar/tools_src/hangar_bake.gd >build/tank/hangar_art/bake.log 2>&1
rc=$?
set -e
grep -E "SCRIPT ERROR|ERROR|Parse Error|hangar_bake" build/tank/hangar_art/bake.log || true
exit "$rc"

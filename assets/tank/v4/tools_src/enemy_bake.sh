#!/usr/bin/env bash
# Rebuilds the enemies' kit in assets/tank/v4/ (enemies.png, enemies.json, bushes.png, far_ground.png) with
# the v3 tank generator's px, gear, hull and finish. Godot only, no fal, no source image.
#   bash assets/tank/v4/tools_src/enemy_bake.sh
# Then import: tools/godot.sh --headless --path . --import
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."
source tools/env.sh >/dev/null
mkdir -p build/tank/v4_art
set +e
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/godot.sh --timeout=900 --headless --path . \
	-s assets/tank/v4/tools_src/enemy_bake.gd >build/tank/v4_art/bake.log 2>&1
rc=$?
set -e
grep -E "SCRIPT ERROR|ERROR|Parse Error|baked|atlas|bake done" build/tank/v4_art/bake.log || true
exit "$rc"

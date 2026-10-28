#!/usr/bin/env bash
# Rebuilds the production v3 tank kit in assets/tank/v3/ (tank_base.png, the gear and gun sprites,
# the track shoe, the blast sheets, kit.json) from the r6 generator. ImageMagick + Godot.
#   bash assets/tank/v3/tools_src/bake.sh          (the planes: bash assets/tank/v3/tools_src/env_regen.sh)
# Then import: tools/godot.sh --headless --path . --import
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."
bash assets/tank/v3/tools_src/r6_base.sh
source tools/env.sh >/dev/null
for i in 1 2 3 4 5; do
	set +e
	env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/godot.sh --timeout=900 --headless --path . \
		-s assets/tank/v3/tools_src/bake.gd >build/v3mock/bake.log 2>&1
	rc=$?
	set -e
	[ "$rc" -ne 75 ] && break
done
grep -E "SCRIPT ERROR|ERROR|bake" build/v3mock/bake.log || true
exit "$rc"

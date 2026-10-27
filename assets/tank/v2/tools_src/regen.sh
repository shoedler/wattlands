#!/usr/bin/env bash
# Regenerates the Diesel Domestiques v2 art kit (assets/tank/v2/) from THE reference, with no fal call.
# Run from the repository root in Git Bash:  bash assets/tank/v2/tools_src/regen.sh
# The scripts load their helpers from res://build/v2/, so they are copied there first (this folder is
# .gdignore'd). Intermediates and previews land in build/v2/; the shipped files in assets/tank/v2/.
# Order: ref (decode the webp) -> plate (the tank-free plate) -> tankfix (markings and crew painted out)
# -> tank (the cut-out tank) -> assemble (modules, the four variants, turret_barrel.png) -> planes2 (the
# planes with their baked blur) -> crew20 (the 20 px crewmen) -> kit (kit.json) -> enemies (they read
# kit.json) -> kit again (the enemies' measured muzzles). Afterwards: tools/godot.sh --headless --path . --import
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."
source tools/env.sh >/dev/null 2>&1
mkdir -p build/v2/view
cp assets/tank/v2/tools_src/*.gd build/v2/
run() {
	env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/godot.sh --timeout=900 --headless --path . -s "build/v2/$1" >"build/v2/$1.log" 2>&1 \
		|| { echo "regen: $1 failed (build/v2/$1.log)"; exit 1; }
	grep -E "SCRIPT ERROR|^ERROR" "build/v2/$1.log" && { echo "regen: $1 logged errors"; exit 1; }
	echo "regen: $1 done"
}
for s in ref.gd plate.gd tankfix.gd tank.gd assemble.gd planes2.gd crew20.gd kit.gd enemies.gd kit.gd; do
	run "$s"
done

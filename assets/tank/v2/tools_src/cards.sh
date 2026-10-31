#!/usr/bin/env bash
# Renders the picker card and the content cards (assets/tank/v2/picker_card.png, card_mission.png,
# card_ambush.png, card_drill.png, card_roam.png) in-engine: the view's fixture scene without its HUD at 960 x 540 through
# tools/screenshot --scene (a window: headless captures are blank), then cards.gd crops and scales
# each render to 320 x 180. Run from the repository root in Git Bash:
#   bash assets/tank/v2/tools_src/cards.sh
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." || exit 1
source tools/env.sh >/dev/null 2>&1
OUT=build/v2/cards
mkdir -p build/v2
cp assets/tank/v2/tools_src/cards.gd build/v2/
render() { # <name> <fixture options>
	mkdir -p "$OUT/$1"
	local n=0
	while :; do
		TANK_FIXTURE="$2;nohud" env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/screenshot \
			--scene=res://tests/games/tank/view/fixture_scene.tscn --frames=160 --size=960x540 --out="$OUT/$1" \
			>"$OUT/$1/shot.log" 2>&1
		local rc=$?
		[ $rc -ne 75 ] && return $rc
		n=$((n + 1)); [ $n -ge 5 ] && return 75
	done
}
render picker "crew=3;kind=v4:far_duel;nopip" || exit 1
render mission "crew=3;kind=v4:boss_far;nopip" || exit 1
render ambush "crew=3;kind=v4:bow_duel;nopip" || exit 1
render drill "crew=1;kind=v4:advance_far" || exit 1
render roam "crew=3;kind=v4:roam_west;nopip" || exit 1
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/godot.sh --headless --path . -s build/v2/cards.gd -- "$OUT" || exit 1
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/godot.sh --headless --path . --import >/dev/null 2>&1

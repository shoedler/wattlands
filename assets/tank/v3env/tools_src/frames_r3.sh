#!/usr/bin/env bash
# MOCK r3: the tank builder's r4 tank composed into the r2 frames (moderate, seat layout A with the
# ERG/SIM tags, ground line 385). Output: build/v3mock/env/r3/.
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."
OUT=build/v3mock/env/r3
TMP=build/v3mock/tmp_shots_r3
mkdir -p "$OUT" "$TMP"
shot() {
	local name="$1" players="$2" content="$3" at="$4"
	shift 4
	rm -rf "$TMP/$name"
	env TANK_V3_TANK=r4 TANK_V3_TILT=moderate TANK_V3_HUD=A "$@" bash assets/tank/v3env/tools_src/shoot.sh "$TMP/$name" \
		--content="$content" --players="$players" --at="$at" >/dev/null
	local f
	f=$(ls "$TMP/$name"/*.png 2>/dev/null | head -1)
	if [ -n "$f" ]; then cp "$f" "$OUT/$name.png"; echo "ok   $name"; else echo "FAIL $name"; tail -5 "$TMP/$name/last.log"; fi
}
shot c4_gunline 4 ashfall_road 560 TANK_V3_LOCK=42
shot c4_boss 4 ashfall_road 1500 TANK_V3_LOCK=0 TANK_V3_RACK=2
shot c1_advance 1 ashfall_road 400 TANK_V3_LOCK=34
shot c3_roam_base 3 roam_10 300 TANK_V3_BASE_SX=640 TANK_V3_LOCK=18
echo done

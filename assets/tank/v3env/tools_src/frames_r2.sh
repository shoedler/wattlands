#!/usr/bin/env bash
# MOCK r2 (Simon picked tilt MODERATE and seat layout A): crew 1 and 4 at the new ground line,
# plus the road-line before/after. Output: build/v3mock/env/r2/.
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."
OUT=build/v3mock/env/r2
TMP=build/v3mock/tmp_shots_r2
mkdir -p "$OUT" "$TMP"
shot() {
	local name="$1" players="$2" content="$3" at="$4"
	shift 4
	rm -rf "$TMP/$name"
	env TANK_V3_TILT=moderate TANK_V3_HUD=A "$@" bash assets/tank/v3env/tools_src/shoot.sh "$TMP/$name" \
		--content="$content" --players="$players" --at="$at" >/dev/null
	local f
	f=$(ls "$TMP/$name"/*.png 2>/dev/null | head -1)
	if [ -n "$f" ]; then cp "$f" "$OUT/$name.png"; echo "ok   $name"; else echo "FAIL $name"; tail -5 "$TMP/$name/last.log"; fi
}
shot c1_advance 1 ashfall_road 400 TANK_V3_LOCK=34
shot c1_gunline 1 ashfall_road 560 TANK_V3_SEATS=-1,0,-1,-1,-1 TANK_V3_RACK=2 TANK_V3_LOCK=21
shot c1_boss 1 ashfall_road 1500 TANK_V3_SEATS=-1,-1,0,-1,-1 TANK_V3_RACK=1 TANK_V3_LOCK=0
shot c1_roam 1 roam_10 300 TANK_V3_BASE_SX=560 TANK_V3_LOCK=30
shot c4_advance 4 ashfall_road 400 TANK_V3_LOCK=55
shot c4_gunline 4 ashfall_road 560 TANK_V3_SEATS=0,1,2,-1,3 TANK_V3_LOCK=42
shot c4_boss 4 ashfall_road 1500 TANK_V3_SEATS=3,1,2,-1,0 TANK_V3_RACK=1 TANK_V3_LOCK=0
shot c4_roam 4 roam_10 300 TANK_V3_BASE_SX=620 TANK_V3_LOCK=0
# the road line before (r1 layout: ground 340, v2 road band) is the r1 frame tilt_moderate.png;
# here the same moment at the r1 ground line with the r2 road for reference
shot c4_gunline_ground340 4 ashfall_road 560 TANK_V3_GROUND_Y=340 TANK_V3_SEATS=0,1,2,-1,3 TANK_V3_LOCK=42
echo done

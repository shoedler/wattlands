#!/usr/bin/env bash
# Shoots every deliverable frame of the v3 background + HUD mock into build/v3mock/env/.
# shot <name> <players> <content> <at> [ENV=VAL ...]
cd /c/Projects/wt/tank3-env
OUT=build/v3mock/env
TMP=build/v3mock/tmp_shots
mkdir -p "$OUT" "$TMP"
shot() {
	local name="$1" players="$2" content="$3" at="$4"
	shift 4
	rm -rf "$TMP/$name"
	env "$@" bash assets/tank/v3env/tools_src/shoot.sh "$TMP/$name" --content="$content" --players="$players" --at="$at" >/dev/null
	local f
	f=$(ls "$TMP/$name"/*.png 2>/dev/null | head -1)
	if [ -n "$f" ]; then
		cp "$f" "$OUT/$name.png"
		echo "ok   $name"
	else
		echo "FAIL $name"
		tail -5 "$TMP/$name/last.log"
	fi
}
only="${1:-}"
want() { [ -z "$only" ] || [[ "$1" == $only* ]]; }

# crew 1 (solo): drive in the advance; on the gun with 2 shells racked; on the loader in the boss
want c1 && shot c1_advance_layoutA 1 ashfall_road 400 TANK_V3_LOCK=34
want c1 && shot c1_gunline_layoutA 1 ashfall_road 560 TANK_V3_SEATS=-1,0,-1,-1,-1 TANK_V3_RACK=2 TANK_V3_LOCK=21
want c1 && shot c1_boss_layoutA 1 ashfall_road 1500 TANK_V3_SEATS=-1,-1,0,-1,-1 TANK_V3_RACK=1 TANK_V3_LOCK=0
# crew 3: default stations in the advance and the boss; in the gun line the drive is left empty
want c3 && shot c3_advance_layoutA 3 ashfall_road 400 TANK_V3_LOCK=48
want c3 && shot c3_gunline_layoutA 3 ashfall_road 560 TANK_V3_SEATS=-1,0,1,-1,2 TANK_V3_RACK=3 TANK_V3_LOCK=12
want c3 && shot c3_boss_layoutA 3 ashfall_road 1500 TANK_V3_LOCK=0
# crew 4: default (lights manned, secondaries empty); gun line and boss with the secondaries manned
want c4 && shot c4_advance_layoutA 4 ashfall_road 400 TANK_V3_LOCK=55
want c4 && shot c4_gunline_layoutA 4 ashfall_road 560 TANK_V3_SEATS=0,1,2,-1,3 TANK_V3_LOCK=42
want c4 && shot c4_boss_layoutA 4 ashfall_road 1500 TANK_V3_SEATS=3,1,2,-1,0 TANK_V3_RACK=1 TANK_V3_LOCK=0
# layout B (seat board over my numbers, v2 crew row kept), gun lines
want lb && shot c1_gunline_layoutB 1 ashfall_road 560 TANK_V3_HUD=B TANK_V3_SEATS=-1,0,-1,-1,-1 TANK_V3_RACK=2 TANK_V3_LOCK=21
want lb && shot c3_gunline_layoutB 3 ashfall_road 560 TANK_V3_HUD=B TANK_V3_SEATS=-1,0,1,-1,2 TANK_V3_RACK=3 TANK_V3_LOCK=0
want lb && shot c4_gunline_layoutB 4 ashfall_road 560 TANK_V3_HUD=B TANK_V3_SEATS=0,1,2,-1,3 TANK_V3_LOCK=42
# free roam
want roam && shot c3_roam_120s 3 roam_10 120 TANK_V3_LOCK=30
want roam && shot c4_roam_300s_base 4 roam_10 300 TANK_V3_BASE_SX=620 TANK_V3_LOCK=0
# the three tilt-shift strengths (crew 4, the gun line)
want tilt && shot tilt_moderate 4 ashfall_road 560 TANK_V3_TILT=moderate TANK_V3_SEATS=0,1,2,-1,3 TANK_V3_LOCK=42
want tilt && shot tilt_strong 4 ashfall_road 560 TANK_V3_TILT=strong TANK_V3_SEATS=0,1,2,-1,3 TANK_V3_LOCK=42
want tilt && shot tilt_extreme 4 ashfall_road 560 TANK_V3_TILT=extreme TANK_V3_SEATS=0,1,2,-1,3 TANK_V3_LOCK=42
# the little base (in view ahead of the tank), crew 1
want base && shot little_base 1 ashfall_road 400 TANK_V3_BASE_SX=560 TANK_V3_LOCK=34
# the layering bug: a base lamp standing behind the hull, v2 light layering vs the fix
want lay && shot layering_before 4 ashfall_road 400 TANK_V3_BASE_SX=350 TANK_V3_LAYERFIX=0 TANK_V3_LOCK=55
want lay && shot layering_after 4 ashfall_road 400 TANK_V3_BASE_SX=350 TANK_V3_LOCK=55
# v2 as shipped, for comparison (no v3 switches)
want v2 && shot v2_c4_gunline 4 ashfall_road 560 TANK_V3_ENV=0 TANK_V3_HUD=0 TANK_V3_LAYERFIX=0
want v2 && shot v2_c1_depot 1 ashfall_road 60 TANK_V3_ENV=0 TANK_V3_HUD=0 TANK_V3_LAYERFIX=0
echo done

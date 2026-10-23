class_name SiegeSnapshotSchema
extends RefCounted
## The 10 Hz snapshot layout, exactly brief 2.6 (G0 contract). All numbers are ints; positions in
## decimetres, times in milliseconds; at most 8 KB of JSON at the 150-enemy cap. SiegeSnapshot
## (net/, B2) encodes and applies it; this file pins the keys, the row columns and the int paths.
##
## {"v": 1, "tick": n, "ph": phase index, "pt_ms": phase elapsed ms,
##  "gate": [hp (ceil), max, breach_ms], "nb": breaches, "gl": generator level, "pk": [perk codes],
##  "w": team raw watts (1 s mean),
##  "r": [[slot, target, reconnect_ms, od_ms, od_cd_ms, denarii (floor), p_eff_w, raw_w,
##         cadence_rpm, rescue 0/1, afk 0/1], ...]   one row per slot, slot order
##  "tw": [[pad, type, level, m_x100, cd_ms], ...]   built pads only, pad order
##  "e": [[id, type, road, prog_dm, lat_dm, hp (ceil)], ...]   live enemies, spawn order
##  "z": [[road, prog_dm, ttl_ms], ...]   Caltrop zones; ttl_ms = (delay + ttl) x 1000
##  "f": [[pad, [target ids]], ...]   shots of the last 0.1 s (visuals only)
##  "q": queued spawns}
## Optional keys (additive, ADR "snapshot roads and rush"), present only when not at their default so
## the common mid-wave snapshot is unchanged:
##  "ro": [road ids]   the active roads, only when they are not all three (a break: [])
##  "ru": [1, i, left_ms]   a rush is on (index i, time left), absent otherwise
##  "ib": n   Iron bands bought (1 or 2), absent at 0
##  "gd": [dm per road]   gate damage by road in 0.1 HP (west, valley, east), absent until a road took any
##  "gt": [mask per road]   per road, the enemy types that damaged the gate there (bit 1 << type code)
## A client without "ro" has all three roads active and without "ru" no rush; without "ib" no bands,
## without "gd" / "gt" no gate damage. "ib", "gd" and "gt" feed the shop (price of Iron bands, the road
## and tower type Autopilot recommends, brief 2.5) and the gate view, so a client's recommendation
## equals the host's (SiegeShopModel.cost_of, SiegeAutopilot.shop_picks).
## od_ms is the Overdrive time left (0 unless ACTIVE), od_cd_ms the cooldown left (0 unless
## COOLDOWN); a client derives od_state from them (od_ms > 0 ACTIVE, od_cd_ms > 0 COOLDOWN, else
## READY).

const VERSION := 1
## Brief 2.6 cap at 150 enemies (the relay's limit is 16 384).
const MAX_BYTES := 8192
const KEYS: Array[String] = [
	"v", "tick", "ph", "pt_ms", "gate", "nb", "gl", "pk", "w", "r", "tw", "e", "z", "f", "q"
]

## Optional keys (see above); check() does not require them.
const OPTIONAL_KEYS: Array[String] = ["ro", "ru", "ib", "gd", "gt"]
# ru columns
const RU_ON := 0
const RU_INDEX := 1
const RU_LEFT_MS := 2

# r row columns
const R_SLOT := 0
const R_TARGET := 1
const R_RECONNECT_MS := 2
const R_OD_MS := 3
const R_OD_CD_MS := 4
const R_DENARII := 5
const R_P_EFF_W := 6
const R_RAW_W := 7
const R_CADENCE := 8
const R_RESCUE := 9
const R_AFK := 10
const R_LEN := 11
# tw row columns
const TW_PAD := 0
const TW_TYPE := 1
const TW_LEVEL := 2
const TW_M_X100 := 3
const TW_CD_MS := 4
const TW_LEN := 5
# e row columns
const E_ID := 0
const E_TYPE := 1
const E_ROAD := 2
const E_PROG_DM := 3
const E_LAT_DM := 4
const E_HP := 5
const E_LEN := 6
# z row columns
const Z_ROAD := 0
const Z_PROG_DM := 1
const Z_TTL_MS := 2
const Z_LEN := 3
# f row columns
const F_PAD := 0
const F_TARGETS := 1
# gate columns
const G_HP := 0
const G_MAX := 1
const G_BREACH_MS := 2

## int_fields()["snapshot"]: f[][] converts the pad, f[][][] the target ids (an Array found at
## a matched path is left alone, GAME_SDK 12).
const INT_PATHS: Array[String] = [
	"v",
	"tick",
	"ph",
	"pt_ms",
	"gate[]",
	"nb",
	"gl",
	"pk[]",
	"w",
	"r[][]",
	"tw[][]",
	"e[][]",
	"z[][]",
	"f[][]",
	"f[][][]",
	"q",
	"ro[]",
	"ru[]",
	"ib",
	"gd[]",
	"gt[]",
]


## "" when `snap` has every key with the right row widths, else the first problem.
static func check(snap: Dictionary) -> String:
	for k: String in KEYS:
		if not snap.has(k):
			return "missing %s" % k
	for spec: Array in [["r", R_LEN], ["tw", TW_LEN], ["e", E_LEN], ["z", Z_LEN]]:
		for row: Variant in snap[spec[0]]:
			if not (row is Array) or (row as Array).size() != int(spec[1]):
				return "%s: a row needs %d columns" % [spec[0], int(spec[1])]
	if not (snap["gate"] is Array) or (snap["gate"] as Array).size() != 3:
		return "gate needs [hp, max, breach_ms]"
	return ""


## The snapshot's size as the platform measures it (UTF-8 bytes of JSON.stringify).
static func byte_size(snap: Dictionary) -> int:
	return JSON.stringify(snap).to_utf8_buffer().size()

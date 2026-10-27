class_name TankSnapshotSchema
extends RefCounted
## The 10 Hz snapshot layout (brief 2.6; G0 contract): full state as compact integer arrays, at most
## 4 KB of JSON at the caps (16 enemies, 24 shells). TankSnapshot (net/, module) encodes and
## applies it; this file pins the keys, the row columns, the flag bits and the int paths.
## Units on the wire: positions in art px (dpx = 0.1 px), times in ms, speeds in cm/s, grades,
## angles and % targets in 0.1 units (x10), shares 0..1 in thousandths (x1000, "pml"), HP rounded
## up (ceil) so a living target never shows 0.
##
## v2 (VERSION 2) added, at the ends of their rows: tk dir, r target_x10, e lane, and the arc room's
## row; the r flags R_CAN_EVADE and R_SPRINTING. v1's Ram columns (tk stall_ms, the diesel's and the
## Bulwark's ram_ms / ram_cd_ms / dodge_ms) and the STF_PROMPT bit are reserved: always 0 (brief 2.4).
##
## {"v": 2, "tick": n,
##  "sg": [seg code, stage, phase index, elapsed_ms, flags SG_*],
##  "tk": [tank code, x_dpx, speed_cms, grade_x10, hp, hp_max, berm, 0 (reserved), repair_hj,
##         facing, elev_x10, traverse_ms, loaded shell, breech_ms, target id, flags TK_*,
##         dir (TankIds.DIR_*: 1 right, -1 left)],
##  "r":  [[slot, engine code, raw_w, cadence_rpm, ftp_pct, flags R_*, target_x10], ...]  slot order
##  "st": [[engine code, slot, flags ST_* (+ engine bits), a, b, c, d, e], ...]  rooms rear to front
##        diesel:  a 0, b 0, c 0, d 0, e 0 (a-c reserved)
##        dynamo:  a bank_x10, b hoist_ms, c 0, d 0, e 0
##        steam:   a pressure_x10, b window_ms, c over_ms, d 0, e 0
##        bulwark: a 0, b 0 (reserved), c lever + 4 x lever_to, d move_ms, e hoist_j / 10
##        arc:     a duty_pml (duty x 1000), b 0, c 0, d 0, e 0
##  "e":  [[id, enemy code, x_dpx, hp, mode EM_*, side, telegraph_ms, lane], ...]  live enemies, spawn order
##  "s":  [[id, shell type, x, y, vx, vy, friendly 0/1], ...]   shells in flight (px, px/s)
##  "o":  [[id, obstacle code, x_px, light_hits, cleared 0/1], ...]
##  "gl": [active 0/1, guns_total, guns_left, barrage 0/1],
##  "b":  [boss phase, x_dpx, bogie hp x3, turret hp, telegraph_ms]   (all 0 without a boss)
##  "sc": [breakdowns, overruns, behemoth killed 0/1, crew kills]}

const VERSION := 2
const MAX_BYTES := TankConst.SNAPSHOT_MAX_BYTES
const KEYS: Array[String] = ["v", "tick", "sg", "tk", "r", "st", "e", "s", "o", "gl", "b", "sc"]

# sg columns and flags
const SG_SEG := 0
const SG_STAGE := 1
const SG_PHASE := 2
const SG_ELAPSED_MS := 3
const SG_FLAGS := 4
const SG_LEN := 5
const SGF_OBJECTIVE := 1
const SGF_REGROUP := 2
const SGF_OVERRUN := 4

# tk columns and flags
const TK_CODE := 0
const TK_X_DPX := 1
const TK_SPEED_CMS := 2
const TK_GRADE_X10 := 3
const TK_HP := 4
const TK_HP_MAX := 5
const TK_BERM := 6
## Reserved (v1's failed-Ram stall): always 0.
const TK_STALL_MS := 7
const TK_REPAIR_HJ := 8
const TK_FACING := 9
const TK_ELEV_X10 := 10
const TK_TRAVERSE_MS := 11
const TK_LOADED := 12
const TK_BREECH_MS := 13
const TK_TARGET := 14
const TK_FLAGS := 15
## v2: TankHullState.dir.
const TK_DIR := 16
const TK_LEN := 17
const TKF_HOLDING := 1
const TKF_EVASIVE := 2
const TKF_TRAPS_CLEARED := 4
const TKF_BLOCKED := 8
const TKF_BREAKDOWN := 16

# r columns and flags
const R_SLOT := 0
const R_ENGINE := 1
const R_RAW_W := 2
const R_CADENCE := 3
const R_FTP_PCT := 4
const R_FLAGS := 5
## v2: TankRiderState.target_pct x 10.
const R_TARGET_X10 := 6
const R_LEN := 7
const RF_IN_BAND := 1
const RF_RESCUE := 2
const RF_AFK := 4
const RF_CONNECTED := 8
## v2: TankRiderState.can_evade and sprinting.
const RF_CAN_EVADE := 16
const RF_SPRINTING := 32

# st columns; flags shared by every room, then per engine
const ST_ENGINE := 0
const ST_SLOT := 1
const ST_FLAGS := 2
const ST_A := 3
const ST_B := 4
const ST_C := 5
const ST_D := 6
const ST_E := 7
const ST_LEN := 8
const STF_IN_BAND := 1
const STF_RESERVE := 2
const STF_UNPOWERED := 4
## diesel and bulwark
const STF_SPRINTING := 8
## Reserved (v1's Ram prompt): never set.
const STF_PROMPT := 16
## bulwark
const STF_AUTO := 32
## dynamo
const STF_STALLED := 8
const STF_STABILIZING := 16
## steam
const STF_OVER := 8
const STF_LOADED := 16
const STF_CYCLING := 32
const STF_STEAM_SPRINTING := 64
## arc (v2)
const STF_LIT := 8
const STF_ARC_STALLED := 16

# e columns
const E_ID := 0
const E_CODE := 1
const E_X_DPX := 2
const E_HP := 3
const E_MODE := 4
const E_SIDE := 5
const E_TELEGRAPH_MS := 6
## v2: TankEnemyState.lane.
const E_LANE := 7
const E_LEN := 8

# s columns
const S_ID := 0
const S_TYPE := 1
const S_X := 2
const S_Y := 3
const S_VX := 4
const S_VY := 5
const S_FRIENDLY := 6
const S_LEN := 7

# o columns
const O_ID := 0
const O_CODE := 1
const O_X := 2
const O_LIGHT_HITS := 3
const O_CLEARED := 4
const O_LEN := 5

# gl columns
const GL_ACTIVE := 0
const GL_TOTAL := 1
const GL_LEFT := 2
const GL_BARRAGE := 3
const GL_LEN := 4

# b columns
const B_PHASE := 0
const B_X_DPX := 1
const B_BOGIE_0 := 2
const B_TURRET := 5
const B_TELEGRAPH_MS := 6
const B_LEN := 7

# sc columns
const SC_BREAKDOWNS := 0
const SC_OVERRUNS := 1
const SC_BEHEMOTH := 2
const SC_CREW_KILLS := 3
const SC_LEN := 4

## int_fields()["snapshot"] (GAME_SDK 12): every number in the snapshot.
const INT_PATHS: Array[String] = [
	"v",
	"tick",
	"sg[]",
	"tk[]",
	"r[][]",
	"st[][]",
	"e[][]",
	"s[][]",
	"o[][]",
	"gl[]",
	"b[]",
	"sc[]",
]


## "" when `snap` has every key with the right row widths, else the first problem.
static func check(snap: Dictionary) -> String:
	for k: String in KEYS:
		if not snap.has(k):
			return "missing %s" % k
	for spec: Array in [
		["sg", SG_LEN], ["tk", TK_LEN], ["gl", GL_LEN], ["b", B_LEN], ["sc", SC_LEN]
	]:
		if not (snap[spec[0]] is Array) or (snap[spec[0]] as Array).size() != int(spec[1]):
			return "%s needs %d columns" % [spec[0], int(spec[1])]
	for spec: Array in [["r", R_LEN], ["st", ST_LEN], ["e", E_LEN], ["s", S_LEN], ["o", O_LEN]]:
		if not (snap[spec[0]] is Array):
			return "%s must be an array of rows" % spec[0]
		for row: Variant in snap[spec[0]]:
			if not (row is Array) or (row as Array).size() != int(spec[1]):
				return "%s: a row needs %d columns" % [spec[0], int(spec[1])]
	if (snap["e"] as Array).size() > TankConst.MAX_ENEMIES:
		return "e: more than %d enemies" % TankConst.MAX_ENEMIES
	if (snap["s"] as Array).size() > TankConst.MAX_SHELLS:
		return "s: more than %d shells" % TankConst.MAX_SHELLS
	return ""


## The snapshot's size as the platform measures it (UTF-8 bytes of JSON.stringify).
static func byte_size(snap: Dictionary) -> int:
	return JSON.stringify(snap).to_utf8_buffer().size()


## Float -> wire int helpers (rounded; HP uses ceil so a living target never shows 0).
static func ms(seconds: float) -> int:
	return roundi(seconds * 1000.0)


static func x10(v: float) -> int:
	return roundi(v * 10.0)


## A share 0..1 in thousandths.
static func pml(v: float) -> int:
	return roundi(v * 1000.0)


static func hp(v: float) -> int:
	return ceili(maxf(v, 0.0) - 0.0001)

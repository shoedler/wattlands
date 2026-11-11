class_name SiegeSnapshotSchema
extends RefCounted
## The 10 Hz snapshot layout, brief 2.6 (v2). All numbers are ints; positions in decimetres,
## times in milliseconds, angles in centidegrees, fractions in per mille; at most 8 KB of JSON at
## the 150-enemy cap. SiegeSnapshot (net/) encodes and applies it; this file pins the keys, the
## row columns and the int paths.
##
## {"v": 2, "tick": n, "ph": phase index, "pt_ms": phase elapsed ms,
##  "gate": [hp (ceil), max, breach_ms], "nb": breaches, "ib": iron bands, "ml": mine level,
##  "pk": [perk codes], "w": team raw watts (1 s mean),
##  "r": [[slot, target, reconnect_ms, od_ms, od_cd_ms, gold (floor), p_eff_w, raw_w,
##         cadence_rpm, rescue 0/1, afk 0/1, connected 0/1, shop_fallback 0/1], ...]   one row
##         per slot, slot order (the last two are additive: ADR "snapshot rider flags")
##  "st": [[station, level, wind_pm, yaw_cdeg, m_x100, arm_pm], ...]   all five, id order
##  "pd": [[pad, type, level, cd_ms, yaw_cdeg], ...]   built pads only, pad order
##  "tar": [cauldron_dl, curtain_dhp, coat_pm, boarded 0/1]
##  "e": [[id, type, prog_dm, lat_dm, hp (ceil), st], ...]   live enemies, spawn order
##  "q": queued spawns, "gd": gate damage this wave in 0.1 HP,
##  "dw": [[station, damage], ...]   each weapon's damage in the current or last wave}
## Optional keys (additive, present only when not at their default, so the common snapshot is the
## brief's):
##  "ru": [1, i, left_ms]   a rush is on (index i, time left), absent otherwise
##  "rn": n   the index of the next rush (rushes_at_s), absent at 0
##  "rk": n   the arrow organ's next rack, absent at 0
##  "rc": [[item, at, lvl, cost, slot, no_slot...], ...]   the shared receipt in the order the items
##        were added, absent when empty: item is SiegeIds.item_code (1..9), at the station or pad (0
##        otherwise), lvl the level an upgrade, mine level or pad upgrade line buys (0 otherwise),
##        cost the gold held, slot the picker, then the slots that voted no in slot order
##        (TeamVote.no_voters); a row is at least RC_NO columns wide and as wide as its votes
## od_ms is the Overdrive time left (0 unless ACTIVE), od_cd_ms the cooldown left (0 unless
## COOLDOWN); a client derives od_state from them (od_ms > 0 ACTIVE, od_cd_ms > 0 COOLDOWN, else
## READY).

const VERSION := 2
## Brief 2.6 cap at 150 enemies (the relay's limit is 16 384).
const MAX_BYTES := 8192
const KEYS: Array[String] = [
	"v",
	"tick",
	"ph",
	"pt_ms",
	"gate",
	"nb",
	"ib",
	"ml",
	"pk",
	"w",
	"r",
	"st",
	"pd",
	"tar",
	"e",
	"q",
	"gd",
	"dw",
]
## Optional keys (see above); check() does not require them.
const OPTIONAL_KEYS: Array[String] = ["ru", "rk", "rn", "rc"]
# ru columns
const RU_ON := 0
const RU_INDEX := 1
const RU_LEFT_MS := 2

# rc row columns (the no votes follow the fourth)
const RC_ITEM := 0
const RC_AT := 1
const RC_LVL := 2
const RC_COST := 3
const RC_SLOT := 4
const RC_NO := 5

# r row columns
const R_SLOT := 0
const R_TARGET := 1
const R_RECONNECT_MS := 2
const R_OD_MS := 3
const R_OD_CD_MS := 4
const R_GOLD := 5
const R_P_EFF_W := 6
const R_RAW_W := 7
const R_CADENCE := 8
const R_RESCUE := 9
const R_AFK := 10
const R_CONNECTED := 11
const R_SHOP_FALLBACK := 12
const R_LEN := 13
## The brief's row before the additive flags (an older row still applies).
const R_LEN_BRIEF := 11
# st row columns
const ST_ID := 0
const ST_LEVEL := 1
const ST_WIND_PM := 2
const ST_YAW_CDEG := 3
const ST_M_X100 := 4
const ST_ARM_PM := 5
const ST_LEN := 6
# pd row columns
const PD_PAD := 0
const PD_TYPE := 1
const PD_LEVEL := 2
const PD_CD_MS := 3
const PD_YAW_CDEG := 4
const PD_LEN := 5
# tar columns
const TAR_CAULDRON_DL := 0
const TAR_CURTAIN_DHP := 1
const TAR_COAT_PM := 2
const TAR_BOARDED := 3
const TAR_LEN := 4
# e row columns
const E_ID := 0
const E_TYPE := 1
const E_PROG_DM := 2
const E_LAT_DM := 3
const E_HP := 4
const E_ST := 5
const E_LEN := 6
# dw row columns
const DW_STATION := 0
const DW_DAMAGE := 1
const DW_LEN := 2
# gate columns
const G_HP := 0
const G_MAX := 1
const G_BREACH_MS := 2

## int_fields()["snapshot"] (GAME_SDK 12).
const INT_PATHS: Array[String] = [
	"v",
	"tick",
	"ph",
	"pt_ms",
	"gate[]",
	"nb",
	"ib",
	"ml",
	"pk[]",
	"w",
	"r[][]",
	"st[][]",
	"pd[][]",
	"tar[]",
	"e[][]",
	"q",
	"gd",
	"dw[][]",
	"ru[]",
	"rk",
	"rn",
	"rc[][]",
]


## "" when `snap` has every key with the right row widths, else the first problem.
static func check(snap: Dictionary) -> String:
	for k: String in KEYS:
		if not snap.has(k):
			return "missing %s" % k
	if int(snap["v"]) != VERSION:
		return "v must be %d" % VERSION
	for spec: Array in [["r", R_LEN], ["st", ST_LEN], ["pd", PD_LEN], ["e", E_LEN], ["dw", DW_LEN]]:
		if not (snap[spec[0]] is Array):
			return "%s must be a list" % spec[0]
		for row: Variant in snap[spec[0]]:
			if not (row is Array) or (row as Array).size() != int(spec[1]):
				return "%s: a row needs %d columns" % [spec[0], int(spec[1])]
	if (snap["st"] as Array).size() != SiegeIds.STATION_COUNT:
		return "st needs one row per station"
	if not (snap["gate"] is Array) or (snap["gate"] as Array).size() != 3:
		return "gate needs [hp, max, breach_ms]"
	if not (snap["tar"] is Array) or (snap["tar"] as Array).size() != TAR_LEN:
		return "tar needs [cauldron_dl, curtain_dhp, coat_pm, boarded]"
	return ""


## The snapshot's size as the platform measures it (UTF-8 bytes of JSON.stringify).
static func byte_size(snap: Dictionary) -> int:
	return JSON.stringify(snap).to_utf8_buffer().size()

class_name FishingSnapshotSchema
extends RefCounted
## The 10 Hz snapshot layout (brief 2.6; G0 contract). All numbers are ints; at most 2 KB of
## JSON for 4 lanes (FishingConst.SNAPSHOT_MAX_BYTES). FishingSnapshot (net/) encodes and applies
## it; this file pins the keys, the lane columns and the int paths.
##
## {"v": 1, "k": tick,
##  "L": [lane row, ...]   one row per slot, slot order (columns below),
##  "T": [team points, team fish, hookup level, trip_over 0/1, fishing seconds left (ceil)],
##  "C": [[lane, species, grade], ...]   the catch board, newest last, <= 5}
##
## Lane row columns (L_*):
##  slot, phase index, state (FishingConst.ST_*), species (-1 none), d (dm), z (permille),
##  S, strain, slack, gaff (each 0-255), band lo, band hi (rpm; 0 0 = no band), raw power (W),
##  EMA cadence (rpm), selected hint (-1 none), lure distance (dm), flags (F_* bits),
##  cosmetics [line, canopy, trim, pennant], hints [[type, d (dm), strength 0-255], ...] (only
##  while picking, else []), state timer (ds: seconds in the lane state x 10), lane points,
##  fish landed

const VERSION := 1
const KEYS: Array[String] = ["v", "k", "L", "T", "C"]

const L_SLOT := 0
const L_PHASE := 1
const L_STATE := 2
const L_SPECIES := 3
const L_D_DM := 4
const L_Z_PM := 5
const L_S := 6
const L_STRAIN := 7
const L_SLACK := 8
const L_GAFF := 9
const L_BAND_LO := 10
const L_BAND_HI := 11
const L_POWER_W := 12
const L_CADENCE := 13
const L_SELECTED := 14
const L_LURE_DM := 15
const L_FLAGS := 16
const L_COSMETICS := 17
const L_HINTS := 18
const L_STATE_DS := 19
const L_POINTS := 20
const L_LANDED := 21
const L_COLUMNS := 22

const T_POINTS := 0
const T_FISH := 1
const T_HOOKUP := 2
const T_TRIP_OVER := 3
const T_TIME_LEFT_S := 4

const F_RESCUE := 1
const F_AFK := 2
const F_RUN := 4  ## a run or a jump is on
const F_JUMP := 8  ## the active run is a jump
const F_REPLACEMENT := 16
const F_TROPHY := 32  ## the gaff meter filled (Landing)
const F_STALE := 64  ## the lane's cadence or telemetry is stale
const F_FRENZY := 128
const F_OFF_LINE := 256  ## between a loss and the replacement
const F_FALLBACK := 512  ## the lane plays as Autopilot (Autopilot on or zero-input fallback)

## Protocol.decode() paths (GameModule.int_fields "snapshot").
const INT_PATHS: Array[String] = ["v", "k", "L[][]", "L[][][]", "L[][][][]", "T[]", "C[][]"]


## A unit (0..1) as 0..255.
static func u8(x: float) -> int:
	return clampi(roundi(x * 255.0), 0, 255)


## 0..255 back to a unit.
static func unit(v: Variant) -> float:
	return clampf(float(v) / 255.0, 0.0, 1.0)


## "" when `snap` has every key and well-formed lane rows, else the problem.
static func check(snap: Dictionary) -> String:
	for k in KEYS:
		if not snap.has(k):
			return "missing %s" % k
	if int(snap["v"]) != VERSION:
		return "version %s" % snap["v"]
	if not snap["L"] is Array:
		return "L is not an array"
	for row: Variant in snap["L"]:
		if not row is Array or (row as Array).size() != L_COLUMNS:
			return "a lane row needs %d columns" % L_COLUMNS
		if not row[L_COSMETICS] is Array or not row[L_HINTS] is Array:
			return "lane cosmetics and hints are arrays"
	if not snap["T"] is Array or (snap["T"] as Array).size() != 5:
		return "T needs 5 values"
	if not snap["C"] is Array or (snap["C"] as Array).size() > FishingConst.CATCH_BOARD:
		return "C holds at most 5 catches"
	return ""

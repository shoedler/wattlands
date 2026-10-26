class_name FishingSnapshotSchema
extends RefCounted
## The 10 Hz snapshot layout, version 2 (contract; additive changes only). Every number is an
## int; at most 2 KB of JSON for 4 riders (FishingConst.SNAPSHOT_MAX_BYTES). FishingSnapshot
## (net/) encodes and applies it; this file pins the keys, the columns and the int paths.
##
## {"v": 2, "k": tick,
##  "R": [rider row, ...]   one row per slot, slot order (columns R_* below),
##  "T": [mode, time left, over, team points, team fish, hookup level]   (T_* below),
##  "C": [[slot, species, kg x 10, trophy 0/1], ...]   the latest catches, newest last, <= 5}
##
## Rider row columns (R_*). Distances in decimetres (dm), x along the map from the dock (x 0)
## out to sea; "dx" is a world-x offset from the boat (+ = seaward), depths are metres below the
## surface x 10 (dm, positive down):
##  R_SLOT          slot index
##  R_X_DM          boat x
##  R_HEADING       +1 out to sea, -1 back toward the dock (the bow's direction)
##  R_SPEED_CMS     boat speed in cm/s, signed (+ = seaward)
##  R_PITCH_DD      signed pitch in 0.1 degrees (FishingConst.TRIM_MIN_DEG..TRIM_MAX_DEG: -60..140),
##                  FishingBoat's rigid-body pitch: + bow up (thrust moment, the displacement
##                  hump, a fish pulling the stern down; a surge kicks it up, then it settles;
##                  on the plane the hull flattens), - bow down (braking: drag with no thrust digs
##                  the bow in and lifts the stern; back to level as the boat slows)
##  R_WAKE          wake and spray intensity 0..255 (speed and thrust)
##  R_THROTTLE      P_eff as % of FTP-equivalent (250 W of P_eff = 100), 0..255
##  R_ACTION        FishingConst.A_DRIVE .. A_HOME (display_action() adds A_PAUSED / A_AFK)
##  R_SELECTED      the highlighted menu entry (index into R_MENU), -1 none
##  R_MENU          menu entries while in A_MENU, else []: 0..2 cast at hint i (R_HINTS[i]),
##                  FishingConst.M_DRIVE_ON, FishingConst.M_TURN
##  R_SPECIES       the fish on the line (A_FIGHT, A_LAND) or being fished for (A_CAST,
##                  A_WAIT in Free Roam); -1 none
##  R_FISH_DX_DM    the fish's dx (fight: behind the stern, sign = -heading)
##  R_FISH_DEPTH_DM the fish's depth
##  R_LURE_DX_DM    the wobbler's dx (0 when the line is in)
##  R_LURE_DEPTH_DM the wobbler's depth (0 at the surface or reeled in)
##  R_LINE_DM       line paid out (0 = reeled in)
##  R_STRAIN, R_SLACK, R_GAFF, R_STAMINA   fight meters 0..255 (stamina S: 255 fresh, 0 spent)
##  R_BAND_LO, R_BAND_HI   the published cadence band in rpm (0 0 = none)
##  R_POWER_W       raw power (W), R_CADENCE: EMA cadence (rpm)
##  R_FLAGS         F_* bits below
##  R_POINTS        the rider's points, R_LANDED: fish landed
##  R_COSMETICS     [line, canopy, trim, pennant] cosmetics.json indexes (0 = default look)
##  R_HINTS         [[species, dx_dm, depth_dm, size 0..255], ...] while in A_MENU, else []:
##                  the fish this spot offers (size = the hint's w: 0 smallest .. 255 largest)
##  R_STATE_DS      seconds in the current action x 10
##  R_FURTHEST_DM   the farthest x this rider reached
##  R_BRAKE         braking intensity 0..255 (the boat's deceleration, 255 at
##                  FishingConst.BRAKE_FULL_MPS2 or more): bow foam, collapsing wake
##  R_HEAVE_CM      the hull's heave in cm, signed (+ the hull rides higher on the water than at
##                  rest: lifted onto the plane; - lower: squat at the hump, a fish pulling the
##                  stern down). The view offsets the hull by heave and pitch about the hull's
##                  centre (FishingConst.STERN_ARM_M from the transom).
##  R_PLANE         planing level 0..255 (0 displacement, 255 fully on the plane): the hull
##                  flattens and rides up, drag drops; hysteresis keeps it from flickering
##  R_TOW           line tension 0..255 (255 = FishingConst.TOW_MAX_N), 0 with no fish on. The
##                  force acts along the line, from the stern toward the fish (R_FISH_DX_DM,
##                  R_FISH_DEPTH_DM): its horizontal part tows the boat backward toward the fish,
##                  its vertical part pulls the stern down
##  R_PROP_CM       the prop's depth below the surface at the transom in cm, always at least
##                  FishingConst.PROP_MIN_M x 100 (the prop never leaves the water: the stern
##                  squats while the bow rises; on the plane the transom stays at the waterline)
##  R_REEL          reel-in progress 0..255 in a fight or landing: 1 - line / full line, where the
##                  line is R_LINE_DM (hypot(d, depth), the distance number) and the full line
##                  hypot(d_max, hook depth); 0 else. Runs pull it down, the landing ends at 255
##
## T columns: T_MODE (0 Free Roam, 1 workout), T_TIME_LEFT_S (seconds of play left, ceil; 0 in
## overtime), T_OVER (1 once time is up: no new bites, fights may finish), T_POINTS, T_FISH (team
## totals), T_HOOKUP (fights on right now; workouts score overlaps).

const VERSION := 2
const KEYS: Array[String] = ["v", "k", "R", "T", "C"]

const R_SLOT := 0
const R_X_DM := 1
const R_HEADING := 2
const R_SPEED_CMS := 3
const R_PITCH_DD := 4
const R_WAKE := 5
const R_THROTTLE := 6
const R_ACTION := 7
const R_SELECTED := 8
const R_MENU := 9
const R_SPECIES := 10
const R_FISH_DX_DM := 11
const R_FISH_DEPTH_DM := 12
const R_LURE_DX_DM := 13
const R_LURE_DEPTH_DM := 14
const R_LINE_DM := 15
const R_STRAIN := 16
const R_SLACK := 17
const R_GAFF := 18
const R_STAMINA := 19
const R_BAND_LO := 20
const R_BAND_HI := 21
const R_POWER_W := 22
const R_CADENCE := 23
const R_FLAGS := 24
const R_POINTS := 25
const R_LANDED := 26
const R_COSMETICS := 27
const R_HINTS := 28
const R_STATE_DS := 29
const R_FURTHEST_DM := 30
const R_BRAKE := 31
const R_HEAVE_CM := 32
const R_PLANE := 33
const R_TOW := 34
const R_PROP_CM := 35
const R_REEL := 36
const R_COLUMNS := 37

## Hint entry columns (R_HINTS rows).
const H_SPECIES := 0
const H_DX_DM := 1
const H_DEPTH_DM := 2
const H_SIZE := 3

const T_MODE := 0
const T_TIME_LEFT_S := 1
const T_OVER := 2
const T_POINTS := 3
const T_FISH := 4
const T_HOOKUP := 5
const T_COLUMNS := 6
const MODE_ROAM := 0
const MODE_WORKOUT := 1

## Catch board entry columns.
const C_SLOT := 0
const C_SPECIES := 1
const C_KG10 := 2
const C_TROPHY := 3

const F_RESCUE := 1  ## the governor's rescue hold
const F_AFK := 2  ## AFK (multiplayer coasting, a dropped peer, or stale telemetry)
const F_STALE := 4  ## cadence or telemetry is stale
const F_PAUSED := 8  ## the platform paused this rider (10 s without pedaling): the boat drifts
const F_SPRINT := 16  ## P_eff > 105 % FTP-equivalent (wake icon)
const F_RUN := 32  ## a run or a jump is on
const F_JUMP := 64  ## the active run is a jump (the fish is at the surface)
const F_TROPHY := 128  ## the gaff meter filled (Landing)
const F_REPLACEMENT := 256  ## a same-species replacement after a lost fish
const F_OFF_LINE := 512  ## between a loss and the replacement
const F_AUTO := 1024  ## Autopilot plays this rider's choices (Autopilot on, or a bot)
const F_PEDAL_NAV := 2048  ## the menu scans and auto-confirms (PlayerSlot.pedal_nav)
const F_WARMUP := 4096  ## the drive-out warm-up: the fish do not bite yet
const F_BOT := 8192  ## a bot rider
## A big fish's surge (FishingConst.SURGE_S after a run starts, fish >= SURGE_KG): rod jerks,
## line snaps taut. The rules requested an ERG haptic_pull when the rider allows haptics.
const F_SURGE := 16384

## Protocol.decode() paths (GameModule.int_fields "snapshot").
const INT_PATHS: Array[String] = ["v", "k", "R[][]", "R[][][]", "R[][][][]", "T[]", "C[][]"]


## A unit (0..1) as 0..255.
static func u8(x: float) -> int:
	return clampi(roundi(x * 255.0), 0, 255)


## 0..255 back to a unit.
static func unit(v: Variant) -> float:
	return clampf(float(v) / 255.0, 0.0, 1.0)


## The action to show for a rider row: A_AFK or A_PAUSED when flagged, else R_ACTION.
static func display_action(row: Array) -> int:
	var flags := int(row[R_FLAGS])
	if flags & F_AFK:
		return FishingConst.A_AFK
	if flags & F_PAUSED:
		return FishingConst.A_PAUSED
	return int(row[R_ACTION])


## "" when `snap` has every key and well-formed rows, else the problem.
static func check(snap: Dictionary) -> String:
	for k in KEYS:
		if not snap.has(k):
			return "missing %s" % k
	if int(snap["v"]) != VERSION:
		return "version %s" % snap["v"]
	if not snap["R"] is Array:
		return "R is not an array"
	for row: Variant in snap["R"]:
		if not row is Array or (row as Array).size() != R_COLUMNS:
			return "a rider row needs %d columns" % R_COLUMNS
		if not row[R_COSMETICS] is Array or not row[R_HINTS] is Array or not row[R_MENU] is Array:
			return "rider cosmetics, menu and hints are arrays"
	if not snap["T"] is Array or (snap["T"] as Array).size() != T_COLUMNS:
		return "T needs %d values" % T_COLUMNS
	if not snap["C"] is Array or (snap["C"] as Array).size() > FishingConst.CATCH_BOARD:
		return "C holds at most 5 catches"
	return ""

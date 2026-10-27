class_name FishingWhitewater
extends RefCounted
## A boat's water (mockups E4 and E7) as chunky whitewater lumps on the art grid: each lump a
## lit top plane (foam) over a face plane (sky) with a surface-teal shadow seam under the big
## ones, corners cut (clump()); farther ones a palette step paler. What shows follows the boat
## physics (FishingRiderState: speed, planing level, line tow, braking) through a level with
## hysteresis (level()):
##  - IDLE (barely moving): two foam sheets at the transom and the stem;
##  - CRUISE (about 50 % FTP): a mound behind and onto the stern quarter, a bow wave;
##  - HUMP (near the hump speed or climbing onto the plane: the stern squats, the bow is up): a
##    big boiling mound that buries the transom to the deck, a spray sheet ramping up from the
##    wet forefoot, no rooster tail yet;
##  - PLANE (fully on the plane: the hull flat and up): the mound hides the leg and the transom,
##    a rooster tail arches back over a curtain falling into the wake and breaks up toward its
##    far end, only a low sheet peels off the wet aft third;
##  - towed by a fish: a mound piled against the transom, a short reverse wake off the bow on
##    the waterline;
##  - braking: a mound pushed ahead of the bow, a churn behind the stern.
## Behind the boats (paint_behind): the far arm of the V wake, crests climbing a few rows into
## the far water, and the aerated prop wash under the surface. In front (paint_front): the centre
## wake, the mounds, the rooster tail, the bow water. The wake's lumps live in the water: each
## spawns at the transom every SPACING px of the boat's travel (`odo`, the view's odometer per
## boat), drifts back as the boat moves on, shrinks a step every SPACING px and fades a palette
## step before it goes, so a frame is a pure function of the travel and the time (no flicker).
## The mound's lumps boil: each grows a row now and then on a slow beat from its own seed.
## Coordinates in the tables are art px in a bow-right frame: x from the transom (T), the stem
## (B) or the forefoot (F), dy the lump's top above the surface row.

enum { NONE, IDLE, CRUISE, HUMP, PLANE }

## Speed (m/s) from which each level shows, and the margin a level holds past its edge.
const IDLE_MPS := 0.5
const CRUISE_MPS := 4.0
const HUMP_MPS := 10.5
const HOLD_MPS := 0.5
## On the plane from this planing level (FishingRiderState.plane), climbing onto it (the hump:
## the stern squats, no rooster tail yet) from CLIMB_AT; towed from this share of the line's
## most tension (FishingConst.TOW_MAX_N).
const PLANE_AT := 0.95
const CLIMB_AT := 0.05
const TOW_AT := 0.3
## The wake's spacing (px of travel) and the mound's boil beat (Hz).
const SPACING := 12.0
const BOIL_HZ := 2.5
## Per level (CRUISE, HUMP, PLANE): the centre wake [start behind T, lumps, first width], the
## far V arm [start behind T, crests, first width, rows per climb step], the prop wash under the
## surface ([x from the prop, dy under the surface, w, h]) and the mound ([x from T, dy, w, h]).
const TRAIL := [[24, 6, 8], [40, 5, 10], [66, 4, 9]]
const ARM := [[10, 4, 7, 5], [12, 4, 9, 5], [14, 4, 10, 7]]
## The far arm's crests climb at most this many rows over the surface (they stay on the water).
const ARM_RISE := 6
const WASH := [
	[[-6, 3, 6, 2], [-16, 2, 8, 2]],
	[[-8, 4, 8, 3], [-20, 3, 12, 3], [-34, 1, 12, 2]],
	[[-8, 3, 10, 3], [-22, 2, 14, 3], [-40, 1, 14, 2]],
]
const MOUND := [
	[[-24, 3, 10, 4], [-16, 5, 12, 6], [-7, 7, 12, 8], [3, 3, 10, 4]],
	[
		[-38, 4, 12, 5],
		[-28, 7, 14, 8],
		[-16, 10, 14, 11],
		[-6, 9, 14, 10],
		[4, 8, 12, 9],
		[13, 5, 12, 6],
		[22, 3, 10, 4]
	],
	[[-30, 4, 18, 5], [-18, 8, 14, 9], [-8, 10, 12, 11], [2, 6, 12, 7], [12, 3, 10, 4]],
]
## The bow water: CRUISE from the stem, HUMP and PLANE from the forefoot (the front-most wet hull
## column); HUMP's last two are pale drops thrown ahead.
const BOW_CRUISE := [[-14, 2, 10, 3], [-7, 5, 9, 6], [1, 3, 6, 4]]
const BOW_HUMP := [[1, 4, 10, 5], [9, 6, 10, 7], [-8, 3, 10, 4], [18, 3, 7, 4]]
const BOW_HUMP_DROPS := [[24, 7, 4, 2], [22, 11, 3, 2]]
const BOW_PLANE := [[-8, 2, 10, 3], [2, 1, 6, 2]]
## The rooster tail on the plane, a thin fan of spray thrown back from the transom with the sky
## under it: [x from T, rows above the surface at its base, points, dx per point, rise, fall,
## first w, first h, last w, last h]; it peaks under ROOSTER_TOP rows (never over the horizon)
## and from BREAK of its length on it falls as a broken dotted edge of DROP-sized drops.
const ROOSTER_PLANE := [-6, 5, 16, -4, 2.4, 0.17, 8, 4, 5, 3]
const ROOSTER_TOP := 14
const BREAK := 0.55
const DROP := Vector2i(3, 2)
## The mounds and the wake scale with the rider's effective power (FishingRiderState.p_eff_w
## over FishingConst.P_EFF_REF_W): SCALE_LO at half of it, 1 at all of it, at most SCALE_HI.
const SCALE_LO := 0.8
const SCALE_HI := 1.25
## Towed: the mound against the transom, the water dragged under it and the reverse wake.
const TOW_MOUND := [
	[-36, 4, 12, 5],
	[-28, 8, 13, 9],
	[-18, 10, 14, 11],
	[-8, 10, 12, 11],
	[2, 8, 12, 9],
	[12, 4, 12, 5],
	[22, 2, 9, 3]
]
const TOW_UNDER := [[-16, 2, 10, 3], [-26, 1, 12, 2]]
## Braking: the mound ahead of the stem (x from B; the hard braking adds the last) and the churn
## behind the transom.
const BRAKE_BOW := [[-6, 3, 10, 4], [1, 5, 9, 6], [8, 3, 6, 4], [4, 8, 6, 3]]
const BRAKE_CHURN := [[-14, 2, 8, 3], [-26, 1, 10, 2]]
## The hull's lowest row (boat-local) and the row the waterline foam lies on.
const KEEL_ROW := 33

## Tests: with `recording` set, every rect is appended to `drawn` ([Rect2, Color]) instead of
## drawn (the canvas may be null).
static var recording: bool = false
static var drawn: Array = []

## slot -> the level shown (hysteresis).
var _level: Dictionary = {}


## The level for a boat at `v_mps` (signed), planing level `plane`, after `prev`: speeds hold a
## level HOLD_MPS past its edge.
static func level(v_mps: float, plane: float, prev: int = NONE) -> int:
	if plane >= PLANE_AT:
		return PLANE
	if plane >= CLIMB_AT:
		return HUMP
	var v := absf(v_mps)
	var edges: Array[float] = [IDLE_MPS, CRUISE_MPS, HUMP_MPS]
	var out := NONE
	for i in edges.size():
		var lv := IDLE + i
		var e := edges[i] - (HOLD_MPS if prev >= lv else 0.0)
		if v >= e:
			out = lv
	return out


## The level shown for `slot` this frame (kept for the hysteresis).
func level_of(slot: int, v_mps: float, plane: float) -> int:
	var lv := level(v_mps, plane, int(_level.get(slot, NONE)))
	_level[slot] = lv
	return lv


## A whitewater lump `w` x `h` with its top-left at (x, y): a lit `top` plane over a `face`
## plane, a `base` shadow seam under lumps 4 rows and taller (none when `base` is transparent),
## the corners cut on the grid.
static func clump(
	c: CanvasItem,
	x: float,
	y: float,
	w: int,
	h: int,
	top: Color = FishingPalette.FOAM,
	face: Color = FishingPalette.SKY,
	base: Color = FishingPalette.SURFACE
) -> void:
	var lit := maxi(1, (h * 3 + 4) / 5)
	for r in h:
		var inset := 0
		if r == 0 and h > 1:
			inset = 2 if w >= 7 and h >= 4 else (1 if w >= 5 else 0)
		elif r == 1 and h >= 5 and w >= 8:
			inset = 1
		elif r == h - 1 and h >= 3 and w >= 4:
			inset = 1
		var col := top if r < lit else face
		if base.a > 0.0 and h >= 4 and r >= h - maxi(1, h / 5):
			col = base
		if w - 2 * inset > 0:
			_rect(c, Rect2(x + float(inset), y + float(r), w - 2 * inset, 1), col)


static func _rect(c: CanvasItem, r: Rect2, col: Color) -> void:
	if recording:
		drawn.append([r, col])
	else:
		c.draw_rect(r, col)


## Where a boat's water is: {"T": transom x, "B": stem x, "F": forefoot x, "P": prop x (screen
## px), "sy": its surface row, "h": heading}. The forefoot is the front-most hull column still in
## the water in the pose and heave shown.
static func geometry(b: FishingBoatView) -> Dictionary:
	var h := b.heading if b.heading != 0 else 1
	var t := b.pixel_of(Vector2i(FishingRig.STERN_X, FishingRig.WATERLINE)).x
	var fwd := FishingRig.STERN_X
	for x in range(FishingRig.STERN_X, FishingRig.BOW_X + 1):
		if KEEL_ROW + FishingRig.tilt_dy(b.pose(), x) - b.heave_px > FishingRig.WATERLINE:
			fwd = x
	return {
		"T": t,
		"B": t + float(h * (FishingRig.BOW_X - FishingRig.STERN_X)),
		"F": t + float(h * (fwd - FishingRig.STERN_X)),
		"P": t + float(h * (int(FishingRig.PROP_AT.x) - FishingRig.STERN_X)),
		"sy": b.position.y,
		"h": h,
	}


## The far V arm and the prop wash for boat `b` (behind every hull). `s`: {"slot", "odo" (px of
## travel), "t" (s), "v" (m/s), "plane", "tow" (0..1), "brake" (0..2), "p" (effective power
## over FishingConst.P_EFF_REF_W)}.
func paint_behind(c: CanvasItem, b: FishingBoatView, s: Dictionary) -> void:
	var g := geometry(b)
	var lv := level_of(int(s["slot"]), float(s["v"]), float(s["plane"]))
	if float(s["tow"]) >= TOW_AT:
		if not b.far:
			for e: Array in TOW_UNDER:
				_lump(c, g, g["T"], e, -1, FishingPalette.SKY, FishingPalette.SKY, false, true)
		return
	if lv < CRUISE:
		return
	var i := lv - CRUISE
	_arm(c, g, float(s["odo"]), ARM[i], b.far)
	if b.far:
		return
	var gait := (floori(float(s["t"]) / 0.2) % 2) * 2
	var wash: Array = WASH[i]
	for k in wash.size():
		var e: Array = wash[k]
		var top := FishingPalette.FOAM if k == 0 else FishingPalette.SKY
		var moved := [int(e[0]) - gait, e[1], e[2], e[3]]
		_lump(c, g, g["P"], moved, -1, top, FishingPalette.SKY, false, true)


## The centre wake, the mounds, the rooster tail and the bow water for boat `b` (in front of
## it; a farther boat's go behind every hull, a step paler). `s` as for paint_behind().
func paint_front(c: CanvasItem, b: FishingBoatView, s: Dictionary) -> void:
	var g := geometry(b)
	var t := float(s["t"])
	var odo := float(s["odo"])
	var lv := level_of(int(s["slot"]), float(s["v"]), float(s["plane"]))
	var far := b.far
	var size := power_scale(float(s.get("p", 1.0)))
	if float(s["tow"]) >= TOW_AT:
		_reverse_wake(c, g, odo, far)
		_mound(c, g, TOW_MOUND, t, far, size)
		return
	if lv >= CRUISE:
		_trail(c, g, odo, TRAIL[lv - CRUISE], far)
	match lv:
		IDLE:
			_sheet(c, g, g["T"], -6, far)
			_sheet(c, g, g["B"], -2, far)
		CRUISE:
			_mound(c, g, MOUND[0], t, far, size)
		HUMP:
			_mound(c, g, MOUND[1], t, far, size)
		PLANE:
			_rooster(c, g, ROOSTER_PLANE, t, far)
			_mound(c, g, MOUND[2], t, far, size)
	var brake := int(s["brake"])
	if brake > 0:
		var n := BRAKE_BOW.size() if brake >= 2 else BRAKE_BOW.size() - 1
		for k in n:
			_lump(c, g, g["B"], BRAKE_BOW[k], k, FishingPalette.FOAM, FishingPalette.SKY, far)
		for e: Array in BRAKE_CHURN:
			_lump(c, g, g["T"], e, -1, FishingPalette.FOAM, FishingPalette.SKY, far)
		return
	match lv:
		CRUISE:
			for e: Array in BOW_CRUISE:
				_lump(c, g, g["B"], e, -1, FishingPalette.FOAM, FishingPalette.SKY, far)
		HUMP:
			for e: Array in BOW_HUMP:
				_lump(c, g, g["F"], e, -1, FishingPalette.FOAM, FishingPalette.SKY, far)
			for e: Array in BOW_HUMP_DROPS:
				_lump(c, g, g["F"], e, -1, FishingPalette.FOAM, FishingPalette.SKY, true)
		PLANE:
			for e: Array in BOW_PLANE:
				_lump(c, g, g["F"], e, -1, FishingPalette.FOAM, FishingPalette.SKY, far)


## Lump `e` ([x, dy, w, h] in the bow-right frame from `x0`; dy > 0 above the surface, a
## negative row index `under` puts its top dy rows under it instead) mirrored for the heading.
func _lump(
	c: CanvasItem,
	g: Dictionary,
	x0: float,
	e: Array,
	_seed: int,
	top: Color,
	face: Color,
	far: bool,
	under: bool = false
) -> void:
	var w := int(e[2])
	var hh := int(e[3])
	var x := int(e[0])
	var h := int(g["h"])
	var left := x0 + float(x) if h > 0 else x0 - float(x + w - 1)
	var sy := float(g["sy"])
	var y := sy + float(int(e[1])) if under else sy - float(int(e[1]))
	if far:
		clump(c, left, y, w, hh, FishingPalette.SKY, FishingPalette.HAZE, Color(0, 0, 0, 0))
	else:
		clump(c, left, y, w, hh, top, face)


## A 2-row foam sheet `x` px from `x0` (bow-right), 4 px long, on the surface line.
func _sheet(c: CanvasItem, g: Dictionary, x0: float, x: int, far: bool) -> void:
	var h := int(g["h"])
	var left := x0 + float(x) if h > 0 else x0 - float(x + 3)
	var sy := float(g["sy"])
	var top := FishingPalette.SKY if far else FishingPalette.FOAM
	var face := FishingPalette.HAZE if far else FishingPalette.SKY
	_rect(c, Rect2(left, sy - 1.0, 4, 1), top)
	_rect(c, Rect2(left, sy, 4, 1), face)


## The mound: `lumps` from the transom scaled by `size` (power_scale()), each boiling (a row
## taller) on its own slow beat.
func _mound(
	c: CanvasItem, g: Dictionary, lumps: Array, t: float, far: bool, size: float = 1.0
) -> void:
	var beat := floori(t * BOIL_HZ)
	for k in lumps.size():
		var e: Array = lumps[k]
		var up := 1 if posmod(beat + FishingScenery.hash2(k, 23) % 3, 3) == 0 else 0
		var x := roundi(float(int(e[0])) * size)
		var dy := roundi(float(int(e[1])) * size) + up
		var lump := [x, dy, roundi(float(int(e[2])) * size), roundi(float(int(e[3])) * size) + up]
		_lump(c, g, g["T"], lump, k, FishingPalette.FOAM, FishingPalette.SKY, far)


## The centre wake: lumps spawned every SPACING px of travel, drifting back from `cfg`[0] px
## behind the transom, a step smaller every SPACING px, the last one a step paler.
func _trail(c: CanvasItem, g: Dictionary, odo: float, cfg: Array, far: bool) -> void:
	var start := int(cfg[0])
	var count := int(cfg[1])
	var w0 := int(cfg[2])
	var n0 := floori(odo / SPACING)
	for j in count:
		var d := odo - float(n0 - j) * SPACING
		var k := floori(d / SPACING)
		if k >= count:
			continue
		var w := maxi(3, w0 - k)
		var hh := 3 if k < 3 else 2
		var back := start + floori(d) + FishingScenery.hash2(n0 - j, 31) % 3
		var lump := [-back - w, hh - 1, w, hh]
		_lump(c, g, g["T"], lump, j, FishingPalette.FOAM, FishingPalette.SKY, far or k == count - 1)


## The far arm of the V: crests spawned every SPACING px of travel from `cfg`[0] px behind the
## transom (ahead of the stem when negative: towed stern first), climbing a row per `cfg`[3] px
## toward the horizon, a step smaller as they go and paler past half way, gone at the horizon.
func _arm(c: CanvasItem, g: Dictionary, odo: float, cfg: Array, far: bool) -> void:
	var start := int(cfg[0])
	var count := int(cfg[1])
	var w0 := int(cfg[2])
	var slope := int(cfg[3])
	var n0 := floori(odo / SPACING)
	var h := int(g["h"])
	var sy := float(g["sy"])
	for j in count:
		var d := odo - float(n0 - j) * SPACING
		var k := floori(d / SPACING)
		if k >= count:
			continue
		var w := maxi(3, w0 - k)
		var y := sy - 2.0 - minf(floorf(d / float(slope)), float(ARM_RISE))
		var pale := far or k >= count / 2
		var x := -start - floori(d) - w if start >= 0 else -start + floori(d)
		var left := float(g["T"]) + float(x) if h > 0 else float(g["T"]) - float(x + w - 1)
		var top := FishingPalette.SKY if pale else FishingPalette.FOAM
		var face := FishingPalette.HAZE if pale else FishingPalette.SKY
		clump(c, left, y, w, 2, top, face, Color(0, 0, 0, 0))


## The reverse wake off the stem while a fish tows the boat stern first: crests streaming ahead
## of the bow, shrinking and flattening.
func _reverse_wake(c: CanvasItem, g: Dictionary, odo: float, far: bool) -> void:
	var n0 := floori(odo / SPACING)
	for j in 6:
		var d := odo - float(n0 - j) * SPACING
		var k := floori(d / SPACING)
		if k >= 6:
			continue
		var w := maxi(3, 9 - k)
		var hh := 3 if k < 3 else 2
		var lump := [-2 + floori(d), hh - 1, w, hh]
		_lump(c, g, g["B"], lump, j, FishingPalette.FOAM, FishingPalette.SKY, far or k >= 4)


## The rooster tail along a stepped parabola from the transom (`cfg`: ROOSTER_*): a band of
## foam lumps on haze faces (spray, not cloud), sky under it, drawn from its tip back to its base
## (joined to the mound); from BREAK of its length on it breaks into drops, every other one, the
## gaps walking back with time.
func _rooster(c: CanvasItem, g: Dictionary, cfg: Array, t: float, far: bool) -> void:
	var x0 := int(cfg[0])
	var base := int(cfg[1])
	var n := int(cfg[2])
	var dx := int(cfg[3])
	var rise := float(cfg[4])
	var fall := float(cfg[5])
	var gait := floori(t / 0.15) % 2
	for p in range(n - 1, -1, -1):
		var dy := mini(base + roundi(rise * float(p) - fall * float(p * p)), ROOSTER_TOP)
		if dy < 2:
			continue
		var u := float(p) / float(maxi(1, n - 1))
		var w := roundi(lerpf(float(cfg[6]), float(cfg[8]), u))
		var hh := mini(roundi(lerpf(float(cfg[7]), float(cfg[9]), u)), dy)
		var x := x0 + dx * p - w / 2
		if u >= BREAK:
			if (p + gait) % 2 == 1:
				continue
			w = DROP.x
			hh = DROP.y
		var lump := [x, dy, w, hh]
		if far:
			_lump(c, g, g["T"], lump, p, FishingPalette.SKY, FishingPalette.HAZE, true)
		else:
			_lump(c, g, g["T"], lump, p, FishingPalette.FOAM, FishingPalette.HAZE, false)


## The size factor for effective power share `p` (SCALE_LO .. SCALE_HI).
static func power_scale(p: float) -> float:
	return clampf(SCALE_LO + (1.0 - SCALE_LO) * (p - 0.5) / 0.5, SCALE_LO, SCALE_HI)

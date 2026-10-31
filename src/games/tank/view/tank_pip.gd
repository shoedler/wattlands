class_name TankPip
extends Node2D
## v4: the shell screen (SPEC_TANK 4.5): a little instrument docked on the seam that shows how a shell travels, in
## side profile, distance-compressed and height-stretched so an arc fills its box. The hull at range 0 and a mark per
## far enemy on the ground line, the target's bright, a shooter's red; the gun's arc to the target, faint, while
## nothing flies. A shell is a hot tracer with a bright trail: ours amber, with one predicted arc for the newest; theirs
## red, trail only, blinking while Surge can still make it miss; a flash where it leaves, a puff where it lands.
## The seconds the newest shell has left on the top near-side corner, the target's range on the other. With nothing
## to show it folds to a small dim tab; during a tow it is gone. Mirrored with the far panel (free roam, west); its text
## never mirrors. Pure view: it reads the snapshot's fields and never writes them.

const BEZEL := Color("#17140f")
const FRAME := Color("#6b5230")
const SCREEN := Color("#0a1412")
const SCAN := Color(0, 0, 0, 0.14)
const GROUND := Color("#35554c")
const GROUND_TICK := Color("#27403a")
const GROUND_TICK_M := 500.0
const OURS := Color("#f0b45a")
const THEIRS := Color("#e8502e")
const THEIRS_DIM := Color("#6e2616")
const CORE := Color("#fff4d8")
const AIM := Color(0.62, 0.78, 0.68, 0.34)
const MARK := Color("#6f8a7c")
const MARK_TARGET := Color("#e8dcc0")
const HULL := Color("#c2ab84")
const LABEL := Color("#a9c2b0")
const END_PAD := 10.0
const GROUND_ABOVE := 7.0
const FLOOR_ABOVE := 9.0
## Height: a square root's stretch, so 42 m at 1220 m uses 15 px of the box and 174 m at 2400 m stays inside it.
const UP_K := 2.35
## The folded tab with nothing to show, how fast it unfolds (s), how dim it sits.
const TAB := Vector2(52, 13)
const FOLD_S := 0.25
const TAB_ALPHA := 0.62
const DASH_EVERY := 6.0
const AIM_EVERY := 8.0
const BLINK_HZ := 5.0
const UNIT := "M"
const SECONDS := "S"
## The tracer's trail: samples back along the arc, a step (m) between them, how bright it starts.
const TRAIL_N := 16
const TRAIL_STEP_M := 22.0
const TRAIL_A := 1.0
## This many samples behind the head the trail is 2 px thick.
const TRAIL_THICK := 6
## The flash where a shell leaves the gun (s).
const FLASH_S := 0.22
## A landing's puff: how long it lasts (s), how far it grows, its motes.
const PUFF_S := 0.9
const PUFF_R := 7.0
const PUFF_MOTES := 7
## A shell that vanishes with more than this left never landed: the field was cleared (a tow, a new stage).
const LANDED_LEFT_S := 0.5

var v: TankView = null
var rect: Rect2 = Rect2()
## Live puffs: [{r (m), t (s), friendly, seed}].
var puffs: Array[Dictionary] = []
## Shell id -> {land (m), left (s), friendly}: what each far shell was doing last frame.
var _flying: Dictionary = {}
## 0 folded to its tab .. 1 open.
var open: float = 1.0


func _init(view: TankView) -> void:
	v = view
	name = "Pip"


## "1640 M", or "--" without a far target.
static func range_label(range_m: float) -> String:
	return "--" if range_m <= 0.0 else "%d %s" % [roundi(range_m), UNIT]


## "2.4 S": a shell's seconds until it lands.
static func flight_label(left_s: float) -> String:
	return "%.1f %s" % [maxf(left_s, 0.0), SECONDS]


## Plate-local px of range `r`, height `hm` (m), on a plate of `size`.
static func to_px(r: float, hm: float, size: Vector2, mirrored: bool) -> Vector2:
	var x := END_PAD + r / TankFarMap.RANGE_FAR_M * (size.x - 2.0 * END_PAD)
	if mirrored:
		x = size.x - x
	return Vector2(roundf(x), roundf(size.y - FLOOR_ABOVE - UP_K * sqrt(maxf(hm, 0.0))))


## The far shells as tracers: [{p, trail (head first), friendly, evadable, arc (dashes), launch (px), age, left}].
func dots(state: TankState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var g := v.far_g()
	for s in state.shells:
		if not s.far:
			continue
		var at := v.shell_pos(s)
		var land := TankShellPath.landing_m(s.x, s.vx, s.left_s)
		var age := TankShellPath.age_s(s.left_s, s.vy, g)
		var launch := TankShellPath.launch_m(s.x, s.vx, age)
		(
			out
			. append(
				{
					"p": to_px(at.x, at.y, rect.size, v.mirrored),
					"trail": _trail(s, at.x, launch, g),
					"friendly": s.friendly,
					"evadable": s.evadable,
					"arc": _arc(s, launch, land, g),
					"launch": to_px(launch, 0.0, rect.size, v.mirrored),
					"age": age,
					"left": v.shell_left(s),
				}
			)
		)
	return out


func _trail(s: TankShellState, r: float, launch: float, g: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var back := -signf(s.vx) * TRAIL_STEP_M
	for i in range(1, TRAIL_N + 1):
		var q := r + back * float(i)
		if (q - launch) * signf(s.vx) < 0.0:
			break
		var hm := TankShellPath.height_at(q, s.x, s.y, s.vx, s.vy, g)
		out.append(to_px(q, hm, rect.size, v.mirrored))
	return out


func _arc(s: TankShellState, launch: float, land: float, g: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var a := to_px(launch, 0.0, rect.size, v.mirrored)
	var b := to_px(land, 0.0, rect.size, v.mirrored)
	var n := maxi(int(absf(b.x - a.x) / DASH_EVERY), 1)
	for i in n + 1:
		var r := lerpf(launch, land, float(i) / float(n))
		var hm := TankShellPath.height_at(r, s.x, s.y, s.vx, s.vy, g)
		out.append(to_px(r, hm, rect.size, v.mirrored))
	return out


## The arc the gun would fly to `range_m` (px), faint; empty out of the gun's reach.
func aim_arc(range_m: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var v0 := v.far_v0()
	var g := v.far_g()
	if range_m <= 0.0 or v0 <= 0.0:
		return out
	var elev := TankBallistics.far_elevation(range_m, v0, g)
	if is_nan(elev):
		return out
	var rad := deg_to_rad(elev)
	var vx := v0 * cos(rad)
	var vy := v0 * sin(rad)
	var a := to_px(0.0, 0.0, rect.size, v.mirrored)
	var b := to_px(range_m, 0.0, rect.size, v.mirrored)
	var n := maxi(int(absf(b.x - a.x) / AIM_EVERY), 1)
	for i in n + 1:
		var r := range_m * float(i) / float(n)
		var t := r / vx
		out.append(to_px(r, maxf(vy * t - 0.5 * g * t * t, 0.0), rect.size, v.mirrored))
	return out


## True when there is something to show: a far shell, a far enemy, a target.
func busy(state: TankState) -> bool:
	if v.target_range_m(state) > 0.0 or v.boss_visible(state):
		return true
	for s in state.shells:
		if s.far:
			return true
	for e in state.enemies:
		if not e.is_near() and e.mode != TankIds.EM_DEAD:
			return true
	return false


## One frame: a far shell gone since the last one, near its end, leaves a puff where it landed.
func frame(state: TankState, dt: float) -> void:
	open = move_toward(open, 1.0 if busy(state) else 0.0, dt / FOLD_S)
	for i in range(puffs.size() - 1, -1, -1):
		puffs[i]["t"] = float(puffs[i]["t"]) + dt
		if float(puffs[i]["t"]) >= PUFF_S:
			puffs.remove_at(i)
	var now := {}
	for s in state.shells:
		if s.far:
			now[s.id] = {
				"land": TankShellPath.landing_m(s.x, s.vx, s.left_s),
				"left": s.left_s,
				"friendly": s.friendly,
			}
	for id: int in _flying:
		var was: Dictionary = _flying[id]
		if not now.has(id) and float(was["left"]) <= LANDED_LEFT_S:
			puffs.append({"r": was["land"], "t": 0.0, "friendly": was["friendly"], "seed": id})
	_flying = now


func _draw() -> void:
	if v == null or v.game == null or v.game.state == null:
		return
	var state := v.game.state
	if state.hull.tow_s > 0.0:
		return
	if open < 1.0:
		_tab(state)
		return
	var size := rect.size
	_screen(size)
	var ground := size.y - GROUND_ABOVE
	_ground(size, ground)
	var shown := dots(state)
	var target := v.target_range_m(state)
	if shown.is_empty():
		for q in aim_arc(target):
			draw_rect(Rect2(q, Vector2.ONE), AIM)
	_newest_arc(shown)
	_hull(size, ground)
	_marks(state, size, ground)
	for p in puffs:
		_puff(p, size)
	for d in shown:
		_tracer(d)
	_labels(size, shown, target)


## The plate folded (or folding) to its dim tab on the seam: the hull's icon and what the range plate says.
func _tab(state: TankState) -> void:
	var tab := TAB.lerp(rect.size, open)
	var at := Vector2(rect.size.x - tab.x, 0.0) if v.mirrored else Vector2.ZERO
	var a := lerpf(TAB_ALPHA, 1.0, open)
	draw_rect(Rect2(at, tab), Color(BEZEL, a))
	TankHudDraw.frame(self, Rect2(at, tab), Color(FRAME, a))
	var x := at.x + (tab.x - 13.0 if v.mirrored else 4.0)
	draw_rect(Rect2(Vector2(x, at.y + 6.0), Vector2(9, 3)), Color(HULL, a * 0.7))
	draw_rect(Rect2(Vector2(x + 3.0, at.y + 4.0), Vector2(3, 2)), Color(HULL, a * 0.7))
	var label := range_label(v.target_range_m(state))
	if v.mirrored:
		TankHudDraw.text(self, at.x + 4.0, at.y + 3.0, label, Color(LABEL, a))
	else:
		TankHudDraw.text_r(self, at.x + tab.x - 4.0, at.y + 3.0, label, Color(LABEL, a))


## The newest of our shells has its predicted arc; theirs and our older ones only their trails.
func _newest_arc(shown: Array[Dictionary]) -> void:
	var newest := {}
	for d in shown:
		if bool(d["friendly"]) and (newest.is_empty() or float(d["age"]) < float(newest["age"])):
			newest = d
	if newest.is_empty():
		return
	var arc: PackedVector2Array = newest["arc"]
	for q in arc:
		draw_rect(Rect2(q, Vector2.ONE), Color(OURS, 0.6))


## The bezel, the dark glass and its scan rows.
func _screen(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BEZEL)
	TankHudDraw.frame(self, Rect2(Vector2.ZERO, size), FRAME)
	var glass := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	draw_rect(glass, SCREEN)
	var y := glass.position.y + 1.0
	while y < glass.end.y:
		draw_rect(Rect2(glass.position.x, y, glass.size.x, 1.0), SCAN)
		y += 2.0


## The ground line and a tick every 500 m.
func _ground(size: Vector2, ground: float) -> void:
	draw_rect(Rect2(Vector2(4, ground), Vector2(size.x - 8.0, 1)), GROUND)
	var r := GROUND_TICK_M
	while r < TankFarMap.RANGE_FAR_M:
		draw_rect(
			Rect2(Vector2(to_px(r, 0.0, size, v.mirrored).x, ground + 1.0), Vector2(1, 2)),
			GROUND_TICK
		)
		r += GROUND_TICK_M


## The tiny hull (9 x 5) at range 0, its gun toward the field.
func _hull(size: Vector2, ground: float) -> void:
	var x := to_px(0.0, 0.0, size, v.mirrored).x
	var left := x - 9.0 if v.mirrored else x
	draw_rect(Rect2(Vector2(left, ground - 3.0), Vector2(9, 3)), HULL)
	var tx := x - 6.0 if v.mirrored else x + 3.0
	draw_rect(Rect2(Vector2(tx, ground - 5.0), Vector2(3, 2)), HULL)
	var gx := x - 9.0 if v.mirrored else x + 6.0
	draw_rect(Rect2(Vector2(gx, ground - 5.0), Vector2(3, 1)), HULL)


## A mark per far enemy at its range (the Behemoth's wider): the target's bright with a caret over it, a
## shooter in its telegraph red.
func _marks(state: TankState, size: Vector2, ground: float) -> void:
	var target := state.hull.target_id
	for e in state.enemies:
		if e.is_near() or e.mode == TankIds.EM_DEAD:
			continue
		var x := to_px(v.far_range_of(e), 0.0, size, v.mirrored).x
		_mark(x, ground, 1.0, e.id == target, e.telegraph_s > 0.0)
	if v.boss_visible(state):
		var bx := to_px(v.far_boss_range(state), 0.0, size, v.mirrored).x
		_mark(bx, ground, 2.0, TankBossState.is_part_id(target), state.boss.telegraph_s > 0.0)


func _mark(x: float, ground: float, half: float, target: bool, shooting: bool) -> void:
	var col := MARK_TARGET if target else MARK
	if shooting and fposmod(v.time * BLINK_HZ, 1.0) < 0.5:
		col = THEIRS
	var h := 3.0 + half
	draw_rect(Rect2(Vector2(x - half, ground - h), Vector2(half * 2.0 + 1.0, h)), col)
	if target:
		draw_rect(Rect2(Vector2(x, ground - h - 3.0), Vector2.ONE), col)
		draw_rect(Rect2(Vector2(x - 1.0, ground - h - 4.0), Vector2(3, 1)), col)


## The tracer: a flash where it left, a bright trail that fades, thick behind the head, a hot head with a halo.
func _tracer(d: Dictionary) -> void:
	var friendly := bool(d["friendly"])
	var col := OURS if friendly else THEIRS
	var age := float(d["age"])
	if age < FLASH_S:
		_burst(d["launch"], col, 1.0 - age / FLASH_S)
	var p: Vector2 = d["p"]
	if bool(d["evadable"]) and fposmod(v.time * BLINK_HZ, 1.0) >= 0.5:
		col = THEIRS_DIM
	var trail: PackedVector2Array = d["trail"]
	for i in trail.size():
		var a := TRAIL_A * (1.0 - float(i) / float(TRAIL_N))
		var thick := Vector2(1, 2) if i < TRAIL_THICK else Vector2.ONE
		draw_rect(Rect2(trail[i], thick), Color(col, a))
	draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(col, 0.3))
	draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), col)
	draw_rect(Rect2(p - Vector2.ONE, Vector2(2, 2)), CORE)


func _burst(at: Vector2, col: Color, k: float) -> void:
	var c := Color(CORE, k)
	draw_rect(Rect2(at + Vector2(-1, -2), Vector2(3, 1)), c)
	draw_rect(Rect2(at + Vector2(0, -4), Vector2(1, 5)), Color(col, k))
	draw_rect(Rect2(at + Vector2(-3, -1), Vector2(7, 1)), Color(col, k * 0.7))


## A landing: a hot flash, then motes of earth thrown up and out, fading.
func _puff(p: Dictionary, size: Vector2) -> void:
	var u := float(p["t"]) / PUFF_S
	var at := to_px(float(p["r"]), 0.0, size, v.mirrored) + Vector2(0, 2)
	var col := OURS if bool(p["friendly"]) else THEIRS
	if u < 0.2:
		draw_rect(Rect2(at + Vector2(-2, -4), Vector2(5, 4)), Color(CORE, 1.0 - u * 5.0))
	var seed_x := float(p["seed"])
	for i in PUFF_MOTES:
		var h := TankDraw.hash01(seed_x * 0.37 + float(i) * 1.9)
		var dir := (float(i) + 0.5) / float(PUFF_MOTES) * 2.0 - 1.0
		var q := (
			at
			+ Vector2(dir * PUFF_R * u, -(2.0 + h * PUFF_R) * sin(minf(u * 1.6, 1.0) * PI * 0.75))
		)
		var c := col.lerp(LABEL, u)
		draw_rect(Rect2(q.round(), Vector2.ONE), Color(c, (1.0 - u) * 0.9))


## The newest shell's seconds on the near side's corner, the target's range on the other.
func _labels(size: Vector2, shown: Array[Dictionary], target: float) -> void:
	var near := {}
	for d in shown:
		if near.is_empty() or float(d["left"]) > float(near["left"]):
			near = d
	var range_text := range_label(target)
	if v.mirrored:
		TankHudDraw.text(self, 5.0, 3.0, range_text, LABEL)
	else:
		TankHudDraw.text_r(self, size.x - 5.0, 3.0, range_text, LABEL)
	if near.is_empty():
		return
	var col := OURS if bool(near["friendly"]) else THEIRS
	var flight := flight_label(float(near["left"]))
	if v.mirrored:
		TankHudDraw.text_r(self, size.x - 5.0, 3.0, flight, col)
	else:
		TankHudDraw.text(self, 5.0, 3.0, flight, col)

class_name TankPip
extends Node2D
## v4: the shell screen (SPEC_TANK 4.5): a small riveted plate in the far panel's top with the ballistic
## arc in side profile, distance-compressed. The hull at range 0 and a tick per far enemy on the ground
## line; each far shell a dot on its predicted arc, ours amber, theirs red and blinking while Surge can
## still make it miss; the target's range at the right. Mirrored with the far panel (free roam, west);
## its text never mirrors.

const PLATE := Color("#100e0b")
const FRAME := Color("#8a6a3a")
const GROUND := Color("#3a3128")
const OURS := Color("#e3a24a")
const THEIRS := Color("#d8452a")
const THEIRS_DIM := Color("#6e2616")
const TICK := Color("#6f6450")
const TICK_TARGET := Color("#e8dcc0")
const HULL := Color("#a3937a")
const END_PAD := 10.0
const GROUND_ABOVE := 7.0
const FLOOR_ABOVE := 9.0
const PX_PER_M_UP := 0.2
const DASH_EVERY := 6.0
const TRAIL_PX := 4.0
const BLINK_HZ := 5.0
const PLATE_W := 42.0
const UNIT := "M"

var v: TankView = null
var rect: Rect2 = Rect2()


func _init(view: TankView) -> void:
	v = view
	name = "Pip"


## "1640 M", or "--" without a far target.
static func range_label(range_m: float) -> String:
	return "--" if range_m <= 0.0 else "%d %s" % [roundi(range_m), UNIT]


## Plate-local px of range `r`, height `hm` (m), on a plate of `size`.
static func to_px(r: float, hm: float, size: Vector2, mirrored: bool) -> Vector2:
	var x := END_PAD + r / TankFarMap.RANGE_FAR_M * (size.x - 2.0 * END_PAD)
	if mirrored:
		x = size.x - x
	return Vector2(roundf(x), roundf(size.y - FLOOR_ABOVE - hm * PX_PER_M_UP))


## The far shells as dots: [{p, from (the trail's far end), friendly, evadable, arc (dashes)}].
func dots(state: TankState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var g := v.far_g()
	for s in state.shells:
		if not s.far:
			continue
		var at := v.shell_pos(s)
		var p := to_px(at.x, at.y, rect.size, v.mirrored)
		var land := TankShellPath.landing_m(s.x, s.vx, s.left_s)
		var age := TankShellPath.age_s(s.left_s, s.vy, g)
		var launch := TankShellPath.launch_m(s.x, s.vx, age)
		var ahead := at.x - signf(s.vx) * 40.0
		var back := TankShellPath.height_at(ahead, s.x, s.y, s.vx, s.vy, g)
		var dir := (p - to_px(ahead, back, rect.size, v.mirrored)).normalized()
		(
			out
			. append(
				{
					"p": p,
					"from": p - dir * TRAIL_PX,
					"friendly": s.friendly,
					"evadable": s.evadable,
					"arc": _arc(s, launch, land, g),
				}
			)
		)
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


func _draw() -> void:
	if v == null or v.game == null or v.game.state == null:
		return
	var state := v.game.state
	var size := rect.size
	draw_rect(Rect2(Vector2.ZERO, size), PLATE)
	TankHudDraw.frame(self, Rect2(Vector2.ZERO, size), FRAME)
	for c: Vector2 in [
		Vector2(2, 2),
		Vector2(size.x - 4.0, 2),
		Vector2(2, size.y - 4.0),
		Vector2(size.x - 4.0, size.y - 4.0)
	]:
		TankHudDraw.rivet(self, c)
	var ground := size.y - GROUND_ABOVE
	draw_rect(Rect2(Vector2(5, ground), Vector2(size.x - 10.0, 1)), GROUND)
	_hull(size, ground)
	_ticks(state, size, ground)
	for d in dots(state):
		_dot(d)
	var label := range_label(v.target_range_m(state))
	TankHudDraw.text_r(self, size.x - 6.0, 4.0, label, TankHudDraw.NUM)


## The tiny hull (9 x 5) at range 0, its gun toward the field.
func _hull(size: Vector2, ground: float) -> void:
	var x := to_px(0.0, 0.0, size, v.mirrored).x
	var sgn := -1.0 if v.mirrored else 1.0
	var left := x - 9.0 if v.mirrored else x
	draw_rect(Rect2(Vector2(left, ground - 3.0), Vector2(9, 3)), HULL)
	var tx := x + sgn * 3.0 if not v.mirrored else x - 6.0
	draw_rect(Rect2(Vector2(tx, ground - 5.0), Vector2(3, 2)), HULL)
	var gx := x + 6.0 if not v.mirrored else x - 9.0
	draw_rect(Rect2(Vector2(gx, ground - 5.0), Vector2(3, 1)), HULL)


## One tick per far enemy at its range (the Behemoth's wider), the target's bright.
func _ticks(state: TankState, size: Vector2, ground: float) -> void:
	var target := state.hull.target_id
	for e in state.enemies:
		if e.is_near() or e.mode == TankIds.EM_DEAD:
			continue
		var x := to_px(v.far_range_of(e), 0.0, size, v.mirrored).x
		var col := TICK_TARGET if e.id == target else TICK
		draw_rect(Rect2(Vector2(x, ground - 4.0), Vector2(1, 4)), col)
	if v.boss_visible(state):
		var bx := to_px(v.far_boss_range(state), 0.0, size, v.mirrored).x
		var col2 := TICK_TARGET if TankBossState.is_part_id(target) else TICK
		draw_rect(Rect2(Vector2(bx - 1.0, ground - 6.0), Vector2(3, 6)), col2)


func _dot(d: Dictionary) -> void:
	var friendly := bool(d["friendly"])
	var col := OURS if friendly else THEIRS
	var arc: PackedVector2Array = d["arc"]
	var dash := Color(col, 0.45)
	for q in arc:
		draw_rect(Rect2(q, Vector2.ONE), dash)
	var p: Vector2 = d["p"]
	if bool(d["evadable"]) and fposmod(v.time * BLINK_HZ, 1.0) >= 0.5:
		col = THEIRS_DIM
	draw_line(d["from"], p, Color(col, 0.6), 1.0)
	draw_rect(Rect2(p - Vector2.ONE, Vector2(2, 2)), col)

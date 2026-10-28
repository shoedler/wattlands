class_name TankLightDraw
extends RefCounted
## The two additive light layers (docs/games/tank.md v3 "Lights", 3.1). Lights are the only
## near-saturated pixels.
##   draw()        the tank's own lights, on the Light layer over the tank and rotated with the hull:
##                 the rooms' incandescent lamps (warm; the seat's slot colour mixed in while its
##                 rider is in band; the Lights room cold while its arc burns; dark in a breakdown),
##                 the turret windows' lamps, the headlight, the turret searchlight (forward about 11
##                 degrees down, on while the Lights seat is manned and its arc lit), the rear
##                 searchlight (aft about 13 degrees down, always on: a work light), the red and
##                 green position lights, the main gun's scene flash, shells, flashes, the wash
##   draw_world()  every world light, on the WorldLight layer behind the tank: the tank's pools on
##                 the road (the headlight's, the searchlights' where their axes meet the road, the
##                 rooms' spill, the shot's flash), the little bases' lamps, the halt line's and the
##                 turning places' lamps, burning wrecks and the Behemoth, the beams' rim light on
##                 enemies and wrecks, the enemies' slits and telegraph glows

const WARM := Color(1.0, 0.64, 0.32)
const COLD := Color(0.66, 0.82, 1.0)
const RED := Color(1.0, 0.15, 0.1)
const GREEN := Color(0.2, 1.0, 0.35)
const AMBER := Color(1.0, 0.68, 0.3)
const SEARCH := Color(1.0, 0.94, 0.78)
## The beams' warm light on what they cross.
const BEAM_LIT := Color(1.0, 0.8, 0.52)
## The headlight's beam: degrees below the hull's line, length, half spread (degrees).
const HEAD_DEG := 9.0
const HEAD_LEN := 210.0
const HEAD_HALF := 12.0
## The searchlights' slow sway (degrees) and its rate.
const SWAY_DEG := 1.0
const SWAY_HZ := 0.45
## The rooms that glow (kit rooms).
const GLOW_ROOMS: Array[String] = [
	"drive", "loader", "gun", "lights", "sec", "quarters", "turret_drive", "upper_front"
]


static func draw(ci: CanvasItem, v: TankView, state: TankState) -> void:
	if not state.hull.breakdown:
		_rooms(ci, v, state)
	_beams(ci, v, state)
	_running_lights(ci, v)
	_scene_flash(ci, v)
	_shells(ci, v, state)
	v.fx.draw_light(ci)
	if v.fx.wash > 0.0:
		var c := v.fx.wash_color
		TankDraw.glow_at(ci, v.fx.wash_pos, 320.0, Color(c.r, c.g, c.b, 0.16 * v.fx.wash))


static func draw_world(ci: CanvasItem, v: TankView, state: TankState) -> void:
	_ground_pools(ci, v, state)
	_world_lamps(ci, v, state)
	for bx in TankForest.bases(v, state):
		TankForest.draw_base_light(ci, v, bx)
	_fires(ci, v, state)
	_lit_by_beams(ci, v, state)
	for id: int in v.enemy_rects:
		var e := state.enemy(id)
		if e == null:
			continue
		var er: Rect2 = v.enemy_rects[id]
		if e.telegraph_s > 0.0:
			TankDraw.glow_at(ci, v.enemy_muzzle(e, er), 12.0, Color(1.0, 0.4, 0.15, 0.6))
		var slit_x := er.size.x - 6.0 if e.side >= 0 else 6.0
		TankDraw.glow_at(
			ci, er.position + Vector2(slit_x, er.size.y * 0.45), 3.0, Color(1.0, 0.2, 0.1, 0.7)
		)


## The tank's beams this frame: [{p (the lens, stage px), ang, half (radians), len, k, head}].
static func beams(v: TankView, state: TankState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hk := 1.0
	if state.hull.breakdown:
		hk = 0.25 + 0.2 * TankDraw.hash01(floorf(v.time * 12.0))
	var hd := v.rig.detail("headlight")
	if not hd.is_empty():
		(
			out
			. append(
				{
					"p": v.at_sprite((hd["at"] as Vector2) + Vector2(3.5, 0)),
					"ang": v.hull_rot + deg_to_rad(HEAD_DEG),
					"half": deg_to_rad(HEAD_HALF),
					"len": HEAD_LEN,
					"k": hk,
					"head": true,
				}
			)
		)
	var sway := deg_to_rad(SWAY_DEG * sin(v.time * SWAY_HZ))
	var ts := v.rig.detail("searchlight")
	if not ts.is_empty() and v.turret_search_on(state):
		var a := deg_to_rad(float(ts.get("ang", 11.0)))
		if v.turret_sx() < 0.0:
			a = PI - a
		(
			out
			. append(
				{
					"p": v.at_turret(TankRig.lens_of(ts)),
					"ang": v.hull_rot + a + sway,
					"half": deg_to_rad(float(ts.get("half", 6.0))),
					"len": float(ts.get("len", 560.0)),
					"k": v.searchlight_k(state),
					"head": false,
				}
			)
		)
	var rs := v.rig.detail("searchlight_rear")
	if not rs.is_empty():
		(
			out
			. append(
				{
					"p": v.at_sprite(TankRig.lens_of(rs)),
					"ang": v.hull_rot + deg_to_rad(float(rs.get("ang", 167.0))) + sway,
					"half": deg_to_rad(float(rs.get("half", 8.0))),
					"len": float(rs.get("len", 220.0)),
					"k": hk,
					"head": false,
				}
			)
		)
	return out


## How much of the tank's beams falls on stage point `p` (0..1): each beam by how near `p` lies to
## its cone's axis and how far down its reach.
static func beam_light(v: TankView, state: TankState, p: Vector2) -> float:
	var k := 0.0
	for b in beams(v, state):
		var d: Vector2 = p - (b["p"] as Vector2)
		var dist := d.length()
		if dist < 1.0:
			continue
		var off := absf(angle_difference(d.angle(), float(b["ang"])))
		var cone := clampf(1.0 - off / (float(b["half"]) * 2.2), 0.0, 1.0)
		var reach := clampf(1.0 - dist / (float(b["len"]) * 1.4), 0.0, 1.0)
		k += cone * cone * sqrt(reach) * minf(float(b["k"]), 1.0)
	return clampf(k, 0.0, 1.0)


## The rooms' lamps: a bloom over each lit room, a lamp at its ceiling, the turret windows' lamps.
static func _rooms(ci: CanvasItem, v: TankView, state: TankState) -> void:
	var arc_on := v.turret_search_on(state)
	for id in GLOW_ROOMS:
		var r: Rect2 = v.rig.rooms.get(id, Rect2())
		if r.size == Vector2.ZERO:
			continue
		var c := v.at_sprite(r.get_center())
		var lamp := v.at_sprite(Vector2(r.get_center().x, r.position.y + 3.0))
		var col := WARM
		var gain := 1.0
		var rd: TankRiderState = v.rider_on(id) if id in TankRig.SEATS else null
		if id == "lights" and arc_on:
			col = COLD
			gain = 1.4
		elif rd != null and rd.in_band:
			col = WARM.lerp(slot_color(rd), 0.15)
			gain = 1.25
		var fl := 0.92 + 0.08 * sin(v.time * 3.0 + r.position.x)
		TankDraw.glow_at(ci, c, r.size.x * 0.75, Color(col.r, col.g, col.b, 0.1 * fl * gain))
		TankDraw.glow_at(ci, c, r.size.x * 0.35, Color(col.r, col.g, col.b, 0.08 * fl * gain))
		TankDraw.glow_at(ci, lamp, 4.0, Color(1.0, 0.85, 0.6, 0.45))
	for wl in v.rig.window_lamps:
		var p := v.at_turret(wl) if v.rig.turret_rect.has_point(wl) else v.at_sprite(wl)
		TankDraw.glow_at(ci, p + Vector2(0, 4), 12.0, Color(WARM.r, WARM.g, WARM.b, 0.14))


## A rider's slot colour (the caps TankInterior paints).
static func slot_color(r: TankRiderState) -> Color:
	if r == null:
		return WARM
	return TankInterior.SLOT[posmod(r.slot, TankInterior.SLOT.size())]


static func _beams(ci: CanvasItem, v: TankView, state: TankState) -> void:
	for b in beams(v, state):
		var p: Vector2 = b["p"]
		var k := float(b["k"])
		var ang := float(b["ang"])
		var half := float(b["half"])
		if bool(b["head"]):
			TankDraw.beam(ci, p, ang, float(b["len"]), half, Color(1.0, 0.82, 0.52), 0.5 * k)
			TankDraw.glow_at(ci, p, 6.0, Color(1.0, 0.95, 0.8, k))
			TankDraw.glow_at(ci, p, 22.0, Color(1.0, 0.8, 0.5, 0.35 * k))
			continue
		TankDraw.beam(ci, p, ang, float(b["len"]), half, SEARCH, 0.45 * k)
		TankDraw.glow_at(ci, p, 9.0, Color(1.0, 0.95, 0.8, 0.9 * maxf(k, 0.3)))
		TankDraw.glow_at(ci, p, 24.0, Color(1.0, 0.85, 0.6, 0.2 * k))


## The red and green position lights (the rear red one and the green one blinking slowly).
static func _running_lights(ci: CanvasItem, v: TankView) -> void:
	var blink := 0.75 + 0.25 * sin(v.time * 2.2)
	var reds := v.rig.details_of("lamp_red")
	for i in reds.size():
		var p := v.at_sprite((reds[i]["at"] as Vector2) + Vector2(0.5, 0.5))
		TankDraw.lamp(ci, p, RED, blink if i == 0 else 0.9)
	for g in v.rig.details_of("lamp_green"):
		TankDraw.lamp(ci, v.at_sprite((g["at"] as Vector2) + Vector2(0.5, 0.5)), GREEN, blink)


## The main gun's flash on the scene for its first frames: a wide warm halo at the muzzle, the
## tank's own hull and the road lit, a white core.
static func _scene_flash(ci: CanvasItem, v: TankView) -> void:
	var k := v.firing.flash_k()
	if k <= 0.0:
		return
	var m := v.muzzle()
	TankDraw.glow_at(ci, m, 240.0, Color(1.0, 0.75, 0.44, 0.5 * k))
	TankDraw.glow_at(ci, m + Vector2(-120, 50), 220.0, Color(1.0, 0.69, 0.38, 0.28 * k))
	TankDraw.glow_at(ci, m + Vector2(10, 90), 160.0, Color(1.0, 0.69, 0.38, 0.25 * k))
	TankDraw.glow_at(ci, m, 26.0, Color(1.0, 0.96, 0.82, 0.9 * k))


## The tank's pools on the road (behind the tank): the headlight's long pool, the searchlights'
## pools where their axes meet the road, the shot's flash, the rooms' spill beside the tracks.
static func _ground_pools(ci: CanvasItem, v: TankView, state: TankState) -> void:
	for b in beams(v, state):
		var p: Vector2 = b["p"]
		var k := minf(float(b["k"]), 1.0)
		if bool(b["head"]):
			var x1 := p.x + 160.0
			var x2 := p.x + 45.0
			ground_glow(
				ci, Vector2(x1, v.ground_y(x1) + 6.0), 125.0, Color(1.0, 0.75, 0.45, 0.4 * k)
			)
			ground_glow(
				ci, Vector2(x2, v.ground_y(x2) + 3.0), 70.0, Color(1.0, 0.72, 0.42, 0.22 * k)
			)
			continue
		var dv := Vector2.from_angle(float(b["ang"]))
		if dv.y > 0.01:
			var hit := p + dv * ((v.ground_y(p.x) - p.y) / dv.y)
			hit.y = v.ground_y(hit.x)
			if hit.distance_to(p) < float(b["len"]):
				ground_glow(ci, hit, 46.0, Color(1.0, 0.9, 0.72, 0.32 * k))
	var fk := v.firing.flash_k()
	if fk > 0.0:
		var m := v.muzzle()
		ground_glow(
			ci, Vector2(m.x, v.ground_y(m.x) + 4.0), 220.0, Color(1.0, 0.72, 0.38, 0.5 * fk)
		)
	if state.hull.breakdown:
		return
	for id in GLOW_ROOMS:
		var r: Rect2 = v.rig.rooms.get(id, Rect2())
		if r.size == Vector2.ZERO or r.position.y < 140.0:
			continue
		var lit := 0.08
		var rd: TankRiderState = v.rider_on(id) if id in TankRig.SEATS else null
		if rd != null:
			lit = 0.12 if rd.in_band else 0.07
		var x := v.at_sprite(r.get_center()).x
		var c := Color(1.0, 0.66, 0.36, lit)
		if id == "lights" and v.turret_search_on(state):
			c = Color(COLD.r, COLD.g, COLD.b, 0.07)
		ground_glow(ci, Vector2(x, v.ground_y(x) + 6.0), r.size.x * 0.8 + 20.0, c)


## A flat glow lying on the road (an ellipse 0.14 as tall as wide) at `p`, `r` px wide each side.
static func ground_glow(ci: CanvasItem, p: Vector2, r: float, c: Color) -> void:
	ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.14))
	ci.draw_texture_rect(TankDraw.glow_tex(), Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0), false, c)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _world_lamps(ci: CanvasItem, v: TankView, state: TankState) -> void:
	var hl := TankWorldDraw.halt_lamp(v, state)
	if not is_nan(hl.x):
		TankDraw.glow_at(ci, hl, 6.0, Color(1.0, 0.85, 0.6, 0.7))
		TankDraw.glow_at(ci, hl + Vector2(0, 14), 30.0, Color(AMBER.r, AMBER.g, AMBER.b, 0.3))
	for tl in TankWorldDraw.turn_lamps(v, state):
		TankDraw.glow_at(ci, tl, 5.0, Color(1.0, 0.85, 0.6, 0.7))
		TankDraw.glow_at(ci, tl + Vector2(0, 16), 34.0, Color(AMBER.r, AMBER.g, AMBER.b, 0.26))


## The beams' warm light on the enemies and the wrecks they cross: their edges facing the tank (the
## kit's rim mask) catch it brightly, the rest of the sprite a little; back lanes less (haze).
static func _lit_by_beams(ci: CanvasItem, v: TankView, state: TankState) -> void:
	for id: int in v.enemy_rects:
		var e := state.enemy(id)
		if e == null or not v.lanes.has(id):
			continue
		var r: Rect2 = v.enemy_rects[id]
		_beam_rim(ci, v, state, v.kit.enemies[v.enemy_kind(e)], r, e.side < 0, int(v.lanes[id]))
	for w in v.wrecks:
		if v.wreck_collapse(w) >= 1.0:
			continue
		var wr := TankWorldDraw.wreck_rect(v, w)
		var row: Dictionary = v.kit.enemies.get(str(w["kind"]), {})
		if not row.is_empty():
			_beam_rim(ci, v, state, row, wr, int(w.get("side", 1)) < 0, int(w.get("lane", 0)), 0.7)


static func _beam_rim(
	ci: CanvasItem,
	v: TankView,
	state: TankState,
	row: Dictionary,
	r: Rect2,
	flip: bool,
	lane: int,
	gain: float = 1.0
) -> void:
	if not row.has("rim") or r.end.x < 0.0 or r.position.x > v.canvas.x:
		return
	var k := beam_light(v, state, r.get_center()) * gain * (1.0 - TankWorldDraw.lane_fog(lane))
	if k < 0.02:
		return
	TankWorldDraw.sprite(
		ci, row["sil"], r, flip, Color(BEAM_LIT.r, BEAM_LIT.g, BEAM_LIT.b, 0.04 * k)
	)
	TankWorldDraw.sprite(
		ci, row["rim"], r, flip, Color(BEAM_LIT.r, BEAM_LIT.g, BEAM_LIT.b, 0.5 * k)
	)


static func _fires(ci: CanvasItem, v: TankView, state: TankState) -> void:
	for w in v.wrecks:
		var k := v.wreck_fire(w)
		if k <= 0.0:
			# The heap's embers: one slit glowing a while longer.
			if v.wreck_age(w) < TankView.WRECK_BURN_S * 2.0:
				var hr := TankWorldDraw.heap_rect(v, w)
				TankDraw.glow_at(
					ci, hr.get_center() + Vector2(2, 1), 3.0, Color(1.0, 0.35, 0.1, 0.35)
				)
			continue
		var r := TankWorldDraw.wreck_rect(v, w)
		if r.position.x > v.canvas.x + 10.0 or r.end.x < -10.0:
			continue
		var c := TankWorldDraw.wreck_hatch(v, w) + Vector2(0, -2)
		var fl := 0.75 + 0.25 * sin(v.time * 9.0 + r.position.x) * sin(v.time * 5.3)
		TankDraw.glow_at(ci, c, 14.0 * k, Color(1.0, 0.42, 0.12, 0.45 * fl * k))
		TankDraw.glow_at(ci, c, 4.0, Color(1.0, 0.75, 0.35, 0.7 * fl * k))
	if not v.boss_visible(state):
		return
	var b := state.boss
	var br := v.boss_rect(state)
	var meta: Dictionary = v.kit.enemies.get("behemoth", {}).get("meta", {})
	var bog: Array = meta.get("bogies_at", [])
	for i in mini(b.bogie_hp.size(), bog.size()):
		if b.bogie_hp[i] > 0.0 and b.phase != TankIds.BOSS_DEAD:
			continue
		var cpos := br.position + br.size * TankKit.vec(bog[i])
		var fl2 := 0.7 + 0.3 * sin(v.time * 8.0 + i * 2.0) * sin(v.time * 4.7 + i)
		TankDraw.glow_at(ci, cpos, 30.0, Color(1.0, 0.4, 0.1, 0.5 * fl2))
		TankDraw.glow_at(ci, cpos + Vector2(0, -6), 10.0, Color(1.0, 0.75, 0.35, 0.8 * fl2))
	if b.telegraph_s > 0.0:
		var mz := br.position + v.boss_muzzle()
		TankDraw.glow_at(ci, mz, 26.0, Color(1.0, 0.5, 0.2, 0.7))
		TankDraw.glow_at(ci, mz, 7.0, Color(1.0, 0.8, 0.5, 0.8))


static func _shells(ci: CanvasItem, v: TankView, state: TankState) -> void:
	for s in v.shells_drawn(state):
		var at: Vector2 = s["at"]
		var d: Vector2 = s["dir"]
		var bow := int(s["type"]) == TankIds.SHELL_BOW
		var col := Color(1.0, 0.75, 0.35) if bool(s["friendly"]) else Color(1.0, 0.35, 0.2)
		var tail := 8.0 if bow else 14.0
		ci.draw_line(at - d * tail, at, Color(col.r, col.g, col.b, 0.35), 1.0 if bow else 2.0)
		ci.draw_line(at - d * tail * 0.45, at, Color(1, 0.95, 0.8, 0.9), 1.0)
		TankDraw.glow_at(ci, at, 3.0 if bow else 5.0, Color(col.r, col.g, col.b, 0.6))

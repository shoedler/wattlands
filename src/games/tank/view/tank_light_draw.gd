class_name TankLightDraw
extends RefCounted
## The additive light layer (docs/games/tank.md 3.1): warm incandescent room lamps that take the
## rider's slot colour while in band (dark in a breakdown), the plaque lamps, the machines' glow
## (TankRoomMachines), the commander's searchlight sweeping slowly and the Bastion's tower light
## (both lit by the arc generator in band), the headlight with its pool on the road, the small red
## and green position lights, the halt line's and the depot's hooded lamps, burning wrecks and the
## Behemoth's broken bogies, shells and tracers, flashes, and a muzzle flash lighting the scene for
## a few frames. Lights are the only near-saturated pixels.

const WARM := Color(1.0, 0.64, 0.32)
const RED := Color(1.0, 0.15, 0.1)
const GREEN := Color(0.2, 1.0, 0.35)
const AMBER := Color(1.0, 0.68, 0.3)
## The beams' warm light on what they cross.
const BEAM_LIT := Color(1.0, 0.8, 0.52)


static func draw(ci: CanvasItem, v: TankView, state: TankState) -> void:
	var o := v.origin
	var broken := state.hull.breakdown
	_rooms(ci, v, o, broken)
	if not broken:
		var rooms := {}
		for e: String in TankView.MACHINE_ROOMS:
			if v.room_rects.has(e):
				rooms[e] = v.room_rects[e]
		TankRoomMachines.draw_light(ci, o, rooms, v.phases, v.powers, v.time)
	_beams(ci, v, state, o, broken)
	_lamps(ci, v, state, o)
	_fires(ci, v, state)
	_shells(ci, v, state)
	v.fx.draw_light(ci)
	if v.fx.wash > 0.0:
		var c := v.fx.wash_color
		TankDraw.glow_at(ci, v.fx.wash_pos, 320.0, Color(c.r, c.g, c.b, 0.16 * v.fx.wash))
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


## How much of the hero's beams falls on stage point `p` (0..1): the headlight and the commander's
## searchlight (and the Bastion's tower light behind), each by how near `p` lies to its cone's axis and
## how far down its reach.
static func beam_light(v: TankView, state: TankState, p: Vector2) -> float:
	var o := v.origin
	var sk := v.searchlight_k(state)
	var hk := 0.3 if state.hull.breakdown else 1.0
	var beams: Array[Array] = [
		[o + v.kit.anchor(v.variant, "headlight"), deg_to_rad(16.0), deg_to_rad(14.0), 560.0, hk],
		[_lens(v), _sweep(v), deg_to_rad(10.5), 760.0, sk],
	]
	if v.kit.has_anchor(v.variant, "searchlight_tower_lens"):
		var tl := o + v.kit.anchor(v.variant, "searchlight_tower_lens")
		beams.append([tl, deg_to_rad(198.0), deg_to_rad(5.0), 560.0, 0.6 * sk])
	var k := 0.0
	for b: Array in beams:
		var d: Vector2 = p - (b[0] as Vector2)
		var dist := d.length()
		if dist < 1.0:
			continue
		var off := absf(angle_difference(d.angle(), float(b[1])))
		var cone := clampf(1.0 - off / (float(b[2]) * 2.2), 0.0, 1.0)
		var reach := clampf(1.0 - dist / float(b[3]), 0.0, 1.0)
		k += cone * cone * sqrt(reach) * float(b[4])
	return clampf(k, 0.0, 1.0)


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


## The commander's searchlight lens (stage px) and its sweep (radians) this frame, turning with the
## turret (facing back it sweeps the road behind).
static func _lens(v: TankView) -> Vector2:
	var feet := v.origin + v.kit.anchor(v.variant, "turret_roof_commander_feet")
	var lens := feet - TankCrew.FEET + Vector2(22, 9) + Vector2(0.5, 0.5)
	if v.turret_sx() != 1.0:
		lens = v.turret_map(feet.round()) + (lens - feet.round()) * Vector2(signf(v.turret_sx()), 1)
	return lens


static func _sweep(v: TankView) -> float:
	var sweep := deg_to_rad(14.0 + 3.0 * sin(v.time * 0.45))
	return PI - sweep if v.turret_sx() < 0.0 else sweep


## Room lamps: the rider's slot colour while in band, else a dim warm lamp; dark in a breakdown
## (a few flickers while the crew works the repair).
static func _rooms(ci: CanvasItem, v: TankView, o: Vector2, broken: bool) -> void:
	for room: Dictionary in v.kit.rooms(v.variant):
		var rect := TankKit.rect_of(room)
		rect.position += o
		var lamp := Vector2(rect.get_center().x, rect.position.y + 4.0)
		if broken:
			if TankDraw.hash01(floorf(v.time * 9.0) + rect.position.x) > 0.85:
				TankDraw.glow_at(ci, lamp, rect.size.x * 0.3, Color(WARM.r, WARM.g, WARM.b, 0.08))
			continue
		if not room.has("engine"):
			TankDraw.glow_at(ci, lamp, rect.size.x * 0.5, Color(1.0, 0.7, 0.4, 0.12))
			continue
		var rd := v.rider_of(str(room["engine"]))
		# The small electrical rooms (dynamo, arc) get their lamp a step brighter.
		var gain := 1.3 if str(room["engine"]) in ["dynamo", "arc"] else 1.0
		if rd != null and rd.in_band:
			var c := WARM.lerp(TankHullDraw.slot_color(rd), 0.12)
			var fl := 0.9 + 0.1 * sin(v.time * 3.0 + rect.position.x)
			TankDraw.glow_at(ci, lamp, rect.size.x * 0.55, Color(c.r, c.g, c.b, 0.26 * fl * gain))
			TankDraw.glow_at(ci, lamp, 5.0, Color(1.0, 0.8, 0.55, 0.8))
			TankDraw.fill_room(ci, rect, Color(c.r, c.g, c.b, 0.05))
		else:
			TankDraw.glow_at(ci, lamp, rect.size.x * 0.4, Color(WARM.r, WARM.g, WARM.b, 0.14))
		if room.has("icon_chip_at") and rd != null:
			var pl := o + TankHullDraw.plaque_lamp(room)
			var sc := TankHullDraw.slot_color(rd)
			if rd.in_band:
				TankDraw.glow_at(ci, pl, 6.0, Color(sc.r, sc.g, sc.b, 0.55))
				TankDraw.glow_at(
					ci, pl, 2.0, Color(sc.r * 0.5 + 0.5, sc.g * 0.5 + 0.5, sc.b * 0.5 + 0.5, 0.9)
				)
			else:
				TankDraw.glow_at(ci, pl, 3.0, Color(sc.r, sc.g, sc.b, 0.18))


static func _beams(ci: CanvasItem, v: TankView, state: TankState, o: Vector2, broken: bool) -> void:
	var sk := v.searchlight_k(state)
	# The commander's searchlight on the turret roof, sweeping slowly.
	var lens := _lens(v)
	var sweep := _sweep(v)
	TankDraw.beam(ci, lens, sweep, 270.0, deg_to_rad(10.5), Color(1.0, 0.84, 0.56), 0.5 * sk)
	TankDraw.glow_at(ci, lens, 10.0, Color(1.0, 0.9, 0.7, 0.9 * maxf(sk, 0.3)))
	TankDraw.glow_at(ci, lens, 28.0, Color(1.0, 0.8, 0.5, 0.25 * sk))
	# The Bastion's searchlight tower at the rear (the arc generator's lamp, cold white).
	if v.kit.has_anchor(v.variant, "searchlight_tower_lens"):
		var tl := o + v.kit.anchor(v.variant, "searchlight_tower_lens")
		var ang := deg_to_rad(198.0 + 4.0 * sin(v.time * 0.3))
		TankDraw.beam(ci, tl, ang, 260.0, deg_to_rad(5.0), Color(0.95, 0.88, 0.72), 0.22 * sk)
		TankDraw.glow_at(ci, tl, 9.0, Color(0.8, 0.9, 1.0, 0.9 * maxf(sk, 0.3)))
	# The headlight: down onto the road, with a pool of light where it lands (it gutters in a
	# breakdown).
	var hk := 1.0
	if broken:
		hk = 0.25 + 0.2 * TankDraw.hash01(floorf(v.time * 12.0))
	var hl := o + v.kit.anchor(v.variant, "headlight")
	TankDraw.beam(ci, hl, deg_to_rad(16.0), 190.0, deg_to_rad(14.0), Color(1.0, 0.8, 0.5), 0.5 * hk)
	TankDraw.glow_at(ci, hl, 6.0, Color(1.0, 0.95, 0.8, hk))
	TankDraw.glow_at(ci, hl, 22.0, Color(1.0, 0.8, 0.5, 0.35 * hk))
	# Where the beam lands: a long warm pool on the road ahead, and a nearer spill under the nose.
	var g := TankView.GROUND
	ground_glow(ci, Vector2(hl.x + 165.0, g + 5.0), 125.0, Color(1.0, 0.75, 0.45, 0.4 * hk))
	ground_glow(ci, Vector2(hl.x + 50.0, g + 3.0), 70.0, Color(1.0, 0.72, 0.42, 0.22 * hk))
	# The cutaway rooms' lamps spill down onto the road beside the tracks.
	if not broken:
		for room: Dictionary in v.kit.rooms(v.variant):
			var r := TankKit.rect_of(room)
			var lit := 0.07
			if room.has("engine"):
				var rd := v.rider_of(str(room["engine"]))
				lit = 0.12 if rd != null and rd.in_band else 0.06
			var at := Vector2(o.x + r.get_center().x, g + 6.0)
			ground_glow(ci, at, r.size.x * 0.8 + 20.0, Color(1.0, 0.66, 0.36, lit))


## A flat glow lying on the road (an ellipse 0.14 as tall as wide) at `p`, `r` px wide each side.
static func ground_glow(ci: CanvasItem, p: Vector2, r: float, c: Color) -> void:
	ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.14))
	ci.draw_texture_rect(TankDraw.glow_tex(), Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0), false, c)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _lamps(ci: CanvasItem, v: TankView, state: TankState, o: Vector2) -> void:
	var blink := 0.75 + 0.25 * sin(v.time * 2.2)
	TankDraw.lamp(ci, o + v.kit.anchor(v.variant, "running_light_red_rear"), RED, blink)
	TankDraw.lamp(ci, o + v.kit.anchor(v.variant, "running_light_red_front"), RED, 0.9)
	TankDraw.lamp(ci, o + v.kit.anchor(v.variant, "running_light_green_rear"), GREEN, blink)
	var hl := TankWorldDraw.halt_lamp(v, state)
	if not is_nan(hl.x):
		TankDraw.glow_at(ci, hl, 6.0, Color(1.0, 0.85, 0.6, 0.7))
		TankDraw.glow_at(ci, hl + Vector2(0, 14), 30.0, Color(AMBER.r, AMBER.g, AMBER.b, 0.3))
	for tl in TankWorldDraw.turn_lamps(v, state):
		TankDraw.glow_at(ci, tl, 5.0, Color(1.0, 0.85, 0.6, 0.7))
		TankDraw.glow_at(ci, tl + Vector2(0, 16), 34.0, Color(AMBER.r, AMBER.g, AMBER.b, 0.26))
	if state.seg.seg == TankIds.SEG_DEPOT and not state.roam.active:
		for l: Dictionary in TankDepotDraw.lights(v):
			var p: Vector2 = l["p"]
			if str(l["kind"]) == "door":
				TankDraw.glow_at(ci, p, 34.0, Color(1.0, 0.62, 0.3, 0.3))
				ground_glow(ci, p + Vector2(0, 22), 60.0, Color(1.0, 0.62, 0.32, 0.3))
				continue
			TankDraw.glow_at(ci, p, 5.0, Color(1.0, 0.85, 0.6, 0.7))
			TankDraw.glow_at(ci, p + Vector2(0, 16), 34.0, Color(AMBER.r, AMBER.g, AMBER.b, 0.26))


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

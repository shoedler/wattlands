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
		if rd != null and rd.in_band:
			var c := WARM.lerp(TankHullDraw.slot_color(rd), 0.12)
			var fl := 0.9 + 0.1 * sin(v.time * 3.0 + rect.position.x)
			TankDraw.glow_at(ci, lamp, rect.size.x * 0.55, Color(c.r, c.g, c.b, 0.26 * fl))
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
	var feet := o + v.kit.anchor(v.variant, "turret_roof_commander_feet")
	var lens := feet - TankCrew.FEET + Vector2(22, 9) + Vector2(0.5, 0.5)
	var sweep := deg_to_rad(14.0 + 3.0 * sin(v.time * 0.45))
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
	var pool := hl + Vector2(150, 44)
	ci.draw_set_transform(pool, 0.0, Vector2(1.0, 0.18))
	ci.draw_texture_rect(
		TankDraw.glow_tex(),
		Rect2(Vector2(-110, -110), Vector2(220, 220)),
		false,
		Color(1.0, 0.75, 0.45, 0.42 * hk)
	)
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
		for p in TankWorldDraw.depot_lamps(v):
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
		var c := Vector2(
			r.get_center().x,
			lerpf(r.position.y + r.size.y * 0.35, r.end.y - 5.0, v.wreck_collapse(w))
		)
		var fl := 0.75 + 0.25 * sin(v.time * 9.0 + r.position.x) * sin(v.time * 5.3)
		TankDraw.glow_at(ci, c, 18.0 * k, Color(1.0, 0.42, 0.12, 0.5 * fl * k))
		TankDraw.glow_at(ci, c + Vector2(2, -2), 5.0, Color(1.0, 0.75, 0.35, 0.8 * fl * k))
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

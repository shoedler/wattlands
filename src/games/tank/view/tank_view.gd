class_name TankView
extends Node2D
## The 2D view at pixel_base 640 x 360 (brief 3): the dark 2.5D diorama. Sprite planes in depth
## (TankBackdrop), the cutaway tank (TankRig), enemies, wrecks, the Behemoth, shells with tracers,
## the trajectory dots in the gunner's colour (TankRowLayer), particles (TankFx) and additive halos
## (TankLights). It only reads TankGame.state; it never changes the rules.
##
## Time: positions come from a snapshot history (TankSnapHistory) drawn at TankRenderClock.render_t,
## a little behind the newest entry: a client records one entry per applied snapshot (the game's
## snapshot_applied signal), the host and SOLO one per sim tick they see, so motion is smooth at any
## frame rate. The local rider's own room runs from the live state (client_predict feeds it).
## Machinery moves with frame time, cosmetic randomness comes from TankFx.rng (seeded from ctx.seed).
##
## Layout (TankConst): ground line y 296, the hull's rear at screen x 16, enemies entering from the
## right (rear rushers from the left); the HUD covers only y 0-60 and 300-360.

const MAX_CUES_PER_FRAME := 24
const CUE_QUEUE_MAX := 64
const MAX_WRECKS := 6
const WRECK_TTL_S := 40.0
const WRECK_BURN_S := 12.0
## Wrecks sit on the back lane: scaled down, lifted and darkened toward the haze.
const WRECK_SCALE := 0.8
const WRECK_LIFT_PX := 9.0
## Charred dark grey, not black: the plate seams and the cool rim still read at half strength, so a
## wreck keeps its type's silhouette and detail.
const WRECK_TINT := Color(0.48, 0.46, 0.45)
## The depot gate stands behind the start (world x of its left edge).
const DEPOT_GATE_X := -90.0
## Ground props (craters, rubble, pairs of telegraph poles with their wires, fence posts and wire,
## flooded ruts; at the depot drums, barriers, crates and floodlights) every this many world px, by
## hash.
const PROP_CELL_PX := 210.0
## The depot yard's props on the tank's plane, every this many world px.
const DEPOT_PROP_CELL_PX := 150.0
## The aimed arc: a dot every TRAJECTORY_STEP_S of flight (about 16 px), so the dots read as one
## dotted arc in the gunner's colour, every third with a faint halo, not as stray pixels.
const TRAJECTORY_STEP_S := 0.045
const TRAJECTORY_DOTS := 34
## No HP bar floats on the tank's plane (the scene critic): damage shows on the sprite. A hit flashes
## the enemy warm for HIT_FLASH_S; below DAMAGE_SMOKE_FRAC of its HP its hull smokes, and below
## DAMAGE_FIRE_FRAC a small fire burns in it.
const HIT_FLASH_S := 0.16
const DAMAGE_SMOKE_FRAC := 0.5
const DAMAGE_FIRE_FRAC := 0.25
const HALO_RADIUS := {
	TankIds.SHELL_LIGHT: 9.0,
	TankIds.SHELL_HEAVY: 13.0,
	TankIds.SHELL_OVER: 18.0,
	TankIds.SHELL_SECONDARY: 6.0,
	TankIds.SHELL_ENEMY: 11.0,
	TankIds.SHELL_BOSS_MAIN: 26.0,
}
## Enemies on one lane keep at least this gap between them (else the next one steps back a lane).
const ENEMY_GAP_PX := 8.0
## A falling shell that vanishes this close to the ground landed in it.
const SHELL_LANDING_PX := 22.0
const WITHDRAW_PX_S := 46.0
const FADE_S := 1.5

var game: TankGame = null
var audio: TankAudio = null
## Turn off to drive advance() yourself (tests, screenshots).
var auto_process: bool = true

var backdrop: TankBackdrop = null
var world: Node2D = null
var props_layer: TankRowLayer = null
var enemies_layer: TankRowLayer = null
var rig: TankRig = null
var shots_layer: TankRowLayer = null
var fx: TankFx = null
var lights: TankLights = null
var overlay: TankPainter = null
var hub: TankRigHub = TankRigHub.new()
var history: TankSnapHistory = TankSnapHistory.new()
var clock: TankRenderClock = TankRenderClock.new()

## The camera's world x this frame (the interpolated hull x minus the rear's screen x).
var cam_x: float = 0.0
## Frames advanced (tests).
var frames: int = 0
## Wrecks: {"x": world left x, "w", "h", "code", "side", "age", "key"}.
var wrecks: Array[Dictionary] = []
## Screen rects of what is drawn: enemy id -> Rect2 (tests, effects).
var enemy_rects: Dictionary = {}
var geometry: TankGeometry = null

var _built: bool = false
var _dt: float = 0.0
var _time: float = 0.0
var _last_tick: int = -1
var _seg_index: int = -2
var _seen_enemies: Dictionary = {}
var _seen_shells: Dictionary = {}
var _cues: Array[Dictionary] = []
var _timers: Array[Dictionary] = []
var _fade_t: float = 0.0
var _fade_was: float = -1.0
var _barrage_t: float = 0.0
var _barrage_next: float = 0.0
var _withdraw_s: float = 0.0
var _prev_cam: float = 0.0
var _cam_primed: bool = false
var _traps_were_cleared: bool = false
var _boss_death_done: bool = false
## Enemy id -> [last hp seen, seconds its hit flash still shows].
var _hp_seen: Dictionary = {}


func _ready() -> void:
	audio = TankAudio.new()
	audio.game = game
	add_child(audio)
	if game != null:
		game.cue.connect(audio.on_cue)
		game.cue.connect(_on_cue)
		game.snapshot_applied.connect(_on_snapshot_applied)
	_build()


func _process(delta: float) -> void:
	if auto_process:
		advance(delta)


# --- Build ---------------------------------------------------------------------------------------------


func _build() -> void:
	if _built or game == null or game.state == null:
		return
	_built = true
	geometry = TankGeometry.load_default()
	fx = TankFx.new()
	fx.name = "Fx"
	fx.seed_rng(game.ctx.seed if game.ctx != null else 1)
	lights = TankLights.new()
	lights.name = "Lights"
	hub.fx = fx
	hub.lights = lights
	hub.local_peer = game.ctx.local_peer if game.ctx != null else 0
	if game.ctx != null:
		for p in game.ctx.players:
			hub.looks[p.slot_index] = {
				"color": p.color, "shape": p.shape, "pattern": p.pattern, "hollow": p.hollow
			}
		clock.min_delay_s = (
			TankRenderClock.CLIENT_DELAY_S
			if game.ctx.role == Wl.CLIENT
			else TankRenderClock.HOST_DELAY_S
		)
	backdrop = TankBackdrop.new()
	add_child(backdrop)
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	props_layer = _row_layer("Props")
	enemies_layer = _row_layer("Enemies")
	rig = TankRig.new()
	rig.assemble(game.state.hull.tank, hub)
	world.add_child(rig)
	shots_layer = _row_layer("Shots")
	world.add_child(fx)
	world.add_child(lights)
	add_child(backdrop.front)
	overlay = TankPainter.new()
	overlay.name = "Overlay"
	overlay.painter = _paint_overlay
	add_child(overlay)
	backdrop.set_near(TankBackdrop.backdrop_id(game.state))


func _row_layer(layer_name: String) -> TankRowLayer:
	var l := TankRowLayer.new()
	l.name = layer_name
	world.add_child(l)
	return l


# --- Frame ---------------------------------------------------------------------------------------------


## One frame of `delta` seconds: history and render clock, planes, rig, rows, effects, lights, audio.
func advance(delta: float) -> void:
	if game == null or game.state == null:
		return
	_build()
	if not _built:
		return
	var state := game.state
	frames += 1
	_dt = delta
	_time += delta
	fx.note_frame_time(delta)
	_poll_history(state)
	clock.advance(delta, history)
	var t := clock.render_t
	cam_x = _hull_x(state, t) - float(TankConst.REAR_SCREEN_X)
	var scroll := cam_x - _prev_cam if _cam_primed else 0.0
	_prev_cam = cam_x
	_cam_primed = true
	_on_segment(state)
	lights.begin()
	backdrop.set_world_x(cam_x)
	backdrop.advance(delta)
	var feed := rider_feed(state, t)
	rig.update(state, feed, delta)
	backdrop.hull_span = Vector2(rig.base_pos.x - 2.0, rig.base_pos.x + float(rig.hull_w) + 2.0)
	_process_cues(state)
	_process_timers(delta)
	_track_enemies(state, delta)
	_track_shells(state)
	_build_props(state)
	_build_enemies(state, t)
	_build_shots(state)
	_ambient(state, delta)
	_scenery(delta)
	fx.step(delta, scroll)
	_reflections()
	lights.wash = fx.flash
	lights.wash_color = fx.flash_color
	lights.wash_pos = fx.flash_pos
	lights.end()
	world.position = (rig.shake_offset * 0.6).round()
	_update_fade(delta)
	if audio != null:
		audio.update(state, delta, hub.local_peer, feed)


# --- History and time ---------------------------------------------------------------------------------


func _on_snapshot_applied(tick: int) -> void:
	if game != null and game.state != null:
		history.push(tick, game.state)
		_last_tick = tick


## The host and SOLO have no snapshot signal: record every sim tick the state reaches.
func _poll_history(state: TankState) -> void:
	if state.tick != _last_tick:
		history.push(state.tick, state)
		_last_tick = state.tick


func _hull_x(state: TankState, t: float) -> float:
	return history.hull_x_at(t, state.hull.x_px) if clock.is_set() else state.hull.x_px


## The x an enemy is drawn at (world, left edge).
func enemy_x(e: TankEnemyState) -> float:
	return history.enemy_x_at(e.id, clock.render_t, e.x_px) if clock.is_set() else e.x_px


func _boss_x(state: TankState, t: float) -> float:
	return history.boss_x_at(t, state.boss.x_px) if clock.is_set() else state.boss.x_px


## Where a shell is drawn (world).
func shell_pos(s: TankShellState) -> Vector2:
	var live := Vector2(s.x, s.y)
	return history.shell_at(s.id, clock.render_t, live) if clock.is_set() else live


## peer -> Vector2(raw_w, cadence): live for the host, SOLO and the local rider, the interpolated
## snapshot values for the other riders on a client.
func rider_feed(state: TankState, t: float) -> Dictionary:
	var out := {}
	var client := game.ctx != null and game.ctx.role == Wl.CLIENT
	for r in state.riders:
		var live := Vector2(r.raw_w, r.cadence_rpm)
		if client and r.peer != hub.local_peer and clock.is_set():
			live = history.rider_at(r.peer, t, live)
		out[r.peer] = live
	return out


# --- Segment ---------------------------------------------------------------------------------------------


func _on_segment(state: TankState) -> void:
	var idx := state.seg.phase_index
	backdrop.set_near(TankBackdrop.backdrop_id(state), cam_x)
	if idx == _seg_index:
		return
	_seg_index = idx
	wrecks.clear()
	_seen_enemies.clear()
	_seen_shells.clear()
	_traps_were_cleared = state.hull.traps_cleared


# --- Cues ---------------------------------------------------------------------------------------------------


func _on_cue(kind: String, data: Dictionary) -> void:
	_cues.append({"kind": kind, "data": data})
	if _cues.size() > CUE_QUEUE_MAX:
		_cues = _cues.slice(_cues.size() - CUE_QUEUE_MAX)


func _process_cues(state: TankState) -> void:
	var n := 0
	while not _cues.is_empty() and n < MAX_CUES_PER_FRAME:
		var c: Dictionary = _cues.pop_front()
		apply_cue(state, str(c["kind"]), c["data"])
		n += 1


## Turns one game event into effects: muzzle blasts, impacts, explosions, shakes.
func apply_cue(state: TankState, kind: String, data: Dictionary) -> void:
	match kind:
		TankEvents.SHOT:
			_cue_shot(state, data)
		TankEvents.HIT:
			_cue_hit(state, data)
		TankEvents.KILL:
			if int(data.get("e", 0)) == TankIds.BOSS_CODE:
				_boss_death()
		TankEvents.RAM:
			_cue_ram(state, data)
		TankEvents.BREAKDOWN:
			rig.add_shake(3.5)
			var at := rig.hull_point(Vector2(rig.hull_w * 0.4, 0.0))
			for i in 3:
				fx.explosion(at + Vector2(float(i) * 14.0 - 14.0, 4.0), false)
		TankEvents.REPAIRED:
			for i in 6:
				fx.impact_sparks(rig.hull_point(Vector2(30.0 + float(i) * 12.0, 8.0)), Vector2.UP)
		TankEvents.ROTATION:
			rig.flash_rooms()
		TankEvents.OVERRUN:
			_cue_overrun(data)
		TankEvents.BOSS_PHASE:
			rig.add_shake(3.0)
			if int(data.get("p", 0)) == TankIds.BOSS_PHASE_2:
				_schedule(0.1, _explode_boss_rear)


func _cue_shot(state: TankState, data: Dictionary) -> void:
	var sh := int(data.get("sh", 0))
	if int(data.get("s", -1)) >= 0:
		if sh == TankIds.SHELL_SECONDARY:
			var idx := 0
			for s in state.shells:
				if s.id == int(data.get("id", 0)):
					idx = 0 if s.vx >= 0.0 else 1
			rig.fire_secondary(idx)
		else:
			rig.fire_main(_shell_strength(sh))
		return
	var src := int(data.get("src", 0))
	if sh == TankIds.SHELL_BOSS_MAIN or src == 0:
		var heavy := sh == TankIds.SHELL_BOSS_MAIN
		var mz := _boss_muzzle(state, heavy)
		if heavy:
			fx.muzzle_blast(mz, Vector2.LEFT, 1.0, false)
			rig.add_shake(2.0)
		else:
			fx.small_blast(mz, Vector2.LEFT, TankPalette.FIRE)
		return
	var row: Variant = enemy_rects.get(src)
	var e := state.enemy(src)
	if row is Rect2 and e != null:
		fx.small_blast(
			_enemy_muzzle(e, row), Vector2(-1.0 if e.side > 0 else 1.0, -0.05), TankPalette.FIRE
		)


static func _shell_strength(sh: int) -> float:
	match sh:
		TankIds.SHELL_HEAVY:
			return 0.8
		TankIds.SHELL_OVER:
			return 1.0
	return 0.45


func _cue_hit(state: TankState, data: Dictionary) -> void:
	var dmg := float(data.get("dmg", 0))
	var wx := float(data.get("x", 0)) - cam_x
	match int(data.get("on", -1)):
		TankEvents.ON_TANK:
			var x := clampf(wx, rig.base_pos.x + 6.0, rig.base_pos.x + float(rig.hull_w) - 6.0)
			var at := Vector2(x, rig.base_pos.y + float(rig.hull_h) * 0.45)
			fx.impact_sparks(at, Vector2(1.0, -0.6).normalized())
			rig.hit(clampf(dmg / 20.0, 0.1, 1.0))
			if int(data.get("sh", 0)) == TankIds.SHELL_BOSS_MAIN:
				fx.explosion(at, true)
				rig.add_shake(4.0)
		TankEvents.ON_ENEMY:
			var r: Variant = enemy_rects.get(int(data.get("id", 0)))
			var at := Vector2(wx, float(TankConst.GROUND_Y) - 20.0)
			if r is Rect2:
				at = (r as Rect2).get_center()
			fx.impact_sparks(at, Vector2(1.0, -0.5).normalized())
		TankEvents.ON_BOSS:
			var at := _boss_part_center(state, TankBossState.part_of(int(data.get("id", 0))))
			fx.impact_sparks(at, Vector2(1.0, -0.4).normalized())
			if dmg >= 40.0:
				fx.explosion(at, false)
		TankEvents.ON_OBSTACLE:
			fx.impact_sparks(Vector2(wx, float(TankConst.GROUND_Y) - 12.0), Vector2.UP)
			fx.dirt_spray(Vector2(wx, float(TankConst.GROUND_Y)))


func _cue_ram(state: TankState, data: Dictionary) -> void:
	rig.add_shake(3.0)
	var front := rig.hull_point(Vector2(float(rig.hull_w) + 14.0, float(rig.hull_h) - 10.0))
	if int(data.get("ok", 0)) == 1:
		var r: Variant = enemy_rects.get(int(data.get("id", 0)))
		fx.explosion((r as Rect2).get_center() if r is Rect2 else front, false)
	else:
		fx.impact_sparks(front, Vector2.UP)
		fx.dirt_spray(Vector2(front.x, float(TankConst.GROUND_Y)))
	if state.hull.stall_s > 0.0:
		rig.hit(0.6)


func _cue_overrun(data: Dictionary) -> void:
	match TankIds.seg_of(int(data.get("sg", 0))):
		TankIds.SEG_ADVANCE:
			_fade_t = FADE_S
		TankIds.SEG_GUN_LINE:
			_barrage_t = 2.4
			_barrage_next = 0.0


func _boss_death() -> void:
	if _boss_death_done:
		return
	_boss_death_done = true
	for i in 7:
		_schedule(0.2 * float(i), _explode_boss_random)
	rig.add_shake(4.0)


func _explode_boss_random() -> void:
	if game == null or game.state == null or fx == null:
		return
	var bx := game.state.boss.x_px - cam_x
	fx.explosion(Vector2(bx + fx.r(20.0, 300.0), fx.r(150.0, 280.0)), true)
	rig.add_shake(3.0)


func _explode_boss_rear() -> void:
	if game == null or game.state == null or fx == null:
		return
	fx.explosion(_boss_part_center(game.state, 2), true)


func _schedule(delay: float, fn: Callable) -> void:
	_timers.append({"t": delay, "fn": fn})


func _process_timers(dt: float) -> void:
	var i := 0
	while i < _timers.size():
		_timers[i]["t"] = float(_timers[i]["t"]) - dt
		if float(_timers[i]["t"]) <= 0.0:
			var fn: Callable = _timers[i]["fn"]
			_timers.remove_at(i)
			fn.call()
		else:
			i += 1
	if _barrage_t > 0.0:
		_barrage_t -= dt
		_barrage_next -= dt
		if _barrage_next <= 0.0:
			_barrage_next = 0.22
			fx.explosion(Vector2(fx.r(260.0, 610.0), fx.r(230.0, 290.0)), false)
			fx.dirt_spray(Vector2(fx.r(260.0, 610.0), float(TankConst.GROUND_Y)))
			rig.add_shake(1.5)


func _update_fade(dt: float) -> void:
	if _fade_t > 0.0:
		_fade_t = maxf(0.0, _fade_t - dt)
	var f := fade_amount()
	if not is_equal_approx(f, _fade_was):
		_fade_was = f
		overlay.queue_redraw()


## The black fade of a tow, 0 .. 1: in over the first third, held, out over the last third.
func fade_amount() -> float:
	if _fade_t <= 0.0:
		return 0.0
	var k := 1.0 - _fade_t / FADE_S
	return clampf(minf(k / 0.33, (1.0 - k) / 0.33), 0.0, 1.0)


# --- Tracking: enemies, wrecks, shells -----------------------------------------------------------------


## Notes what is on screen and, for an enemy that vanished, a fireball and a wreck.
func _track_enemies(state: TankState, dt: float) -> void:
	var now := {}
	for e in state.enemies:
		now[e.id] = true
	for id: int in _seen_enemies.keys():
		if now.has(id):
			continue
		var info: Dictionary = _seen_enemies[id]
		_seen_enemies.erase(id)
		_hp_seen.erase(id)
		fx.forget("e%d" % id)
		var center: Vector2 = info["center"]
		fx.explosion(center, int(info["code"]) >= TankIds.enemy_code(TankIds.ENEMY_MEDIUM))
		rig.add_shake(1.0)
		_add_wreck(info)
	var i := 0
	while i < wrecks.size():
		wrecks[i]["age"] = float(wrecks[i]["age"]) + dt
		if float(wrecks[i]["age"]) > WRECK_TTL_S:
			fx.forget(str(wrecks[i]["key"]))
			wrecks.remove_at(i)
		else:
			i += 1


func _add_wreck(info: Dictionary) -> void:
	(
		wrecks
		. append(
			{
				"x": float(info["x"]),
				"w": int(info["w"]),
				"h": int(info["h"]),
				"code": int(info["code"]),
				"side": int(info["side"]),
				"age": 0.0,
				"key": "wreck%d" % int(info["id"]),
			}
		)
	)
	if wrecks.size() > MAX_WRECKS:
		var old: Dictionary = wrecks.pop_front()
		fx.forget(str(old["key"]))


## The screen top-left of wreck `w` drawn at size `sz` on the back lane.
func wreck_pos(w: Dictionary, sz: Vector2) -> Vector2:
	var full := float(w["w"])
	var x := float(w["x"]) - cam_x + (full - sz.x) * 0.5
	return Vector2(x, float(TankConst.GROUND_Y) - sz.y + 2.0 - WRECK_LIFT_PX)


## Shells that vanish while falling near the ground threw up dirt (judged on the state's latest
## position, not the delayed drawn one, so a shell that lands between two frames still counts).
func _track_shells(state: TankState) -> void:
	var now := {}
	for s in state.shells:
		now[s.id] = true
	for id: int in _seen_shells.keys():
		if now.has(id):
			continue
		var info: Dictionary = _seen_shells[id]
		_seen_shells.erase(id)
		var p: Vector2 = info["pos"]
		if p.y >= float(TankConst.GROUND_Y) - SHELL_LANDING_PX and float(info["vy"]) > 0.0:
			fx.dirt_spray(Vector2(p.x - cam_x, float(TankConst.GROUND_Y)))
	for s in state.shells:
		_seen_shells[s.id] = {"pos": Vector2(s.x, s.y), "vy": s.vy, "type": s.type}


# --- Rows ----------------------------------------------------------------------------------------------------


func _build_props(state: TankState) -> void:
	var rows: Array[Dictionary] = []
	var ground := float(TankConst.GROUND_Y)
	if state.seg.seg == TankIds.SEG_DEPOT or state.seg.phase_index == 0:
		var gs := TankSprites.size("depot_gate")
		var gate_pos := Vector2(DEPOT_GATE_X - cam_x, ground - gs.y + 2.0)
		rows.append(_sprite_row("depot_gate", gate_pos, gs, false, Color(0.78, 0.8, 0.84)))
	_halt_line(rows, state)
	_ground_props(rows, state)
	for ob in state.obstacles:
		_obstacle_row(rows, ob, state)
	for w in wrecks:
		var sprite := _enemy_sprite(int(w["code"]))
		var sz := Vector2(float(w["w"]), float(w["h"]))
		if sz.x <= 0.0:
			sz = TankSprites.size(sprite)
		# Wrecks lie on the back lane (smaller, higher, hazed and dark), so a live enemy keeping
		# station over one keeps its own silhouette; their fires stay on the wreck.
		sz = (sz * WRECK_SCALE).round()
		var pos := wreck_pos(w, sz)
		var burn := clampf(1.0 - float(w["age"]) / WRECK_BURN_S, 0.0, 1.0)
		rows.append(_sprite_row(sprite, pos, sz, int(w["side"]) < 0, WRECK_TINT))
		var hatch := pos + Vector2(sz.x * 0.5, sz.y * 0.28)
		if burn > 0.2:
			var halo := 20.0 + 10.0 * burn
			lights.add(hatch, halo, TankPalette.FIRE, 0.5 * burn)
		# Embers keep glowing in the open hatch after the flames die.
		var glow := 0.16 + 0.06 * sin(_time * 3.1 + float(int(w["x"]) % 17))
		lights.add(hatch, 7.0, TankPalette.FIRE, glow)
		lights.add(hatch, 2.5, TankPalette.AMBER, glow * 1.6)
	props_layer.set_rows(rows)


## The size of the halt line's lamp post (tests find the line by it).
const HALT_POST := Vector2(2, 24)


## The halt line of an Advance, standing where the hull's front is when its rear reaches the end of
## the road (TankHudModel.halt_distance_m is zero there): a row of concrete dragon's teeth across
## the road (three blunt pyramids, the nearest largest, lit on their upper-left faces, mud banked at
## their feet) and a short post at the line with a hooded amber lamp throwing its light down. No
## banner, nothing striped and nothing brighter than the concrete but the lamp (no flag).
func _halt_line(rows: Array[Dictionary], state: TankState) -> void:
	if state.seg.seg != TankIds.SEG_ADVANCE or state.content == null:
		return
	var length_m := float(state.content.segment(state.seg.phase_index).get("length_m", 0.0))
	if length_m <= 0.0:
		return
	var x := roundf(TankConst.m_to_px(length_m) + float(state.hull.hull_w) - cam_x)
	if x < -40.0 or x > float(TankConst.SCREEN_W) + 40.0:
		return
	var ground := float(TankConst.GROUND_Y)
	# Far to near: each tooth a little lower (nearer) and larger.
	var teeth: Array[Vector3] = [Vector3(12, -4, 9), Vector3(26, -2, 11), Vector3(5, 1, 13)]
	for t in teeth:
		_tooth(rows, Vector2(x + t.x, ground + t.y), t.z)
	var post := Rect2(Vector2(x, ground - HALT_POST.y), HALT_POST)
	rows.append({"t": "rect", "r": post, "c": TankPalette.IRON, "of": "halt_line"})
	rows.append(
		{
			"t": "rect",
			"r": Rect2(post.position, Vector2(1, post.size.y)),
			"c": TankPalette.STEEL_DARK
		}
	)
	# The hood: a dark cowl over the lamp so its light falls on the road, not up into the sky.
	var hood := post.position + Vector2(-3, -3)
	rows.append({"t": "rect", "r": Rect2(hood, Vector2(8, 3)), "c": TankPalette.IRON_DARK})
	rows.append({"t": "rect", "r": Rect2(hood, Vector2(8, 1)), "c": TankPalette.STEEL_DARK})
	rows.append(
		{"t": "rect", "r": Rect2(hood + Vector2(2, 3), Vector2(3, 1)), "c": TankPalette.AMBER}
	)
	var lamp := hood + Vector2(3.5, 4.0)
	lights.add(lamp, 6.0, TankPalette.GLOW_WARM, 0.6)
	lights.add(lamp + Vector2(0, 10), 26.0, TankPalette.AMBER, 0.32)


## One concrete dragon's tooth (a blunt pyramid seen from the side) standing on `foot` (its base's
## middle), `s` px tall: a lit upper-left face, a darker right face, a flat cap and a mud foot.
func _tooth(rows: Array[Dictionary], foot: Vector2, s: float) -> void:
	var half := s * 0.62
	var cap := s * 0.18
	var top := foot + Vector2(-s * 0.08, -s)
	var left_face := PackedVector2Array(
		[foot + Vector2(-half, 0), top + Vector2(-cap, 0), top + Vector2(cap * 0.3, 0), foot]
	)
	var right_face := PackedVector2Array(
		[foot, top + Vector2(cap * 0.3, 0), top + Vector2(cap, 0), foot + Vector2(half, 0)]
	)
	rows.append({"t": "poly", "pts": left_face, "c": TankPalette.STEEL_DARK})
	rows.append({"t": "poly", "pts": right_face, "c": TankPalette.IRON})
	rows.append(
		{
			"t": "line",
			"a": foot + Vector2(-half, -0.5),
			"b": top + Vector2(-cap, 0.5),
			"w": 1.0,
			"c": TankPalette.STEEL
		}
	)
	rows.append(
		{
			"t": "line",
			"a": top + Vector2(-cap, 0),
			"b": top + Vector2(cap, 0),
			"w": 1.0,
			"c": TankPalette.STEEL
		}
	)
	rows.append(
		{
			"t": "rect",
			"r": Rect2((foot + Vector2(-half - 1.0, -2.0)).round(), Vector2(half * 2.0 + 2.0, 3)),
			"c": TankPalette.MUD_DARK
		}
	)


## Props on the tank's plane, placed by a hash of the world cell (no RNG), so the road ahead is never
## empty: flooded craters that catch the lamps, rubble, a pair of telegraph poles with two wires
## sagging from one to the other (never a single pole with a wire ending in the air), fence posts
## strung with sagging wire, and flooded ruts (a dark sheet of water with a cold sky line and the
## near lights' reflection). The depot yard has its own (_depot_props).
func _ground_props(rows: Array[Dictionary], state: TankState) -> void:
	var ground := float(TankConst.GROUND_Y)
	if state.seg.seg == TankIds.SEG_DEPOT:
		_depot_props(rows, ground)
		return
	var first := int(floor(cam_x / PROP_CELL_PX)) - 1
	var last := int(floor((cam_x + float(TankConst.SCREEN_W)) / PROP_CELL_PX)) + 1
	for cell in range(first, last + 1):
		var h := TankBackdrop.cell_hash(cell, state.seg.phase_index + 17)
		var x := float(cell) * PROP_CELL_PX + float(h % 120) - cam_x
		match h % 8:
			0:
				var cs := TankSprites.size("prop_crater")
				rows.append(
					_sprite_row(
						"prop_crater", Vector2(x, ground - 9.0), cs, false, Color(0.7, 0.72, 0.78)
					)
				)
				# Flooded craters catch the nearby lamps.
				var mid := Vector2(x + cs.x * 0.5, ground)
				var wet := lights.intensity_near(mid, 60.0)
				if wet > 0.05:
					lights.add(
						mid + Vector2(0, 1), 22.0, TankPalette.COLD_LIGHT, minf(0.35, wet * 0.3)
					)
			1, 7:
				var rs := TankSprites.size("prop_rubble")
				rows.append(
					_sprite_row(
						"prop_rubble",
						Vector2(x, ground - rs.y + 3.0),
						rs,
						h % 2 == 0,
						Color(0.8, 0.8, 0.82)
					)
				)
			2:
				_poles(rows, x, ground, h)
			3, 4, 5:
				_fence(rows, x, ground, h)
			6:
				_puddle(rows, x, ground, h)


## Two telegraph poles 60-80 px apart, the far one leaning after a near miss, each with a short
## bracket and two insulators, and two wires sagging from the near pole's insulators to the far
## pole's: a stretch of line that ends on poles at both ends, on small mud heaps.
func _poles(rows: Array[Dictionary], x: float, ground: float, h: int) -> void:
	var gap := 60.0 + float(h % 21)
	var tips: Array[Array] = []
	for k in 2:
		var px := x + gap * float(k)
		var ht := 44.0 + float((h >> (3 + k * 4)) % 10)
		var lean := 0.0 if k == 0 else float((h >> 9) % 7) - 3.0
		var top := Vector2(px + lean, ground - ht)
		var foot := Vector2(px, ground + 1.0)
		rows.append({"t": "line", "a": foot, "b": top, "w": 3.0, "c": TankPalette.IRON_DARK})
		rows.append(
			{
				"t": "line",
				"a": foot + Vector2(-1, 0),
				"b": top + Vector2(-1, 0),
				"w": 1.0,
				"c": TankPalette.STEEL_DARK
			}
		)
		var bar := top.lerp(foot, 0.07)
		var l := bar + Vector2(-4, 0.5)
		var r := bar + Vector2(4, -0.5)
		rows.append({"t": "line", "a": l, "b": r, "w": 2.0, "c": TankPalette.IRON})
		for ins: Vector2 in [l, r]:
			rows.append(
				{
					"t": "rect",
					"r": Rect2((ins + Vector2(0, -1)).round(), Vector2(1, 1)),
					"c": TankPalette.STEEL_PALE
				}
			)
		tips.append([l, r])
		_mud_heap(rows, foot)
	for side in 2:
		var a: Vector2 = tips[0][side]
		var b: Vector2 = tips[1][side]
		var sag := 7.0 + float((h >> (5 + side)) % 4)
		var wire := PackedVector2Array()
		for k in 11:
			var t := float(k) / 10.0
			wire.append(a.lerp(b, t) + Vector2(0, 4.0 * sag * t * (1.0 - t)))
		rows.append({"t": "polyline", "pts": wire, "w": 1.0, "c": TankPalette.STEEL_DARK})


func _mud_heap(rows: Array[Dictionary], foot: Vector2) -> void:
	rows.append(
		{
			"t": "poly",
			"pts":
			PackedVector2Array(
				[
					foot + Vector2(-8, 1),
					foot + Vector2(-3, -3),
					foot + Vector2(4, -2),
					foot + Vector2(9, 1)
				]
			),
			"c": TankPalette.MUD_DARK
		}
	)


## The depot yard on the tank's plane, by a hash of the world cell: groups of fuel drums, concrete
## barrier blocks, stacked crates and floodlight posts throwing a cold light down on the apron.
func _depot_props(rows: Array[Dictionary], ground: float) -> void:
	var first := int(floor(cam_x / DEPOT_PROP_CELL_PX)) - 1
	var last := int(floor((cam_x + float(TankConst.SCREEN_W)) / DEPOT_PROP_CELL_PX)) + 1
	for cell in range(first, last + 1):
		var h := TankBackdrop.cell_hash(cell, 977)
		var x := roundf(float(cell) * DEPOT_PROP_CELL_PX + float(h % 90) - cam_x)
		match h % 5:
			0, 1:
				_drums(rows, x, ground, h)
			2:
				_barriers(rows, x, ground, h)
			3:
				_crates(rows, x, ground, h)
			4:
				_floodlight(rows, x, ground, h)


## Two to four upright fuel drums, rust-dark with two rim bands and a lit edge.
func _drums(rows: Array[Dictionary], x: float, ground: float, h: int) -> void:
	var n := 2 + h % 3
	for k in n:
		var dx := x + float(k) * 7.0 + float((h >> k) % 2)
		var body := TankPalette.RUST_DARK if k % 2 == 0 else TankPalette.IRON
		rows.append({"t": "rect", "r": Rect2(dx, ground - 9.0, 6, 9), "c": body})
		rows.append({"t": "rect", "r": Rect2(dx, ground - 9.0, 6, 1), "c": TankPalette.STEEL_DARK})
		rows.append({"t": "rect", "r": Rect2(dx, ground - 6.0, 6, 1), "c": TankPalette.COAL})
		rows.append({"t": "rect", "r": Rect2(dx, ground - 3.0, 6, 1), "c": TankPalette.COAL})
		rows.append({"t": "rect", "r": Rect2(dx + 5.0, ground - 8.0, 1, 7), "c": TankPalette.RUST})


## A row of two or three concrete barrier blocks (wide feet, sloped faces, a lit top).
func _barriers(rows: Array[Dictionary], x: float, ground: float, h: int) -> void:
	var n := 2 + h % 2
	for k in n:
		var bx := x + float(k) * 17.0
		var pts := PackedVector2Array(
			[
				Vector2(bx, ground + 1.0),
				Vector2(bx + 3.0, ground - 4.0),
				Vector2(bx + 4.0, ground - 9.0),
				Vector2(bx + 11.0, ground - 9.0),
				Vector2(bx + 12.0, ground - 4.0),
				Vector2(bx + 15.0, ground + 1.0)
			]
		)
		rows.append({"t": "poly", "pts": pts, "c": TankPalette.STEEL_DARK})
		rows.append({"t": "rect", "r": Rect2(bx + 4.0, ground - 9.0, 7, 1), "c": TankPalette.STEEL})


## Stacked wooden crates: two below, one on top.
func _crates(rows: Array[Dictionary], x: float, ground: float, h: int) -> void:
	var boxes: Array[Rect2] = [Rect2(x, ground - 9.0, 10, 9), Rect2(x + 11.0, ground - 8.0, 9, 8)]
	if h % 2 == 0:
		boxes.append(Rect2(x + 4.0, ground - 17.0, 10, 8))
	for b in boxes:
		rows.append({"t": "rect", "r": b, "c": TankPalette.MUD})
		var lid := Rect2(b.position, Vector2(b.size.x, 1))
		rows.append({"t": "rect", "r": lid, "c": TankPalette.MUD_PALE})
		var side := Rect2(b.position + Vector2(b.size.x - 1.0, 1.0), Vector2(1, b.size.y - 1.0))
		rows.append({"t": "rect", "r": side, "c": TankPalette.MUD_DARK})


## A floodlight post: a steel post with a hooded lamp head throwing a cold light onto the apron.
func _floodlight(rows: Array[Dictionary], x: float, ground: float, h: int) -> void:
	var ht := 40.0 + float(h % 9)
	rows.append({"t": "rect", "r": Rect2(x, ground - ht, 2, ht), "c": TankPalette.IRON})
	rows.append({"t": "rect", "r": Rect2(x, ground - ht, 1, ht), "c": TankPalette.STEEL_DARK})
	var head := Vector2(x - 3.0, ground - ht - 2.0)
	rows.append({"t": "rect", "r": Rect2(head, Vector2(8, 2)), "c": TankPalette.IRON_DARK})
	var lens := Rect2(head + Vector2(1, 2), Vector2(6, 1))
	rows.append({"t": "rect", "r": lens, "c": TankPalette.COLD_LIGHT})
	var lamp := head + Vector2(4, 3)
	lights.add(lamp, 6.0, TankPalette.WHITE_COLD, 0.5)
	lights.add(lamp + Vector2(0, 14), 30.0, TankPalette.COLD_LIGHT, 0.2)
	_mud_heap(rows, Vector2(x + 1.0, ground + 1.0))


## Fence posts (3-5, leaning) strung with two strands of sagging wire.
func _fence(rows: Array[Dictionary], x: float, ground: float, h: int) -> void:
	var n := 3 + h % 3
	var tops: Array[Vector2] = []
	for k in n:
		var px := x + float(k) * (11.0 + float((h >> k) % 5))
		var ht := 11.0 + float((h >> (k + 3)) % 6)
		var top := Vector2(px + float((h >> (k + 1)) % 3) - 1.0, ground - ht)
		tops.append(top)
		rows.append(
			{
				"t": "line",
				"a": Vector2(px, ground + 1.0),
				"b": top,
				"w": 2.0,
				"c": TankPalette.MUD_DARK
			}
		)
		rows.append(
			{
				"t": "rect",
				"r": Rect2(top.round() + Vector2(-1, 0), Vector2(1, 3)),
				"c": TankPalette.MUD_LIGHT
			}
		)
	for strand in 2:
		var pts := PackedVector2Array()
		for k in range(tops.size() - 1):
			for q in 5:
				var t := float(q) / 5.0
				pts.append(
					(
						tops[k].lerp(tops[k + 1], t)
						+ Vector2(0, 2.0 + 4.0 * float(strand) + sin(t * PI) * 2.0)
					)
				)
		pts.append(tops[tops.size() - 1] + Vector2(0, 2.0 + 4.0 * float(strand)))
		rows.append({"t": "polyline", "pts": pts, "w": 1.0, "c": TankPalette.STEEL_DARK})


## A flooded rut: a flat dark sheet of water on the road, its far edge catching the cold sky and its
## surface the near lights' colour.
func _puddle(rows: Array[Dictionary], x: float, ground: float, h: int) -> void:
	var w := 22.0 + float(h % 18)
	var y := ground - 2.0
	var pts := PackedVector2Array()
	for k in 13:
		var a := PI * float(k) / 12.0
		pts.append(Vector2(x + w * 0.5 - cos(a) * w * 0.5, y + 1.0 - sin(a) * 2.0))
	for k in 13:
		var a := PI * float(k) / 12.0
		pts.append(Vector2(x + w * 0.5 + cos(a) * w * 0.5, y + 1.0 + sin(a) * 1.0))
	rows.append({"t": "poly", "pts": pts, "c": TankPalette.COAL})
	rows.append(
		{
			"t": "line",
			"a": Vector2(x + 3.0, y - 0.5),
			"b": Vector2(x + w - 3.0, y - 0.5),
			"w": 1.0,
			"c": TankPalette.with_alpha(TankPalette.SLATE, 0.8)
		}
	)
	var mid := Vector2(x + w * 0.5, y)
	var wet := lights.intensity_near(mid, 80.0)
	if wet > 0.04:
		var k := minf(0.5, wet * 0.5)
		lights.add_line(
			mid + Vector2(-w * 0.3, 1), mid + Vector2(w * 0.3, 1), lights.near_color(), k
		)


func _obstacle_row(rows: Array[Dictionary], ob: TankObstacleState, state: TankState) -> void:
	if ob.cleared:
		return
	var kind := TankIds.obstacle_of(ob.code)
	if kind == TankIds.OBST_TANK_TRAPS:
		if not state.hull.traps_cleared:
			TankObstacleArt.traps(rows, ob.x_px - cam_x, float(ob.w), ob.id)
		return
	if kind != TankIds.OBST_WRECK and kind != TankIds.OBST_DRILL_WRECK:
		TankObstacleArt.wire(rows, ob.x_px - cam_x, float(ob.w), ob.id)
		return
	var sprite := "prop_wire"
	var tint := Color.WHITE
	match kind:
		TankIds.OBST_WRECK:
			sprite = "prop_wreck_barricade"
		TankIds.OBST_DRILL_WRECK:
			sprite = "prop_wreck_barricade"
			tint = Color(0.55, 0.56, 0.58)
		TankIds.OBST_TANK_TRAPS:
			sprite = "prop_tank_traps"
			if state.hull.traps_cleared:
				return
	var sz := TankSprites.size(sprite)
	var pos := Vector2(
		ob.x_px - cam_x + (float(ob.w) - sz.x) * 0.5, float(TankConst.GROUND_Y) - sz.y + 3.0
	)
	rows.append(_sprite_row(sprite, pos, sz, false, tint))
	if kind == TankIds.OBST_WRECK or kind == TankIds.OBST_DRILL_WRECK:
		fx.fire_and_smoke("ob%d" % ob.id, pos + Vector2(sz.x * 0.5, 4.0), 0.0, 0.5, _dt)


func _enemy_sprite(code: int) -> String:
	return TankSprites.enemy_id(TankIds.enemy_of(code))


func _build_enemies(state: TankState, t: float) -> void:
	var rows: Array[Dictionary] = []
	enemy_rects.clear()
	var dug_i := 0
	var ground := float(TankConst.GROUND_Y)
	# Dug-in guns are drawn first, on lanes behind the road, so a tank passing in front of a
	# revetment keeps its own silhouette; the rest share the road and step back to a second lane
	# only where they would overlap (a gap of ENEMY_GAP_PX at least), back lane drawn first.
	var order: Array[TankEnemyState] = []
	for e in state.enemies:
		if TankIds.enemy_of(e.code) == TankIds.ENEMY_DUGIN:
			order.append(e)
	var lanes := enemy_lanes(state)
	for want in [1, 0]:
		for e in state.enemies:
			if TankIds.enemy_of(e.code) != TankIds.ENEMY_DUGIN and int(lanes.get(e.id, 0)) == want:
				order.append(e)
	for e in order:
		var type := TankIds.enemy_of(e.code)
		var sprite := TankSprites.enemy_id(type)
		var sz := Vector2(float(e.w), float(e.h))
		if sz.x <= 0.0:
			sz = TankSprites.size(sprite)
		var lift := 0.0
		var dim := 1.0
		if type == TankIds.ENEMY_DUGIN:
			# Dug-ins alternate between two lanes behind the road so neighbours never merge.
			lift = 7.0 if dug_i % 2 == 0 else 13.0
			dim = 0.72 if dug_i % 2 == 0 else 0.6
			dug_i += 1
		elif int(lanes.get(e.id, 0)) == 1:
			# The back lane: higher and dimmer, toward the haze.
			lift = 6.0
			dim = 0.72
		var pos := Vector2(enemy_x(e) - cam_x, ground - sz.y + 2.0 - lift)
		var max_hp := enemy_max_hp(state, type)
		var hit := hit_flash(e, max_hp)
		var tint := Color(dim + 0.75 * hit, dim + 0.55 * hit, dim + 0.4 * hit)
		rows.append(_sprite_row(sprite, pos, sz, e.side < 0, tint))
		enemy_rects[e.id] = Rect2(pos.round(), sz)
		if max_hp > 0.0 and e.hp < max_hp * DAMAGE_SMOKE_FRAC:
			var burn := 0.35 if e.hp < max_hp * DAMAGE_FIRE_FRAC else 0.0
			var vent := pos + Vector2(sz.x * (0.45 if e.side > 0 else 0.55), sz.y * 0.35)
			fx.fire_and_smoke("e%d_dmg" % e.id, vent, burn, 0.7, _dt)
		_seen_enemies[e.id] = {
			"id": e.id,
			"x": enemy_x(e),
			"w": int(sz.x),
			"h": int(sz.y),
			"code": e.code,
			"side": e.side,
			"center": pos + sz * 0.5,
		}
		if e.telegraph_s > 0.0:
			_telegraph_light(state, e, type, Rect2(pos, sz))
		elif e.mode in [TankIds.EM_ENTER, TankIds.EM_MOVE, TankIds.EM_BACKOFF, TankIds.EM_LEAVE]:
			var stack := pos + Vector2(sz.x * (0.25 if e.side > 0 else 0.7), 2.0)
			fx.exhaust("e%d" % e.id, stack, 0.4, _dt)
	_boss_rows(state, t, rows)
	enemies_layer.set_rows(rows)


## The hit flash of `e`, 1 at a hit fading to 0 over HIT_FLASH_S: its HP dropped since the last
## frame (an enemy first seen damaged does not flash).
func hit_flash(e: TankEnemyState, max_hp: float) -> float:
	if max_hp <= 0.0:
		return 0.0
	var seen: Array = _hp_seen.get(e.id, [e.hp, 0.0])
	var left := maxf(float(seen[1]) - _dt, 0.0)
	if e.hp < float(seen[0]) - 0.01:
		left = HIT_FLASH_S
	_hp_seen[e.id] = [e.hp, left]
	return clampf(left / HIT_FLASH_S, 0.0, 1.0)


## The road lane of every enemy that is not dug in, enemy id -> 0 (front) or 1 (back): left to right,
## an enemy takes the front lane unless it would come within ENEMY_GAP_PX of the last one there, then
## the back lane on the same rule, else whichever lane's last enemy ends farther left.
func enemy_lanes(state: TankState) -> Dictionary:
	var road: Array[TankEnemyState] = []
	for e in state.enemies:
		if TankIds.enemy_of(e.code) != TankIds.ENEMY_DUGIN:
			road.append(e)
	road.sort_custom(_drawn_left_of)
	var ends: Array[float] = [-INF, -INF]
	var out := {}
	for e in road:
		var x := enemy_x(e)
		var w := float(e.w) if e.w > 0 else TankSprites.size(_enemy_sprite(e.code)).x
		var lane := 0
		if x < ends[0] + ENEMY_GAP_PX:
			lane = 1 if (x >= ends[1] + ENEMY_GAP_PX or ends[1] < ends[0]) else 0
		ends[lane] = maxf(ends[lane], x + w)
		out[e.id] = lane
	return out


func _drawn_left_of(a: TankEnemyState, b: TankEnemyState) -> bool:
	return enemy_x(a) < enemy_x(b)


## Maximum HP of an enemy type after the tank's scale (clients never get it in the snapshot).
func enemy_max_hp(state: TankState, type: String) -> float:
	if state.content == null:
		return 0.0
	var hp := float(state.content.enemy_def(type).get("hp", 0))
	return hp * state.content.enemy_scale(state.hull.tank)


func _enemy_muzzle(e: TankEnemyState, r: Rect2) -> Vector2:
	var m := geometry.enemy_muzzle(TankSprites.enemy_id(TankIds.enemy_of(e.code)))
	return Vector2(r.end.x - m.x if e.side < 0 else r.position.x + m.x, r.position.y + m.y)


func _telegraph_light(state: TankState, e: TankEnemyState, type: String, r: Rect2) -> void:
	var total := float(state.content.enemy_def(type).get("telegraph_s", 3.0))
	var k := 1.0 - clampf(e.telegraph_s / maxf(total, 0.1), 0.0, 1.0)
	var blink := 0.55 + 0.45 * sin(_time * (6.0 + 14.0 * k))
	var cold := type == TankIds.ENEMY_DESTROYER
	var col := TankPalette.COLD_LIGHT if cold else TankPalette.FIRE
	lights.add(_enemy_muzzle(e, r), 10.0 + 14.0 * k, col, (0.25 + 0.7 * k) * blink)


func _boss_rows(state: TankState, t: float, rows: Array[Dictionary]) -> void:
	var b := state.boss
	if b.phase == TankIds.BOSS_NONE:
		_boss_death_done = false
		_withdraw_s = 0.0
		return
	if b.phase == TankIds.BOSS_WITHDRAWN:
		_withdraw_s += _dt
	var origin := Vector2(
		_boss_x(state, t) - cam_x + _withdraw_s * WITHDRAW_PX_S,
		float(TankConst.GROUND_Y) - _boss_height()
	)
	var dead := b.phase == TankIds.BOSS_DEAD
	var tint := Color(0.5, 0.5, 0.52) if dead else Color.WHITE
	for i in 3:
		var rr := geometry.boss_part_rect(i)
		var broken := b.bogie_hp[i] <= 0.0
		var sprite := "boss_bogie_broken" if broken else "boss_bogie"
		rows.append(_sprite_row(sprite, origin + rr.position, rr.size, false, tint))
		if broken:
			var at := origin + rr.position + Vector2(rr.size.x * 0.5, 4.0)
			fx.fire_and_smoke("boss%d" % i, at, 0.0 if dead else 0.4, 0.9, _dt)
	_boss_running_gear(b, origin, rows)
	var turret := geometry.boss_part_rect(TankBossState.TURRET_PART)
	var muzzle := origin + geometry.boss_muzzle()
	# The barrel runs level from the gun block to the muzzle (no stair-stepped slope).
	var base := Vector2(origin.x + turret.position.x + 8.0, muzzle.y)
	# The main gun: a 4 px tube with a dark underside, a steel body and one lit top row, a collar
	# where it leaves the gun block and a muzzle brake block, so it reads as a gun and not a rule.
	rows.append({"t": "line", "a": base, "b": muzzle, "w": 5.0, "c": TankPalette.IRON_DARK})
	rows.append(
		{
			"t": "line",
			"a": base + Vector2(0, -1),
			"b": muzzle + Vector2(0, -1),
			"w": 2.0,
			"c": TankPalette.IRON
		}
	)
	rows.append(
		{
			"t": "line",
			"a": base + Vector2(0, -2),
			"b": muzzle + Vector2(0, -2),
			"w": 1.0,
			"c": TankPalette.STEEL_DARK
		}
	)
	rows.append(
		{"t": "line", "a": base, "b": base + Vector2(-12, 0), "w": 9.0, "c": TankPalette.IRON}
	)
	rows.append(
		{"t": "rect", "r": Rect2(muzzle + Vector2(-2, -5), Vector2(11, 9)), "c": TankPalette.IRON}
	)
	rows.append(
		{"t": "rect", "r": Rect2(muzzle + Vector2(-2, -5), Vector2(11, 1)), "c": TankPalette.STEEL}
	)
	rows.append(
		{"t": "rect", "r": Rect2(muzzle + Vector2(2, -4), Vector2(2, 7)), "c": TankPalette.SOOT}
	)
	rows.append(_sprite_row("boss_hull", origin, TankSprites.size("boss_hull"), false, tint))
	_boss_skirt(origin, rows, dead)
	var tur_broken := b.turret_hp <= 0.0
	var tur_sprite := "boss_turret_broken" if tur_broken else "boss_turret"
	rows.append(_sprite_row(tur_sprite, origin + turret.position, turret.size, false, tint))
	if not tur_broken:
		_boss_mantlet(Vector2(origin.x + turret.position.x, muzzle.y), rows)
	if tur_broken:
		var at := origin + turret.position + turret.size * 0.5
		fx.fire_and_smoke("boss_t", at, 0.0 if dead else 0.6, 1.1, _dt)
	if b.telegraph_s > 0.0:
		var k := 1.0 - clampf(b.telegraph_s / 6.0, 0.0, 1.0)
		var blink := 0.6 + 0.4 * sin(_time * (5.0 + 12.0 * k))
		lights.add(muzzle, 22.0 + 40.0 * k, TankPalette.FIRE, (0.3 + 0.7 * k) * blink)
		lights.add(muzzle, 10.0 + 10.0 * k, TankPalette.GLOW_WARM, 0.5 * k * blink)
	if dead:
		_boss_death()


## The Behemoth's track run between its three bogies: a belt top and bottom joining each pair of
## neighbouring bogies and two road wheels in each gap, so the running gear reads as one long
## tracked run under the hull, not as three railcar trucks (a broken bogie breaks its joins).
func _boss_running_gear(b: TankBossState, origin: Vector2, rows: Array[Dictionary]) -> void:
	for i in 2:
		if b.bogie_hp[i] <= 0.0 or b.bogie_hp[i + 1] <= 0.0:
			continue
		var ra := geometry.boss_part_rect(i)
		var rb := geometry.boss_part_rect(i + 1)
		var x0 := origin.x + ra.end.x - 4.0
		var x1 := origin.x + rb.position.x + 4.0
		var y_top := origin.y + ra.position.y + ra.size.y * 0.42
		var y_bot := origin.y + ra.end.y - 2.0
		for k in 2:
			var cx := lerpf(x0, x1, 0.3 + 0.4 * float(k))
			var c := Vector2(cx, y_bot - 7.0)
			rows.append({"t": "poly", "pts": _circle_pts(c, 6.0, 12), "c": TankPalette.IRON_DARK})
			rows.append({"t": "poly", "pts": _circle_pts(c, 2.0, 8), "c": TankPalette.STEEL_DARK})
		for y: float in [y_top, y_bot]:
			rows.append(
				{
					"t": "line",
					"a": Vector2(x0, y),
					"b": Vector2(x1, y),
					"w": 3.0,
					"c": TankPalette.COAL
				}
			)
			rows.append(
				{
					"t": "line",
					"a": Vector2(x0, y - 1.0),
					"b": Vector2(x1, y - 1.0),
					"w": 1.0,
					"c": TankPalette.IRON
				}
			)


## Skirt plates along the Behemoth's foot over the dark wheel arches: a riveted band with a lit top
## edge and a mud-dark bottom, the bogies' wheels showing below it.
func _boss_skirt(origin: Vector2, rows: Array[Dictionary], dead: bool) -> void:
	var first := geometry.boss_part_rect(0)
	var last := geometry.boss_part_rect(2)
	var x0 := origin.x + first.position.x - 4.0
	var x1 := origin.x + last.end.x - 2.0
	var y := origin.y + first.position.y + 1.0
	var k := 0.55 if dead else 1.0
	rows.append(
		{
			"t": "rect",
			"r": Rect2(x0, y, x1 - x0, 11),
			"c": TankPalette.darkened(TankPalette.IRON, 1.0 - k)
		}
	)
	rows.append(
		{
			"t": "rect",
			"r": Rect2(x0, y, x1 - x0, 1),
			"c": TankPalette.darkened(TankPalette.STEEL, 1.0 - k)
		}
	)
	rows.append({"t": "rect", "r": Rect2(x0, y + 9.0, x1 - x0, 2), "c": TankPalette.MUD_DARK})
	var px := x0 + 3.0
	var plate := 0
	while px < x1 - 2.0:
		rows.append(
			{
				"t": "rect",
				"r": Rect2(px, y + 3.0, 1, 1),
				"c": TankPalette.darkened(TankPalette.STEEL_LIGHT, 1.0 - k)
			}
		)
		plate += 1
		if plate % 8 == 0:
			rows.append({"t": "rect", "r": Rect2(px + 2.0, y + 1.0, 1, 8), "c": TankPalette.COAL})
		px += 6.0


## A cast mantlet where the Behemoth's gun leaves its turret (centred on the barrel's line).
func _boss_mantlet(at: Vector2, rows: Array[Dictionary]) -> void:
	var r := Rect2(at + Vector2(-9, -8), Vector2(14, 16))
	rows.append({"t": "rect", "r": r, "c": TankPalette.IRON})
	rows.append({"t": "rect", "r": Rect2(r.position, Vector2(r.size.x, 1)), "c": TankPalette.STEEL})
	rows.append(
		{"t": "rect", "r": Rect2(r.position, Vector2(1, r.size.y)), "c": TankPalette.STEEL_DARK}
	)
	rows.append(
		{
			"t": "rect",
			"r": Rect2(r.position + Vector2(0, r.size.y - 2), Vector2(r.size.x, 2)),
			"c": TankPalette.COAL
		}
	)
	rows.append(
		{
			"t": "rect",
			"r": Rect2(r.position + Vector2(3, 4), Vector2(1, 1)),
			"c": TankPalette.STEEL_PALE
		}
	)
	rows.append(
		{
			"t": "rect",
			"r": Rect2(r.position + Vector2(3, 11), Vector2(1, 1)),
			"c": TankPalette.STEEL_PALE
		}
	)


static func _circle_pts(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		pts.append(c + Vector2.from_angle(TAU * float(i) / float(n)) * r)
	return pts


func _boss_height() -> float:
	var h := 0.0
	for i in 3:
		h = maxf(h, geometry.boss_part_rect(i).end.y)
	return maxf(h, 100.0)


func _boss_origin(state: TankState) -> Vector2:
	var bx := _boss_x(state, clock.render_t) - cam_x + _withdraw_s * WITHDRAW_PX_S
	return Vector2(bx, float(TankConst.GROUND_Y) - _boss_height())


## The centre of boss part `index` (0..2 bogies, 3 turret) on screen.
func _boss_part_center(state: TankState, index: int) -> Vector2:
	var rr := geometry.boss_part_rect(clampi(index, 0, 3))
	return _boss_origin(state) + rr.position + rr.size * 0.5


func _boss_muzzle(state: TankState, main: bool) -> Vector2:
	var m := geometry.boss_muzzle() if main else geometry.boss_secondary_muzzle()
	return _boss_origin(state) + m


func _sprite_row(id: String, pos: Vector2, size: Vector2, flip: bool, tint: Color) -> Dictionary:
	return {"t": "sprite", "id": id, "pos": pos.round(), "size": size, "flip": flip, "tint": tint}


## Shells with tracers and halos, and the trajectory dots in the gunner's colour.
func _build_shots(state: TankState) -> void:
	var rows: Array[Dictionary] = []
	for s in state.shells:
		var p := shell_pos(s) - Vector2(cam_x, 0.0)
		var v := Vector2(s.vx, s.vy)
		var dir := v.normalized() if v.length() > 1.0 else Vector2.RIGHT
		var core: Color = TankPalette.TRACER.get(s.type, TankPalette.AMBER)
		# A glowing tracer: a 3 px streak (2 px for secondaries) fading back from a white-hot head,
		# a 1 px hot core along its front half and a halo, unlike the 2 px trajectory dots.
		var tail := 16.0
		if s.type == TankIds.SHELL_BOSS_MAIN:
			tail = 26.0
		elif s.type == TankIds.SHELL_OVER:
			tail = 20.0
		elif s.type == TankIds.SHELL_SECONDARY:
			tail = 10.0
		var w := 2.0 if s.type == TankIds.SHELL_SECONDARY else 3.0
		var a := p - dir * tail
		var m := p - dir * tail * 0.45
		rows.append({"t": "line", "a": a, "b": m, "w": w, "c": TankPalette.with_alpha(core, 0.3)})
		rows.append({"t": "line", "a": m, "b": p, "w": w, "c": TankPalette.with_alpha(core, 0.9)})
		rows.append({"t": "line", "a": m, "b": p, "w": 1.0, "c": TankPalette.WHITE_WARM})
		rows.append({"t": "rect", "r": Rect2(p - Vector2(1, 1), Vector2(3, 3)), "c": Color.WHITE})
		lights.add(p, float(HALO_RADIUS.get(s.type, 9.0)) * 1.4, core, 0.9)
		lights.add(m, 8.0, core, 0.5)
	_trajectory(state, rows)
	shots_layer.set_rows(rows)


## The aimed arc as dots from the muzzle, in the gunner's slot colour.
func _trajectory(state: TankState, rows: Array[Dictionary]) -> void:
	var hl := state.hull
	if hl.target_id == 0 or rig.turret.is_turning() or hl.breakdown:
		return
	var v0 := state.content.num("tanks", "gun.shell_speed_px_s", 360.0)
	var g := state.content.num("tanks", "gun.gravity_px_s2", 300.0)
	var facing := 1 if rig.turret.scale.x >= 0.0 else -1
	var vel := TankBallistics.velocity(v0, rig.turret.elev, facing)
	var from := rig.muzzle_layer()
	var base_alpha := 0.9 if hl.loaded != TankIds.SHELL_NONE else 0.55
	var col := gunner_color(state)
	for i in range(1, TRAJECTORY_DOTS + 1):
		var p := TankBallistics.position(from, vel, g, float(i) * TRAJECTORY_STEP_S)
		if p.y > float(TankConst.GROUND_Y) or p.x < 0.0 or p.x > float(TankConst.SCREEN_W):
			break
		var a := base_alpha * (1.0 - 0.75 * float(i) / float(TRAJECTORY_DOTS + 1))
		rows.append(
			{"t": "rect", "r": Rect2(p.floor(), Vector2(2, 2)), "c": TankPalette.with_alpha(col, a)}
		)
		if i % 3 == 0:
			lights.add(p + Vector2(1, 1), 5.0, col, 0.3 * a)


## The slot colour of the gunner (the dynamo's or the Bulwark's rider).
func gunner_color(state: TankState) -> Color:
	var st := state.station(TankIds.ENGINE_DYNAMO)
	if st == null:
		st = state.station(TankIds.ENGINE_BULWARK)
	var slot := st.slot if st != null and st.slot >= 0 else 0
	return hub.look(slot).get("color", Color.WHITE)


# --- Ambient effects ---------------------------------------------------------------------------------------


func _ambient(state: TankState, dt: float) -> void:
	for w in wrecks:
		var burn := clampf(1.0 - float(w["age"]) / WRECK_BURN_S, 0.0, 1.0)
		var at := Vector2(
			float(w["x"]) - cam_x + float(w["w"]) * 0.5,
			float(TankConst.GROUND_Y) - WRECK_LIFT_PX - float(w["h"]) * WRECK_SCALE * 0.8
		)
		fx.fire_and_smoke(str(w["key"]), at, burn, 1.0 if burn > 0.0 else 0.5, dt)
	if state.hull.traps_cleared and not _traps_were_cleared:
		var tp := Vector2(
			rig.base_pos.x + float(rig.hull_w) + 30.0, float(TankConst.GROUND_Y) - 8.0
		)
		fx.dirt_spray(tp)
		fx.explosion(tp, false)
	_traps_were_cleared = state.hull.traps_cleared


## Wet ground and wet steel (brief 3 "Light"): every bright halo near the ground drops a soft
## vertical streak of its colour onto the wet road below it, and when a muzzle flash or a fire is
## close the hull's and the turret's top edges catch a faint specular line.
func _reflections() -> void:
	var ground := float(TankConst.GROUND_Y)
	lights.add_reflections(ground - 1.0, ground - 70.0, 0.3)
	var roof := rig.hull_roof()
	if roof.size.x <= 0.0:
		return
	var mid := roof.position + Vector2(roof.size.x * 0.5, 0)
	var wet := lights.intensity_near(mid, roof.size.x * 0.5 + 40.0) + fx.flash * 1.5
	if wet > 0.08:
		var k := minf(0.3, wet * 0.16)
		var a := roof.position + rig.shake_offset * 0.6
		lights.add_line(a, a + Vector2(roof.size.x, 0), lights.near_color(), k)


## Lights and fires of the near plane (scenery), with flames on the far plane.
func _scenery(dt: float) -> void:
	var sl := backdrop.scenery_lights
	sl.begin()
	var near_lights := TankBackdrop.scenery(
		backdrop.near_id, cam_x, float(TankConst.SCREEN_W), backdrop.near_offset
	)
	for l: Dictionary in near_lights:
		var lp: Vector2 = l["pos"]
		if lp.x < -50.0 or lp.x > float(TankConst.SCREEN_W) + 50.0:
			continue
		var flick := 1.0
		# A fire behind the hull would throw its back-plane flames over the cutaway: none there.
		if bool(l["fire"]) and not _behind_hull(lp):
			flick = 0.8 + 0.2 * sin(_time * 9.0 + float(int(l["seed"]) % 13))
			fx.fire_and_smoke(
				"sc%d" % int(l["seed"]), l["pos"], 0.6, 0.5, dt, TankParticles.PLANE_BACK
			)
		sl.add(l["pos"], float(l["radius"]), l["color"], float(l["intensity"]) * flick)
	sl.add_reflections(TankBackdrop.NEAR_BOTTOM_Y - 22.0, 200.0, 0.22)
	sl.end()


## True when screen point `p` lies behind the tank's hull and turret (with a margin).
func _behind_hull(p: Vector2) -> bool:
	var r := Rect2(rig.base_pos + Vector2(-12, -50), Vector2(rig.hull_w + 30, rig.hull_h + 60))
	return r.has_point(p)


func _paint_overlay(item: Node2D) -> void:
	item.draw_texture_rect(
		TankProcTex.vignette(), Rect2(0, 0, TankConst.SCREEN_W, TankConst.SCREEN_H), false
	)
	var f := fade_amount()
	if f > 0.01:
		item.draw_rect(Rect2(0, 0, TankConst.SCREEN_W, TankConst.SCREEN_H), Color(0, 0, 0, f))

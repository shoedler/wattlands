class_name SiegeView
extends Node2D
## Castellum Rotae's 2D view (docs/games/siege.md 3 "View"), drawn in the platform's
## PixelViewport (960 x 540 art pixels, flexing with the window: SiegeViewMath.view_offset keeps
## this node's origin, the design frame's top-left, centred on the canvas, and fit_canvas() moves
## what follows it): the baked world (SiegeV2WorldLayer), every machine
## (SiegeV2Machines), the attackers (SiegeV2Crowd), the shots (SiegeV2Shots) and the tilt-shift
## pass (SiegeV2TiltShift), with Siege's sound (SiegeAudio). It only reads the state
## (contracts/STATE_V2.md) and listens to SiegeGame.cue; on a client the enemies come from the
## snapshot history (SiegeSnapHistory), drawn between snapshots.
##
## What it shows (SiegeViewMath has the formulas):
##   - each rota turning at rim speed 1.2 m/s x P_eff / 250 W (at most 3 m/s) in its slot's hue
##     (timber for an empty slot), with 1 to 3 walkers by P_eff (150 / 300 W, 20 W hysteresis),
##     their stride 1:1 with the rider's cadence;
##   - each rider's powered path to the station they target, lit through the 2 s reconnect, the
##     mine in breaks;
##   - the stations at their yaw and animation phase, the mine and the pump cycling with m, the
##     tar curtain and coat, the gate's damage stage, the pads;
##   - the enemies (facing their travel), a docked tower and its boarders on the wall;
##   - shots replayed from `shot` cues, with impacts;
##   - in the cool-down, the fort's people marching out over the bridge.

## Boarders drawn on the wall walk while a docked tower lands them.
const BOARDERS := 5
const WALL_WALK := Vector3(0, 58.4, 9.0)
## The march home: people, spacing (m) and pace (m/s).
const MARCHERS := 14
const MARCH_GAP_M := 1.6
const MARCH_MPS := 1.3
## The mine's and the pump's cycles per second at m = 1.
const MINE_HZ := 0.9
const PUMP_HZ := 0.5
## Attackers fade in over the road's first metres: on a wide canvas the road's start is on screen.
const ARRIVE_M := 6.0

var game: SiegeGame = null
var state: SiegeState = null
var path: SiegePath = null
var bank: SiegeBakeBank = null
var world: SiegeV2WorldLayer = null
var machines: SiegeV2Machines = null
var crowd: SiegeV2Crowd = null
var shots: SiegeV2Shots = null
var tilt: SiegeV2TiltShift = null
var audio: SiegeAudio = null
## The time the view draws (host game seconds): the sim clock on the host, the history's render
## clock on a client.
var clock_s: float = 0.0
var wheel_deg := PackedFloat32Array([0, 0, 0, 0])
var walker_count := PackedInt32Array([0, 0, 0, 0])
var walk_phase := PackedFloat32Array([0, 0, 0, 0])
## Per slot: the crank that sets the walkers' frames and the wheel's strokes (one 4-frame walk cycle
## per crank revolution). The wheel stays by watts: the wheel is load, the walkers are legs.
var cranks: Array[CrankClock] = [
	CrankClock.new(), CrankClock.new(), CrankClock.new(), CrankClock.new()
]
## Per slot: 1 while the rider is in rescue (the walkers stumble, brief 2.4).
var stumbling := PackedInt32Array([0, 0, 0, 0])
var mine_phase: float = 0.0
var pump_phase: float = 0.0
## Seconds since the march home began (negative: not marching).
var march_s: float = -1.0
## The art canvas the view is laid out on.
var canvas: Vector2i = SiegeBakeBank.ART_SIZE

var _built: bool = false
var _tick_seen: int = -1
var _since_tick: float = 0.0


func bind(p_state: SiegeState, p_path: SiegePath) -> void:
	state = p_state
	path = p_path
	if game != null and not game.cue.is_connected(_on_cue):
		game.cue.connect(_on_cue)
	if is_inside_tree():
		_build()


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	bank = SiegeBakeBank.shared()
	world = SiegeV2WorldLayer.new(bank)
	world.name = "World"
	machines = SiegeV2Machines.new(bank)
	machines.name = "Machines"
	crowd = SiegeV2Crowd.new(bank)
	crowd.name = "Crowd"
	shots = SiegeV2Shots.new(bank)
	shots.name = "Shots"
	shots.path = path
	shots.content = state.content if state != null else null
	tilt = SiegeV2TiltShift.new(SiegeBakeBank.ART_SIZE, bank.manifest.get("focus", {}))
	tilt.name = "TiltShift"
	tilt.enabled = tilt_shift_option()
	audio = SiegeAudio.new()
	audio.name = "Audio"
	audio.rng_seed = SeededRng.derive(game.ctx.seed, "siege:audio") if _has_ctx() else 0
	for n: Node in [world, machines, crowd, shots, tilt, audio]:
		add_child(n)
	fit_canvas(self, bank, world, tilt, _canvas_now())
	canvas = _canvas_now()
	update(0.0)


## Lays a view root and its world and screen pass out on an art canvas.
static func fit_canvas(
	root: Node2D,
	p_bank: SiegeBakeBank,
	p_world: SiegeV2WorldLayer,
	p_tilt: SiegeV2TiltShift,
	art: Vector2i
) -> void:
	var offset := SiegeViewMath.view_offset(art)
	root.position = Vector2(offset)
	p_bank.set_view_offset(offset)
	p_world.set_canvas(art, offset)
	p_tilt.set_canvas(art, offset)


## The canvas this view is on: the PixelViewport's SubViewport (the base outside one).
func _canvas_now() -> Vector2i:
	var vp := get_viewport() if is_inside_tree() else null
	return (vp as SubViewport).size if vp is SubViewport else SiegeBakeBank.ART_SIZE


## The local rider's tilt_shift option (on unless they turned it off).
func tilt_shift_option() -> bool:
	if game == null or game.ctx == null:
		return true
	var me := game.ctx.local_player()
	if me == null or not (me.options is Dictionary):
		return true
	return bool(me.options.get("tilt_shift", true))


func _process(delta: float) -> void:
	update(delta)


func _has_ctx() -> bool:
	return game != null and game.ctx != null


func _is_client() -> bool:
	return game != null and game.ctx != null and game.ctx.role == Wl.CLIENT


## One frame: the clock, the wheels, the machines, the crowd, the shots and the sound.
func update(delta: float) -> void:
	if game != null and game.state != null and game.state != state:
		state = game.state
		path = state.path
	if not _built or state == null:
		return
	var now := _canvas_now()
	if now != canvas:
		canvas = now
		fit_canvas(self, bank, world, tilt, canvas)
	_advance_clock(delta)
	_update_wheels(delta)
	_update_machines(delta)
	_update_crowd(delta)
	shots.set_time(clock_s)
	if audio != null:
		audio.update(state, delta, game.ctx.local_peer if _has_ctx() else 0, self)


func _advance_clock(delta: float) -> void:
	if _is_client() and game.history != null and not game.history.is_empty():
		clock_s = game.history.advance(delta)
		return
	if state.tick != _tick_seen:
		_tick_seen = state.tick
		_since_tick = 0.0
	else:
		_since_tick = minf(_since_tick + delta, Wl.SIM_DT)
	clock_s = state.tick * Wl.SIM_DT + _since_tick


func _update_wheels(delta: float) -> void:
	var r_m := path.wheel_radius_m if path != null else 7.0
	for slot in 4:
		var r := state.rider_at(slot)
		var p := r.p_eff_w if r != null else 0.0
		var stag := r != null and r.rescue
		stumbling[slot] = 1 if stag else 0
		var dip := SiegeViewMath.stumble_dip(clock_s + slot * 0.23) if stag else 0.0
		# a stumble checks the wheel for a moment
		var check := 1.0 - 0.7 * dip
		var turn := SiegeViewMath.wheel_deg_per_s(p, r_m) * check
		wheel_deg[slot] = fposmod(wheel_deg[slot] + turn * delta, 360.0)
		machines.stumble[slot] = stag
		machines.stumble_dip[slot] = dip
		walker_count[slot] = SiegeViewMath.walkers_for(p, walker_count[slot]) if r != null else 0
		cranks[slot].advance(r.cadence_rpm if r != null else 0.0, delta)
		walk_phase[slot] = cranks[slot].revs
		machines.set_wheel(slot, wheel_deg[slot], r != null, walker_count[slot], walk_phase[slot])


func _update_machines(delta: float) -> void:
	for slot in 4:
		machines.set_route(slot, SiegeViewMath.lit_station(state, state.rider_at(slot)))
	for id in [SiegeIds.STATION_BALLISTA, SiegeIds.STATION_ONAGER, SiegeIds.STATION_ARROWS]:
		var st := state.station(id)
		machines.set_station(id, st.yaw_deg, st.arm)
	var arrows := state.station(SiegeIds.STATION_ARROWS)
	var racks := SiegeStations.racks(state, arrows) if state.content != null else 3
	machines.racks = SiegeViewMath.rack_mask(arrows.rack, arrows.arm, racks)
	mine_phase = fposmod(mine_phase + state.station(SiegeIds.STATION_MINE).m * MINE_HZ * delta, 1.0)
	machines.mine_phase = mine_phase
	var tar_m := state.station(SiegeIds.STATION_TAR).m
	if state.tar.cauldron_l > 0.5:
		pump_phase = fposmod(pump_phase + tar_m * PUMP_HZ * delta, 1.0)
	machines.pump_phase = pump_phase
	machines.gate_stage = SiegeViewMath.gate_stage(state.gate_hp, state.gate_max, state.breach_s)
	machines.curtain_stage = SiegeViewMath.curtain_stage(state.tar)
	machines.coat_stage = SiegeViewMath.coat_stage(state.tar)
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		var pd := state.pad(n)
		machines.set_pad(n, pd.type, pd.yaw_deg)
	machines.rebuild()


func _update_crowd(delta: float) -> void:
	var types := PackedInt32Array()
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var walk := PackedFloat32Array()
	var hp := PackedFloat32Array()
	var sts := PackedInt32Array()
	var alpha := PackedFloat32Array()
	var client := _is_client() and game.history != null
	for e in state.enemies:
		# retreating bodies keep walking back until the rules drop them
		var shown := e.alive() or (e.st == SiegeIds.EN_RETREAT and e.hp > 0.0)
		if not shown or types.size() >= SiegeV2Crowd.MAX_ENEMIES:
			continue
		var prog := game.history.prog_of(e.id, e.prog_m) if client else e.prog_m
		var p := game.history.pos_of(e.id, e.pos) if client else e.pos
		types.append(e.type)
		pos.append(p)
		yaw.append(SiegeViewMath.enemy_yaw(path, prog, e.st))
		var stride := 3.0 if e.type == SiegeIds.ENEMY_CHARIOT else SiegeViewMath.STRIDE_M
		walk.append(prog / stride if e.st != SiegeIds.EN_BATTER else 0.0)
		hp.append(e.hp / maxf(e.max_hp, 1.0))
		sts.append(e.st)
		alpha.append(clampf(prog / ARRIVE_M, 0.0, 1.0))
	_add_boarders(types, pos, yaw, walk, hp, sts)
	_add_march(delta, types, pos, yaw, walk, hp, sts)
	shots.bodies = pos
	crowd.set_enemies(types, pos, yaw, walk, hp, sts, alpha)


## Spearmen on the wall walk beside a docked tower while it lands its boarders.
func _add_boarders(
	types: PackedInt32Array,
	pos: PackedVector3Array,
	yaw: PackedFloat32Array,
	walk: PackedFloat32Array,
	hp: PackedFloat32Array,
	sts: PackedInt32Array
) -> void:
	var tower := state.docked_tower()
	if tower == null or not state.tar.boarded:
		return
	var tp := tower.pos
	for k in BOARDERS:
		if types.size() >= SiegeV2Crowd.MAX_ENEMIES:
			return
		var x := clampf(tp.x + (k - BOARDERS * 0.5) * 1.1, 4.0, 80.0)
		types.append(SiegeIds.ENEMY_SPEAR)
		pos.append(Vector3(x, WALL_WALK.y - (k % 2) * 0.7, WALL_WALK.z))
		yaw.append(-90.0 if k % 2 == 0 else 180.0)
		walk.append(clock_s * 1.5 + k * 0.3)
		hp.append(1.0)
		sts.append(SiegeIds.EN_WALK)


## The victory march in the cool-down: the fort's workers and haulers walk out of the gate,
## over the bridge and down the road.
func _add_march(
	delta: float,
	types: PackedInt32Array,
	pos: PackedVector3Array,
	yaw: PackedFloat32Array,
	walk: PackedFloat32Array,
	hp: PackedFloat32Array,
	sts: PackedInt32Array
) -> void:
	var marching := game != null and game.victory_march()
	if game == null:
		marching = state.in_cooldown() or state.done
	if not marching:
		march_s = -1.0
		return
	march_s = maxf(march_s, 0.0) + delta
	for k in MARCHERS:
		if types.size() >= SiegeV2Crowd.MAX_ENEMIES:
			return
		var prog := path.length_m - march_s * MARCH_MPS + k * MARCH_GAP_M * 2.0
		if prog > path.length_m:
			continue
		var lat := (k % 2 - 0.5) * 1.6
		types.append(SiegeV2Crowd.TYPE_WORKER if k % 3 else SiegeV2Crowd.TYPE_HAULER)
		pos.append(path.point_at(maxf(prog, 0.0), lat))
		yaw.append(SiegeViewMath.enemy_yaw(path, prog, SiegeIds.EN_RETREAT))
		walk.append(prog / SiegeViewMath.STRIDE_M)
		hp.append(1.0)
		sts.append(SiegeIds.EN_WALK)


func _on_cue(kind: String, data: Dictionary) -> void:
	if not _built:
		return
	if kind == SiegeIds.EV_SHOT:
		shots.add_event(data)
	if audio != null:
		audio.on_cue(kind, data)

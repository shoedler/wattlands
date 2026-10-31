class_name WorkoutAudio
extends Node
## Workout's sound: game state to bank parameters, events to cue names, and nothing else. The recipes,
## patterns and levels are data (assets/workout/audio/audio.json), the players are GameAudioKit's.
##
## Three clocks, the ride view's own. On cadence, from game.cranks, so sound and legs read one number:
## the chain, the pedals, the breath, the crowd's hands. On speed, from shown_distance: the freewheel,
## tyres and wind. On the view's env_t: the air, which is the view's gust and a slower swell of its own.
## It never integrates cadence, reads no wall clock and never consumes ctx.rng.
##
## FTMS reports cadence about once a second, not crank angle: the sound locks to the crank on screen
## exactly and to the rider's feet in rate only.

const BANK_PATH := "res://assets/workout/audio/audio.json"
const BED := "dawn_road"
## Every event WorkoutRules has makes a sound: none is silent.
const SILENT_EVENTS: Array[String] = []
## A freewheel's ratchet: one tick per this many metres of road.
const TICK_M := 0.35
## Coasting: the legs have stopped and the wheel still runs.
const COAST_RPM := 10.0
const COAST_MPS := 2.0
## shown_distance moves in sim steps (20 Hz on a host), which would put the ticks on that grid. The
## wheel runs on its own distance, speed times frame time, and closes on the shown one this softly.
const WHEEL_TAU_S := 0.4
## Further apart than this the road has jumped (a new session, a resync): follow at once.
const WHEEL_RESYNC_M := 4.0
## A rider breathes once per this many revolutions, the view's breath clouds' rate.
const BREATH_REVS := 2.0
## The shifter clicks at once; the chain crosses a quarter of a revolution later, on the crank, and
## only if it still runs by then: a chain that is not moving cannot cross.
const SHIFT_REVS := 0.25
const SHIFT_MIN_RPM := 10.0
const NO_SHIFT := -1.0
## How the cheer takes a rider's own sprint: above the rule's line, or short of it.
const HIT_DB := 2.0
const MISS_DB := -3.0

var kit := GameAudioKit.new()
var view: WorkoutRideView = null
var played: Array[String]:
	get:
		return kit.played

var _gear: int = -1
## The crank revolution the chain crosses at, NO_SHIFT when no shift is under way.
var _shift_at: float = NO_SHIFT
var _wheel_d: float = 0.0
var _wheel_set: bool = false
var _paused: bool = false
## The landscape's seeded surprises, the same list the view draws (WorkoutSpots), per session length.
var _spots: Array[Dictionary] = []
var _spots_for_s: float = -1.0


## Called once, by the view that owns this. Sets up the kit and listens for the game's events.
func prepare(p_view: WorkoutRideView) -> WorkoutAudio:
	view = p_view
	name = "WorkoutAudio"
	p_view.add_child(self)
	add_child(kit)
	var game := p_view.game
	var seed_value := game.ctx.seed if game != null and game.ctx != null else 0
	kit.setup(BANK_PATH, SeededRng.derive(seed_value, "workout:audio"))
	kit.set_bed(BED)
	if game != null:
		game.cue.connect(_on_cue)
	var tree := Engine.get_main_loop() as SceneTree
	var bus: Node = tree.root.get_node_or_null("EventBus") if tree != null else null
	if bus != null:
		bus.connect("paused_changed", _on_paused_changed)
	return self


## One frame, after the view has moved its clocks.
func update(dt: float) -> void:
	var game := view.game
	if game != null and game.state != null:
		var near := crowd_near()
		_drive_bikes(game)
		_drive_local(game, near, dt)
		_drive_road(game, near)
	kit.commit(dt)


## The breeze's strength on the environment clock, 0..1: what moves the view's grass and pump rotor.
static func gust_at(env_t: float) -> float:
	return 0.5 + 0.5 * sin(env_t / 11.0) * sin(env_t / 3.7)


## The air you hear, 0..1: half the view's gust, half a swell of minutes. The gust alone is one wave
## repeated every 35 s (3.7 and 11 are close to 1:3), which half an hour of a steady block would give away.
static func air_at(env_t: float) -> float:
	var swell := 0.5 + 0.3 * sin(env_t / 23.0) + 0.2 * sin(env_t / 61.0)
	return 0.5 * gust_at(env_t) + 0.5 * swell


## The road surface under the tyres, 0..1, by the metre: patches of rougher tarmac that come and go
## over a few hundred metres, on three lengths that do not line up. The same stretch of road sounds the
## same each time you ride it.
static func road_at(distance_m: float) -> float:
	var long_wave := 0.15 * sin(distance_m / 157.0 + 1.0) + 0.1 * sin(distance_m / 367.0 + 2.0)
	return 0.5 + 0.25 * sin(distance_m / 59.0) + long_wave


## How near the viewer the roadside crowd is, 0..1: 1 among them, 0 from the screen's edge on, so
## you hear it as far as you can see it. It is there only when the view draws one, and the view draws
## none in the warm-up (BRIEF 4.6.8).
func crowd_near() -> float:
	var game := view.game
	var layer := view.crowd_layer
	if game == null or game.state == null or layer == null:
		return 0.0
	var world_x := view.shown_distance(game.view_peer()) * WorkoutRideView.VISUAL_PX_PER_M
	var x := world_x + WorkoutRideView.RIDER_X
	var ahead := maxf(view.canvas_size().x - WorkoutRideView.RIDER_X, 1.0)
	var near := 0.0
	for w: Dictionary in layer.windows:
		var w0 := float(w["w0"])
		var w1 := float(w["w1"])
		var here := 1.0
		if x < w0:
			here = 1.0 - (w0 - x) / ahead
		elif x > w1:
			here = 1.0 - (x - w1) / WorkoutRideView.RIDER_X
		near = maxf(near, here)
	return clampf(near, 0.0, 1.0)


func _drive_bikes(game: WorkoutGame) -> void:
	var me := game.ctx.local_peer if game.ctx != null else 0
	for peer: int in game.state.order:
		kit.drive(
			"bike%d" % peer,
			"bike" if peer == me else "peer_bike",
			game.cranks.revs(peer),
			game.cadence_of(peer),
			{"power": _power_of(game, peer)},
			peer == me
		)


## What only the local rider hears from its own bike: the freewheel, its breath, the crowd beating
## time on its cadence, and its gears. No rider (a spectator): none of these, and no lead.
func _drive_local(game: WorkoutGame, near: float, dt: float) -> void:
	var me := game.ctx.local_peer if game.ctx != null else 0
	if not game.state.riders.has(me):
		return
	var revs := game.cranks.revs(me)
	var rpm := game.cadence_of(me)
	var speed := _speed_of(game, me)
	var coast := 1.0 if rpm < COAST_RPM and speed > COAST_MPS else 0.0
	kit.drive(
		"wheel",
		"wheel",
		_wheel_distance(me, speed, dt) / TICK_M,
		speed / TICK_M * 60.0,
		{"coast": coast, "speed": speed},
		true
	)
	var power := _power_of(game, me)
	kit.drive("breath", "breath", revs / BREATH_REVS, rpm / BREATH_REVS, {"power": power}, true)
	kit.drive("crowd", "crowd", revs, rpm, {"crowd": near}, true)
	_shift_gears(game, revs, rpm)


## The wheel's own distance: smooth between sim steps, never backwards, and it stays with the state.
func _wheel_distance(peer: int, speed: float, dt: float) -> float:
	var shown := view.shown_distance(peer)
	if not _wheel_set or absf(shown - _wheel_d) > WHEEL_RESYNC_M:
		_wheel_set = true
		_wheel_d = shown
		return _wheel_d
	var next := _wheel_d + speed * dt
	next += (shown - next) * (1.0 - exp(-dt / WHEEL_TAU_S))
	_wheel_d = maxf(_wheel_d, next)
	return _wheel_d


func _shift_gears(game: WorkoutGame, revs: float, rpm: float) -> void:
	if _shift_at != NO_SHIFT:
		if _paused or rpm < SHIFT_MIN_RPM:
			_shift_at = NO_SHIFT
		elif revs >= _shift_at:
			_shift_at = NO_SHIFT
			kit.cue("gear_shift")
	if game.local_tm == null:
		return
	var gear := game.local_tm.gear
	if _gear >= 0 and gear != _gear:
		kit.cue("gear_up" if gear > _gear else "gear_down")
		if rpm >= SHIFT_MIN_RPM and not _paused:
			_shift_at = revs + SHIFT_REVS
	_gear = gear


func _drive_road(game: WorkoutGame, near: float) -> void:
	var peer := game.view_peer()
	var speed := _speed_of(game, peer)
	var air := air_at(view.env_t)
	kit.set_loop("tyre_hum", {"speed": speed, "road": road_at(view.shown_distance(peer))})
	kit.set_loop("wind_rush", {"speed": speed, "gust": air})
	kit.set_loop("crowd_loop", {"crowd": near})
	(
		kit
		. bed_params(
			{
				"speed": speed,
				"day": WorkoutTod.progress(game.state),
				"gust": air,
				"tractor": 1.0 if _tractor_crossing(game) else 0.0,
			}
		)
	)


## The rider's watts over its FTP. The local rider's own telemetry on a client, never a snapshot up
## to a second old.
func _power_of(game: WorkoutGame, peer: int) -> float:
	var r := game.state.rider(peer)
	if r == null:
		return 0.0
	var me := game.ctx.local_peer if game.ctx != null else 0
	var watts := game.local_tm.power_w if peer == me and game.local_tm != null else r.power_w
	return watts / maxf(r.ftp, 1.0)


## Paused or over, the state keeps its last speed but nothing rolls.
func _speed_of(game: WorkoutGame, peer: int) -> float:
	if game.sim_quiet_s > WorkoutGame.SIM_ALIVE_S:
		return 0.0
	var r := game.state.rider(peer)
	return r.speed_mps() if r != null else 0.0


## A tractor works the field on screen: the far engine is heard only then.
func _tractor_crossing(game: WorkoutGame) -> bool:
	if game.state.total_s() != _spots_for_s:
		_spots_for_s = game.state.total_s()
		_spots = WorkoutSpots.build(game.ctx.seed if game.ctx != null else 0, _spots_for_s)
	for s: Dictionary in WorkoutSpots.active(_spots, game.state.plan_t):
		if str(s["kind"]) == "tractor":
			return true
	return false


func _on_paused_changed(paused: bool, _reason: String) -> void:
	_paused = paused


func _on_cue(kind: String, data: Dictionary) -> void:
	match kind:
		WorkoutRules.EV_INTERVAL_START:
			kit.cue("interval_start")
		WorkoutRules.EV_INTERVAL_END:
			kit.cue("interval_end")
		WorkoutRules.EV_SPRINT:
			_cheer(data)


## The finish of a scored sprint. A sprint in the warm-up gets no crowd and no cheer (BRIEF 4.6.8).
func _cheer(data: Dictionary) -> void:
	var game := view.game
	if game == null or not WorkoutCrowd.cheers_for(game.state, int(data.get("i", -1))):
		return
	var hit_db := MISS_DB
	var me := game.ctx.local_peer if game.ctx != null else 0
	for row: Array in data.get("r", []):
		if int(row[0]) == me and int(row[3]) == 1:
			hit_db = HIT_DB
	kit.cue(WorkoutRules.EV_SPRINT, {"hit_db": hit_db})

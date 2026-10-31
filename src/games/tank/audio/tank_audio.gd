class_name TankAudio
extends Node
## Synthesized sound (brief 3 Audio; Sfx.synth only, no downloads): the diesel's rumble by cadence,
## the dynamo's whine by armature speed, a steam chuff per pedal stroke and a hiss when a shell
## latches, the arc generator's hum and a crackle each time its arc climbs the ladder (two a
## revolution), the bow guns' rattle, the cannon's boom, the shell's whistle, spent brass,
## explosions, track clank, the lever's clunk and the hoist's ratchet, over a quiet night ambience
## (wind in the pines and crickets; docs/games/tank.md 3.7). The local rider's own station is
## loudest. Silent and error-free headless (no players are created; what would play is still
## recorded in `played`). v2 has no Ram, so no Ram sound.
##
## TankView creates it as a child, connects TankGame.cue to on_cue and calls update() every frame
## with the state, the frame time, the local peer and the riders' feed (peer -> Vector2(raw_w,
## cadence)). It only reads the state and the events.

## Every one-shot registered with the Sfx autoload.
const SOUND_NAMES: Array[String] = [
	"tank_boom_low",
	"tank_boom_crack",
	"tank_boom_small",
	"tank_boom_big",
	"tank_whistle",
	"tank_brass",
	"tank_clank",
	"tank_clunk",
	"tank_ratchet",
	"tank_chuff",
	"tank_hiss",
	"tank_hit",
	"tank_breakdown",
	"tank_arc_crackle",
	"tank_bow_rattle",
	"tank_cricket",
	"tank_rustle",
]
## name -> [synth kind, Hz, duration s, attack s, release s]
const DEFS := {
	"tank_boom_low": ["saw", 52.0, 0.6, 0.004, 0.5],
	"tank_boom_crack": ["noise", 0.0, 0.22, 0.001, 0.18],
	"tank_boom_small": ["square", 120.0, 0.14, 0.002, 0.1],
	"tank_boom_big": ["noise", 0.0, 0.75, 0.004, 0.65],
	"tank_whistle": ["sine", 1700.0, 0.5, 0.15, 0.3],
	"tank_brass": ["sine", 3300.0, 0.09, 0.001, 0.07],
	"tank_clank": ["square", 150.0, 0.05, 0.001, 0.04],
	"tank_clunk": ["square", 85.0, 0.11, 0.002, 0.09],
	"tank_ratchet": ["square", 640.0, 0.03, 0.001, 0.02],
	"tank_chuff": ["noise", 0.0, 0.13, 0.01, 0.1],
	"tank_hiss": ["noise", 0.0, 0.7, 0.05, 0.5],
	"tank_hit": ["triangle", 540.0, 0.2, 0.001, 0.18],
	"tank_breakdown": ["saw", 90.0, 0.9, 0.01, 0.8],
	"tank_arc_crackle": ["noise", 0.0, 0.07, 0.001, 0.06],
	"tank_bow_rattle": ["square", 210.0, 0.035, 0.001, 0.03],
	"tank_cricket": ["sine", 4300.0, 0.05, 0.004, 0.04],
	"tank_rustle": ["noise", 0.0, 0.28, 0.02, 0.24],
}
## The arc generator's engine id (TankIds.ENGINE_ARC).
const ENGINE_ARC := TankIds.ENGINE_ARC
## Loops: engine -> [synth kind, Hz]. Their pitch follows cadence (the dynamo's armature runs faster;
## the arc generator hums low).
const LOOPS := {
	TankIds.ENGINE_DIESEL: ["saw", 46.0],
	TankIds.ENGINE_DYNAMO: ["sine", 380.0],
	ENGINE_ARC: ["triangle", 100.0],
}
## The night ambience: a quiet wind loop and crickets chirping in short trains.
const AMBIENCE := ["noise", 0.0]
const AMBIENCE_DB := -34.0
const CRICKET_DB := -27.0
const CRICKET_GAP_S := Vector2(0.7, 2.6)
## Pitch scale of a loop at cadence 0 .. 120 rpm.
const RUMBLE_PITCH := Vector2(0.7, 1.7)
const WHINE_PITCH := Vector2(0.6, 2.0)
const HUM_PITCH := Vector2(0.8, 1.3)
## Loop volumes (dB): the local rider's own station, and the others.
const OWN_DB := {
	TankIds.ENGINE_DIESEL: -11.0,
	TankIds.ENGINE_DYNAMO: -17.0,
	ENGINE_ARC: -15.0,
}
const OTHER_DB := {
	TankIds.ENGINE_DIESEL: -22.0,
	TankIds.ENGINE_DYNAMO: -28.0,
	ENGINE_ARC: -25.0,
}
const OWN_CRACKLE_DB := -14.0
const OTHER_CRACKLE_DB := -22.0
## A loop stops below this cadence.
const LOOP_MIN_RPM := 8.0
const OWN_CHUFF_DB := -9.0
const OTHER_CHUFF_DB := -18.0
const MAX_PLAYS_PER_FRAME := 8
## How long before a far shell lands its whistle starts (s).
const WHISTLE_LEAD_S := 0.5
const PLAYED_MAX := 256
const DELAYED_MAX := 32
const CLANK_MIN_S := 0.16
const CLANK_MAX_S := 0.5
const RATCHET_EVERY_S := 0.16

var game: TankGame = null
## Every sound asked for, newest last, and its volume in dB (tests read and clear them).
var played: Array[String] = []
var played_db: Array[float] = []
var silent: bool = true
## engine -> the loop's last volume (dB), pitch scale and whether it runs (tests read them).
var loop_db: Dictionary = {}
var loop_pitch: Dictionary = {}
var loop_on: Dictionary = {}
var loop_players: Dictionary = {}
var local_peer: int = 0
var own_engine: String = ""
## Whether the night ambience runs (it does once update() ran; tests read it).
var ambience_on: bool = false

var _rng := RandomNumberGenerator.new()
var _cricket_t: float = 1.0
var _ambience: AudioStreamPlayer = null

var _sfx: WlSfx = null
var _plays_this_frame: int = 0
var _delayed: Array[Dictionary] = []
var _stroke: Dictionary = {}
var _clank_t: float = 0.0
var _ratchet_t: float = 0.0
var _pressure_was: float = 0.0


func _ready() -> void:
	_sfx = get_node_or_null("/root/Sfx") as WlSfx
	silent = DisplayServer.get_name() == "headless"
	_register()
	if not silent:
		for engine: String in LOOPS:
			var d: Array = LOOPS[engine]
			var p := AudioStreamPlayer.new()
			p.name = "Loop_" + engine
			p.volume_db = -40.0
			if _sfx != null:
				p.stream = _sfx.synth(str(d[0]), float(d[1]), 1.0, 0.0, 0.0, true)
			add_child(p)
			loop_players[engine] = p
		_ambience = AudioStreamPlayer.new()
		_ambience.name = "Ambience"
		_ambience.volume_db = AMBIENCE_DB
		if _sfx != null:
			_ambience.stream = _sfx.synth(str(AMBIENCE[0]), float(AMBIENCE[1]), 4.0, 0.0, 0.0, true)
		add_child(_ambience)
	if game != null and game.ctx != null:
		_rng.seed = game.ctx.seed + 7


func _register() -> void:
	if _sfx == null:
		return
	for key: String in DEFS:
		if _sfx.has_sound(key):
			continue
		var d: Array = DEFS[key]
		var stream := _sfx.synth(str(d[0]), float(d[1]), float(d[2]), float(d[3]), float(d[4]))
		if stream != null:
			_sfx.register(key, stream)


## Pitch of a loop for `value` inside `span` (x at 0, y at `full`).
static func pitch_for(value: float, full: float, span: Vector2) -> float:
	return lerpf(span.x, span.y, clampf(value / maxf(full, 1.0), 0.0, 1.0))


# --- Events ------------------------------------------------------------------------------------------------


## Every game event (TankGame.cue: the host where it sends it, clients in apply_event).
func on_cue(kind: String, data: Dictionary) -> void:
	match kind:
		TankEvents.SHOT:
			_shot(data)
		TankEvents.HIT:
			_hit(data)
		TankEvents.KILL:
			var boss := int(data.get("e", 0)) == TankIds.BOSS_CODE
			_play("tank_boom_big", 0.0 if boss else -3.0, 0.7 if boss else 1.0)
			if boss:
				_after(0.4, "tank_boom_big", -2.0, 0.8)
				_after(0.9, "tank_boom_big", -4.0, 0.6)
		TankEvents.BREAKDOWN:
			_play("tank_breakdown", -3.0)
		TankEvents.REPAIRED:
			_play("tank_clunk", -8.0, 1.4)
		TankEvents.SEAT:
			_play("tank_clunk", -4.0 if _is_own_slot(int(data.get("s", -1))) else -12.0)
		TankEvents.ROTATION:
			_play("tank_clunk", -8.0, 0.8)
		TankEvents.LATCH:
			_latch(data)
		TankEvents.BOSS_PHASE:
			_play("tank_boom_big", -4.0, 0.75)
		TankEvents.SPLASH:
			if int(data.get("f", 0)) == 1:
				_play("tank_boom_small", -20.0, 0.7)
			else:
				_play("tank_boom_crack", -14.0, 0.8)
		TankEvents.AMBUSH:
			_play("tank_rustle", -10.0)
			_after(0.08, "tank_clank", -14.0, 1.3)
		TankEvents.TANK_LOST:
			_play("tank_boom_big", -2.0, 0.7)
			_after(0.2, "tank_breakdown", -5.0)
		TankEvents.STAGE_RESTART:
			_play("tank_clunk", -6.0, 0.9)


func _latch(data: Dictionary) -> void:
	var own := _is_own_slot(int(data.get("s", -1)))
	var loader: TankStationState = null
	if game != null and game.state != null:
		loader = game.state.station(TankIds.ENGINE_STEAM)
	if loader != null and not loader.is_empty():
		_play("tank_hiss", -6.0 if own else -13.0)
	else:
		_play("tank_ratchet", -8.0 if own else -14.0)


func _shot(data: Dictionary) -> void:
	var sh := int(data.get("sh", 0))
	if int(data.get("s", -1)) >= 0:
		if sh == TankIds.SHELL_BOW:
			# The bow guns' burst: a short rattle of rounds.
			for i in 5:
				_after(0.06 * i, "tank_bow_rattle", -11.0, 1.0 + 0.04 * float(i % 2))
			return
		var gunner := _is_gunner_slot(int(data.get("s", -1)))
		var heavy := sh == TankIds.SHELL_HEAVY or sh == TankIds.SHELL_OVER
		var db := (4.0 if gunner else 0.0) + (3.0 if heavy else 0.0)
		_play("tank_boom_low", -4.0 + db, 0.8 if sh == TankIds.SHELL_OVER else 1.0)
		_play("tank_boom_crack", -8.0 + db)
		_after(0.35, "tank_brass", -14.0 + (4.0 if gunner else 0.0))
		return
	var flight := float(data.get("flight_s", 0.0))
	if sh == TankIds.SHELL_BOSS_MAIN:
		_play("tank_boom_low", -2.0, 0.7)
		_play("tank_boom_crack", -5.0)
		_after(_whistle_at(flight, 0.5), "tank_whistle", -10.0, 0.7)
		return
	_play("tank_boom_small", -13.0)
	_after(_whistle_at(flight, 0.25), "tank_whistle", -16.0)


## A far shell's whistle comes just before it lands; a near one's `near_s` after the shot.
static func _whistle_at(flight_s: float, near_s: float) -> float:
	return maxf(flight_s - WHISTLE_LEAD_S, 0.0) if flight_s > 0.0 else near_s


func _hit(data: Dictionary) -> void:
	var dmg := float(data.get("dmg", 0))
	if int(data.get("on", -1)) == TankEvents.ON_TANK:
		_play("tank_hit", -9.0 + minf(dmg, 24.0) * 0.25)
		_after(0.06, "tank_boom_crack", -12.0)
	else:
		_play("tank_hit", -14.0, 1.25)


func _is_own_slot(slot: int) -> bool:
	if game == null or game.state == null:
		return false
	var r := game.state.rider(local_peer)
	return r != null and r.slot == slot


func _is_gunner_slot(slot: int) -> bool:
	return own_engine == TankIds.ENGINE_DYNAMO and _is_own_slot(slot)


# --- Per frame ------------------------------------------------------------------------------------------------


## Retunes the loops and starts what the state asks for this frame.
func update(state: TankState, dt: float, p_local_peer: int, feed: Dictionary = {}) -> void:
	local_peer = p_local_peer
	_plays_this_frame = 0
	var me := state.rider(local_peer)
	own_engine = me.engine if me != null else ""
	_run_delayed(dt)
	for engine: String in LOOPS:
		_loop(state, engine, feed)
	_chuffs(state, dt, feed)
	_crackles(state, dt, feed)
	_night(dt)
	_clank(state, dt)
	_ratchets(state, dt)


func _station_cadence(state: TankState, engine: String, feed: Dictionary) -> float:
	var st := state.station(engine)
	if st == null or st.unpowered or state.all_afk:
		return 0.0
	# v3: an empty seat (slot -1) does nothing, so its machine is silent; a dropped rider's room
	# still runs on reserve.
	if st.slot < 0:
		return 0.0
	if st.reserve:
		return 45.0
	var r := state.rider_at(st.slot)
	if r == null:
		return 0.0
	var f: Vector2 = feed.get(r.peer, Vector2(r.raw_w, r.cadence_rpm))
	return f.y


func _loop(state: TankState, engine: String, feed: Dictionary) -> void:
	var present := state.station(engine) != null
	var cadence := _station_cadence(state, engine, feed) if present else 0.0
	var on := present and cadence >= LOOP_MIN_RPM
	var own := engine == own_engine
	var span := RUMBLE_PITCH
	if engine == TankIds.ENGINE_DYNAMO:
		span = WHINE_PITCH
	elif engine == ENGINE_ARC:
		span = HUM_PITCH
	loop_on[engine] = on
	loop_db[engine] = float(OWN_DB[engine] if own else OTHER_DB[engine])
	loop_pitch[engine] = pitch_for(cadence, 120.0, span)
	var p := loop_players.get(engine) as AudioStreamPlayer
	if p == null:
		return
	p.volume_db = loop_db[engine]
	p.pitch_scale = loop_pitch[engine]
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()


## The steam engine chuffs once per pedal stroke.
func _chuffs(state: TankState, dt: float, feed: Dictionary) -> void:
	var st := state.station(TankIds.ENGINE_STEAM) as TankSteamState
	if st == null:
		return
	var cadence := _station_cadence(state, TankIds.ENGINE_STEAM, feed)
	if cadence < LOOP_MIN_RPM:
		return
	var phase: float = float(_stroke.get(TankIds.ENGINE_STEAM, 0.0)) + cadence / 60.0 * dt
	if phase >= 1.0:
		phase = fmod(phase, 1.0)
		var own := own_engine == TankIds.ENGINE_STEAM
		var pitch := 0.9 + 0.4 * clampf(st.pressure_pct / 150.0, 0.0, 1.0)
		_play("tank_chuff", OWN_CHUFF_DB if own else OTHER_CHUFF_DB, pitch)
	_stroke[TankIds.ENGINE_STEAM] = phase


## The arc crackles each time it climbs the ladder (two climbs a revolution of the generator).
func _crackles(state: TankState, dt: float, feed: Dictionary) -> void:
	if state.station(ENGINE_ARC) == null:
		return
	var cadence := _station_cadence(state, ENGINE_ARC, feed)
	if cadence < LOOP_MIN_RPM:
		return
	var phase: float = float(_stroke.get(ENGINE_ARC, 0.0)) + cadence / 60.0 * 2.0 * dt
	if phase >= 1.0:
		phase = fmod(phase, 1.0)
		var own := own_engine == ENGINE_ARC
		_play(
			"tank_arc_crackle",
			OWN_CRACKLE_DB if own else OTHER_CRACKLE_DB,
			0.8 + 0.4 * _rng.randf()
		)
	_stroke[ENGINE_ARC] = phase


## The night: the wind loop runs quietly, crickets chirp in trains of two or three.
func _night(dt: float) -> void:
	ambience_on = true
	if _ambience != null and not _ambience.playing:
		_ambience.play()
	_cricket_t -= dt
	if _cricket_t <= 0.0:
		_cricket_t = _rng.randf_range(CRICKET_GAP_S.x, CRICKET_GAP_S.y)
		var pitch := _rng.randf_range(0.92, 1.08)
		for i in 2 + _rng.randi_range(0, 1):
			_after(0.09 * i, "tank_cricket", CRICKET_DB, pitch)


## Track clank: faster and louder with the hull's speed.
func _clank(state: TankState, dt: float) -> void:
	var v := state.hull.speed_mps
	if v < 1.0:
		_clank_t = 0.0
		return
	_clank_t -= dt
	if _clank_t <= 0.0:
		_clank_t = clampf(0.5 - v * 0.035, CLANK_MIN_S, CLANK_MAX_S)
		_play("tank_clank", -17.0 + minf(v, 10.0) * 0.5)


## The hoist ratchets while a shell is being lifted (the gunner's hoist, the steam engine's
## cradle).
func _ratchets(state: TankState, dt: float) -> void:
	var lifting := false
	var own := false
	var dy := state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
	if dy != null and dy.hoist_s > 0.0:
		lifting = true
		own = own_engine == TankIds.ENGINE_DYNAMO
	var sm := state.station(TankIds.ENGINE_STEAM) as TankSteamState
	if sm != null:
		if sm.pressure_pct > _pressure_was + 0.01 and not sm.loaded:
			lifting = true
			own = own_engine == TankIds.ENGINE_STEAM
		_pressure_was = sm.pressure_pct
	if not lifting:
		_ratchet_t = 0.0
		return
	_ratchet_t -= dt
	if _ratchet_t <= 0.0:
		_ratchet_t = RATCHET_EVERY_S
		_play("tank_ratchet", -9.0 if own else -18.0)


# --- Playing --------------------------------------------------------------------------------------------------


func _after(delay: float, sound: String, db: float, pitch: float = 1.0) -> void:
	if _delayed.size() >= DELAYED_MAX:
		_delayed.pop_front()
	_delayed.append({"t": delay, "sound": sound, "db": db, "pitch": pitch})


func _run_delayed(dt: float) -> void:
	var i := 0
	while i < _delayed.size():
		_delayed[i]["t"] = float(_delayed[i]["t"]) - dt
		if float(_delayed[i]["t"]) <= 0.0:
			var d: Dictionary = _delayed[i]
			_delayed.remove_at(i)
			_play(str(d["sound"]), float(d["db"]), float(d["pitch"]))
		else:
			i += 1


func _play(sound: String, db: float = -6.0, pitch: float = 1.0) -> void:
	played.append(sound)
	played_db.append(db)
	if played.size() > PLAYED_MAX:
		played = played.slice(played.size() - PLAYED_MAX)
		played_db = played_db.slice(played_db.size() - PLAYED_MAX)
	if _plays_this_frame >= MAX_PLAYS_PER_FRAME:
		return
	_plays_this_frame += 1
	if _sfx != null and not silent:
		_sfx.play(sound, db, pitch)

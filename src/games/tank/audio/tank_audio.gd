class_name TankAudio
extends Node
## Synthesized sound (brief 3 Audio; Sfx.synth only, no downloads): the diesel's rumble by cadence,
## the dynamo's whine by armature speed, a steam chuff per pedal stroke and a hiss when a shell
## latches, the cannon's boom, the shell's whistle, spent brass, explosions, track clank, the lever's
## clunk and the hoist's ratchet. The local rider's own station is loudest. Silent and error-free
## headless (no players are created; what would play is still recorded in `played`).
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
	"tank_ram",
	"tank_breakdown",
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
	"tank_ram": ["saw", 70.0, 0.4, 0.003, 0.3],
	"tank_breakdown": ["saw", 90.0, 0.9, 0.01, 0.8],
}
## Loops: engine -> [synth kind, Hz]. Their pitch follows cadence (the dynamo's armature runs faster).
const LOOPS := {
	TankIds.ENGINE_DIESEL: ["saw", 46.0],
	TankIds.ENGINE_BULWARK: ["saw", 46.0],
	TankIds.ENGINE_DYNAMO: ["sine", 380.0],
}
## Pitch scale of a loop at cadence 0 .. 120 rpm.
const RUMBLE_PITCH := Vector2(0.7, 1.7)
const WHINE_PITCH := Vector2(0.6, 2.0)
## Loop volumes (dB): the local rider's own station, and the others.
const OWN_DB := {
	TankIds.ENGINE_DIESEL: -11.0, TankIds.ENGINE_BULWARK: -11.0, TankIds.ENGINE_DYNAMO: -17.0
}
const OTHER_DB := {
	TankIds.ENGINE_DIESEL: -22.0, TankIds.ENGINE_BULWARK: -22.0, TankIds.ENGINE_DYNAMO: -28.0
}
## A loop stops below this cadence.
const LOOP_MIN_RPM := 8.0
const OWN_CHUFF_DB := -9.0
const OTHER_CHUFF_DB := -18.0
const MAX_PLAYS_PER_FRAME := 8
const PLAYED_MAX := 256
const DELAYED_MAX := 32
const CLANK_MIN_S := 0.16
const CLANK_MAX_S := 0.5
const RATCHET_EVERY_S := 0.16

var game: TankGame = null
## Every sound asked for, newest last (tests read and clear it).
var played: Array[String] = []
var silent: bool = true
## engine -> the loop's last volume (dB), pitch scale and whether it runs (tests read them).
var loop_db: Dictionary = {}
var loop_pitch: Dictionary = {}
var loop_on: Dictionary = {}
var loop_players: Dictionary = {}
var local_peer: int = 0
var own_engine: String = ""

var _sfx: WlSfx = null
var _plays_this_frame: int = 0
var _delayed: Array[Dictionary] = []
var _stroke: Dictionary = {}
var _clank_t: float = 0.0
var _ratchet_t: float = 0.0
var _hoist_j_was: float = 0.0
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
		TankEvents.RAM:
			if int(data.get("ok", 0)) == 1:
				_play("tank_ram", -2.0)
				_after(0.12, "tank_boom_big", -6.0)
			else:
				_play("tank_ram", -4.0, 0.7)
		TankEvents.BREAKDOWN:
			_play("tank_breakdown", -3.0)
		TankEvents.REPAIRED:
			_play("tank_clunk", -8.0, 1.4)
		TankEvents.LEVER:
			_play("tank_clunk", -4.0 if _is_own_slot(int(data.get("s", -1))) else -12.0)
		TankEvents.ROTATION:
			_play("tank_clunk", -8.0, 0.8)
		TankEvents.LATCH:
			_latch(data)
		TankEvents.DODGE:
			_play("whoosh", -8.0)
		TankEvents.BOSS_PHASE:
			_play("tank_boom_big", -4.0, 0.75)


func _latch(data: Dictionary) -> void:
	var own := _is_own_slot(int(data.get("s", -1)))
	var steam := (
		game != null and game.state != null and game.state.station(TankIds.ENGINE_STEAM) != null
	)
	if steam:
		_play("tank_hiss", -6.0 if own else -13.0)
	else:
		_play("tank_ratchet", -8.0 if own else -14.0)


func _shot(data: Dictionary) -> void:
	var sh := int(data.get("sh", 0))
	if int(data.get("s", -1)) >= 0:
		if sh == TankIds.SHELL_SECONDARY:
			_play("tank_boom_small", -10.0)
			return
		var gunner := _is_gunner_slot(int(data.get("s", -1)))
		var heavy := sh == TankIds.SHELL_HEAVY or sh == TankIds.SHELL_OVER
		var db := (4.0 if gunner else 0.0) + (3.0 if heavy else 0.0)
		_play("tank_boom_low", -4.0 + db, 0.8 if sh == TankIds.SHELL_OVER else 1.0)
		_play("tank_boom_crack", -8.0 + db)
		_after(0.35, "tank_brass", -14.0 + (4.0 if gunner else 0.0))
		return
	if sh == TankIds.SHELL_BOSS_MAIN:
		_play("tank_boom_low", -2.0, 0.7)
		_play("tank_boom_crack", -5.0)
		_after(0.5, "tank_whistle", -10.0, 0.7)
		return
	_play("tank_boom_small", -13.0)
	_after(0.25, "tank_whistle", -16.0)


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
	return own_engine in [TankIds.ENGINE_DYNAMO, TankIds.ENGINE_BULWARK] and _is_own_slot(slot)


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
	_clank(state, dt)
	_ratchets(state, dt)


func _station_cadence(state: TankState, engine: String, feed: Dictionary) -> float:
	var st := state.station(engine)
	if st == null or st.unpowered or state.all_afk:
		return 0.0
	if st.reserve or st.slot < 0:
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
	var span := WHINE_PITCH if engine == TankIds.ENGINE_DYNAMO else RUMBLE_PITCH
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


## The hoist ratchets while a shell is being lifted (the Bulwark's Hoist, the Rampart's hoist, the
## steam engine's cradle).
func _ratchets(state: TankState, dt: float) -> void:
	var lifting := false
	var own := false
	var gb := state.station(TankIds.ENGINE_BULWARK) as TankGearboxState
	if gb != null:
		lifting = (
			gb.lever == TankIds.LEVER_HOIST and gb.move_s <= 0.0 and gb.hoist_j > _hoist_j_was + 0.5
		)
		_hoist_j_was = gb.hoist_j
		own = own_engine == TankIds.ENGINE_BULWARK
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
	if played.size() > PLAYED_MAX:
		played = played.slice(played.size() - PLAYED_MAX)
	if _plays_this_frame >= MAX_PLAYS_PER_FRAME:
		return
	_plays_this_frame += 1
	if _sfx != null and not silent:
		_sfx.play(sound, db, pitch)

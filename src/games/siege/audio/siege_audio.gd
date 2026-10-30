class_name SiegeAudio
extends Node
## Castellum Rotae's sound (docs/games/siege.md 3 "Audio"), all synthesized with Sfx.synth (no
## files): the treadwheels' creak and the junction's clatter, both looping and pitched by watts;
## the bolt's thunk, the onager's release and its stone's impact, the arrow volley's hiss, the tar
## pouring, hooves, the ram, gate hits, horns and coins. A child of SiegeView: it reads the state
## the view reads and hears the module's cues, so a client hears what the host does. Headless
## runs create no players and play nothing (`played` still records, for the tests).

const SOUNDS := {
	"siege_bolt": ["square", 92.0, 0.16, 0.001, 0.12],
	"siege_scorpion": ["square", 520.0, 0.07, 0.001, 0.05],
	"siege_release": ["saw", 70.0, 0.5, 0.004, 0.4],
	"siege_impact": ["noise", 0.0, 0.42, 0.002, 0.36],
	"siege_volley": ["noise", 0.0, 0.7, 0.05, 0.5],
	"siege_hooves": ["noise", 0.0, 0.09, 0.001, 0.07],
	"siege_ram": ["saw", 55.0, 0.45, 0.005, 0.35],
	"siege_gate": ["noise", 0.0, 0.3, 0.002, 0.25],
	"siege_horn": ["saw", 196.0, 1.1, 0.08, 0.5],
}
const LOOP_CREAK := "siege_creak"
const LOOP_CLATTER := "siege_clatter"
const LOOP_TAR := "siege_tar"
## Loop pitch: creak 0.55..1.6 over 0..300 W mean P_eff, clatter 0.7..1.8 over 0..1500 W team.
const CREAK_PITCH := Vector2(0.55, 1.6)
const CLATTER_PITCH := Vector2(0.7, 1.8)
const HOOF_EVERY_S := 0.4
const RAM_EVERY_S := 1.2
const COIN_EVERY_S := 0.3
const MAX_SHOT_SOUNDS_PER_TICK := 3

## Every sound asked for since the last clear, newest last (tests read and clear it).
var played: Array[String] = []
var silent: bool = true
var creak: AudioStreamPlayer = null
var clatter: AudioStreamPlayer = null
var tar_pour: AudioStreamPlayer = null
var creak_pitch: float = 1.0
var clatter_pitch: float = 1.0
var local_peer: int = 0

var _sfx: WlSfx = null
var _gate_hp: float = -1.0
var _hoof_t: float = 0.0
var _ram_t: float = 0.0
var _coin_t: float = 0.0
var _gold_was: float = -1.0
var _shot_tick: int = -1
var _shot_sounds: int = 0
## Stone impacts to come: [seconds left].
var _impacts := PackedFloat32Array()


func _ready() -> void:
	_sfx = get_node_or_null("/root/Sfx") as WlSfx
	silent = DisplayServer.get_name() == "headless"
	_register()
	if not silent:
		creak = _loop_player(LOOP_CREAK, "saw", 62.0, -20.0)
		clatter = _loop_player(LOOP_CLATTER, "square", 31.0, -24.0)
		tar_pour = _loop_player(LOOP_TAR, "noise", 0.0, -26.0)


func _register() -> void:
	if _sfx == null:
		return
	for key: String in SOUNDS:
		if _sfx.has_sound(key):
			continue
		var d: Array = SOUNDS[key]
		var stream := _sfx.synth(str(d[0]), float(d[1]), float(d[2]), float(d[3]), float(d[4]))
		if stream != null:
			_sfx.register(key, stream)


func _loop_player(key: String, kind: String, hz: float, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = key
	p.volume_db = db
	if _sfx != null:
		p.stream = _sfx.synth(kind, hz, 1.0, 0.0, 0.0, true)
	add_child(p)
	return p


## A loop's pitch for `value` inside `span` (x at 0, y at `full`).
static func pitch_for(value: float, full: float, span: Vector2) -> float:
	return lerpf(span.x, span.y, clampf(value / maxf(full, 1.0), 0.0, 1.0))


## Reads the state once a frame: the loops' pitch, gate hits, the Breach, hooves, the ram, coins
## and the stone impacts that are due.
func update(state: SiegeState, dt: float, p_local_peer: int) -> void:
	local_peer = p_local_peer
	var mean_p := 0.0
	var n := 0
	for r in state.riders:
		if r.connected and not r.afk:
			mean_p += r.p_eff_w
			n += 1
	mean_p = mean_p / float(n) if n > 0 else 0.0
	creak_pitch = pitch_for(mean_p, 300.0, CREAK_PITCH)
	clatter_pitch = pitch_for(state.team_w, 1500.0, CLATTER_PITCH)
	_loop(creak, creak_pitch, n > 0 and mean_p > 5.0)
	_loop(clatter, clatter_pitch, state.team_w > 5.0 and state.in_wave())
	var pouring := state.station(SiegeIds.STATION_TAR).m > 0.0 and state.tar.cauldron_l > 0.5
	_loop(tar_pour, 1.0, pouring and state.in_wave())
	_gate(state)
	_enemies(state, dt)
	_coins(state, dt)
	_due_impacts(dt)


func _loop(p: AudioStreamPlayer, pitch: float, on: bool) -> void:
	if p == null:
		return
	p.pitch_scale = pitch
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()


func _play(sound: String, db: float = -6.0, pitch: float = 1.0) -> void:
	played.append(sound)
	if _sfx != null and not silent:
		_sfx.play(sound, db, pitch)


## The module's cues: shots (thunk, release, hiss; a stone's impact when it lands), horns at a
## wave's start, an engine's push and a rush, and the Breach.
func on_cue(kind: String, data: Dictionary) -> void:
	match kind:
		SiegeIds.EV_SHOT:
			var tk := int(data.get("tk", 0))
			if tk != _shot_tick:
				_shot_tick = tk
				_shot_sounds = 0
			_shot_sounds += 1
			if _shot_sounds > MAX_SHOT_SOUNDS_PER_TICK:
				return
			match int(data.get("kind", 0)):
				SiegeIds.SHOT_BOLT:
					_play("siege_bolt", -6.0)
				SiegeIds.SHOT_SCORPION:
					_play("siege_scorpion", -12.0)
				SiegeIds.SHOT_STONE:
					_play("siege_release", -6.0)
					_impacts.append(_flight_s(data))
				SiegeIds.SHOT_ARROW:
					_play("siege_volley", -14.0, 1.6)
		SiegeIds.EV_WAVE_START, SiegeIds.EV_PUSH:
			_play("siege_horn", -8.0)
		SiegeIds.EV_RUSH:
			if int(data.get("on", 0)) != 0:
				_play("siege_horn", -6.0, 1.25)
		SiegeIds.EV_BREACH:
			_play("boom", -2.0)
			_play("siege_gate", -4.0)


## How long a shot flies before it comes down to the road (about z 0).
static func _flight_s(data: Dictionary) -> float:
	var o := SiegeEvents.shot_origin(data)
	var v := SiegeEvents.shot_velocity(data)
	return SiegeBallistics.flight_time(o, v, 0.0016, 0.0)


func _due_impacts(dt: float) -> void:
	var left := PackedFloat32Array()
	for t in _impacts:
		if t - dt <= 0.0:
			_play("siege_impact", -8.0, 0.8)
		else:
			left.append(t - dt)
	_impacts = left


func _gate(state: SiegeState) -> void:
	if _gate_hp >= 0.0 and state.gate_hp < _gate_hp - 0.5:
		_play("siege_gate", -14.0 + minf(_gate_hp - state.gate_hp, 12.0))
	_gate_hp = state.gate_hp


func _enemies(state: SiegeState, dt: float) -> void:
	_hoof_t -= dt
	_ram_t -= dt
	var horses := 0
	var batter := false
	for e in state.enemies:
		if e.type == SiegeIds.ENEMY_CHARIOT and e.st == SiegeIds.EN_WALK:
			horses += 1
		elif e.type == SiegeIds.ENEMY_RAM and e.st == SiegeIds.EN_BATTER:
			batter = true
	if horses > 0 and _hoof_t <= 0.0:
		_hoof_t = HOOF_EVERY_S
		_play("siege_hooves", -20.0 + minf(float(horses), 10.0))
	if batter and _ram_t <= 0.0:
		_ram_t = RAM_EVERY_S
		_play("siege_ram", -6.0)


func _coins(state: SiegeState, dt: float) -> void:
	_coin_t -= dt
	var me := state.rider(local_peer)
	if me == null:
		return
	if _gold_was >= 0.0 and floorf(me.gold) > floorf(_gold_was) and _coin_t <= 0.0:
		_coin_t = COIN_EVERY_S
		_play("coin", -16.0)
	_gold_was = me.gold

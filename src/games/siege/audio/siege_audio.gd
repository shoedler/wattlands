class_name SiegeAudio
extends Node
## Generator Siege's sound (brief 3 "Audio"), all synthesized with Sfx.synth (no files, no
## downloads; credited in docs/credits.d/siege.md): a wheel creak and a generator hum, both
## looping and pitched by watts; tower shots, hooves, the ram, the gate, horns and coins. It
## reads the state like the view does (a child of SiegeView), so a client hears what the host
## does, from its snapshots: shots, the gate losing HP, a Breach, a ram at the gate, a wave
## starting. Headless runs create no players and play nothing (Sfx stays silent there too).

const SOUND_NAMES: Array[String] = [
	"siege_ballista",
	"siege_scorpion",
	"siege_caltrop",
	"siege_hooves",
	"siege_ram",
	"siege_gate",
	"siege_horn",
]
const LOOP_CREAK := "siege_creak"
const LOOP_HUM := "siege_hum"
## Loop pitch: creak 0.55 .. 1.6 over 0 .. 300 W mean P_eff, hum 0.7 .. 2.0 over 0 .. 2000 W.
const CREAK_PITCH := Vector2(0.55, 1.6)
const HUM_PITCH := Vector2(0.7, 2.0)
const MAX_SHOTS_PER_FRAME := 4
const HOOF_EVERY_S := 0.4
const RAM_EVERY_S := 1.2
const COIN_EVERY_S := 0.3

## Every sound the last update asked for, newest last (tests read and clear it).
var played: Array[String] = []
var silent: bool = true
var creak: AudioStreamPlayer = null
var hum: AudioStreamPlayer = null
var creak_pitch: float = 1.0
var hum_pitch: float = 1.0
var local_peer: int = 0

var _sfx: WlSfx = null
var _tick: int = -1
var _seen: Dictionary = {}
var _gate_hp: float = -1.0
var _breach_was: bool = false
var _phase_was: int = -2
var _hoof_t: float = 0.0
var _ram_t: float = 0.0
var _coin_t: float = 0.0
var _denarii_was: float = -1.0


func _ready() -> void:
	_sfx = get_node_or_null("/root/Sfx") as WlSfx
	silent = DisplayServer.get_name() == "headless"
	_register()
	if not silent:
		creak = _loop_player(LOOP_CREAK, "saw", 62.0, -18.0)
		hum = _loop_player(LOOP_HUM, "sine", 55.0, -16.0)


func _register() -> void:
	if _sfx == null:
		return
	var defs := {
		"siege_ballista": ["saw", 150.0, 0.2, 0.002, 0.16],
		"siege_scorpion": ["square", 520.0, 0.07, 0.001, 0.05],
		"siege_caltrop": ["triangle", 210.0, 0.26, 0.01, 0.2],
		"siege_hooves": ["noise", 0.0, 0.09, 0.001, 0.07],
		"siege_ram": ["saw", 55.0, 0.45, 0.005, 0.35],
		"siege_gate": ["noise", 0.0, 0.3, 0.002, 0.25],
		"siege_horn": ["saw", 196.0, 1.1, 0.08, 0.5],
	}
	for key: String in defs:
		if _sfx.has_sound(key):
			continue
		var d: Array = defs[key]
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


## Pitch of a loop for `value` inside `span` (x at 0, y at `full`).
static func pitch_for(value: float, full: float, span: Vector2) -> float:
	return lerpf(span.x, span.y, clampf(value / maxf(full, 1.0), 0.0, 1.0))


## Reads the state: starts what happened since the last call, retunes the loops.
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
	hum_pitch = pitch_for(state.team_w, 2000.0, HUM_PITCH)
	if creak != null:
		creak.pitch_scale = creak_pitch
		_run(creak, n > 0 and mean_p > 5.0)
	if hum != null:
		hum.pitch_scale = hum_pitch
		_run(hum, state.team_w > 5.0)
	_shots(state)
	_gate(state)
	_phase(state)
	_hooves_and_ram(state, dt)
	_coins(state, dt)


func _run(p: AudioStreamPlayer, on: bool) -> void:
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()


func _play(sound: String, db: float = -6.0, pitch: float = 1.0) -> void:
	played.append(sound)
	if _sfx != null and not silent:
		_sfx.play(sound, db, pitch)


func _shots(state: SiegeState) -> void:
	if state.tick == _tick:
		return
	_tick = state.tick
	var fired := 0
	for shot in state.shots:
		var tick_fired := state.tick - roundi(shot.age_s / Wl.SIM_DT)
		var key := shot.pad * 1000003 + tick_fired
		if _seen.has(key):
			continue
		_seen[key] = tick_fired
		if fired >= MAX_SHOTS_PER_FRAME:
			continue
		fired += 1
		match state.pad(shot.pad).type:
			SiegeIds.TOWER_BALLISTA:
				_play("siege_ballista", -7.0)
			SiegeIds.TOWER_SCORPION:
				_play("siege_scorpion", -12.0)
			SiegeIds.TOWER_CALTROP:
				_play("siege_caltrop", -9.0)
	if _seen.size() > 48:
		for k: int in _seen.keys():
			if int(_seen[k]) < state.tick - 6:
				_seen.erase(k)


func _gate(state: SiegeState) -> void:
	if _gate_hp >= 0.0 and state.gate_hp < _gate_hp - 0.5:
		var loss := _gate_hp - state.gate_hp
		_play("siege_gate", -14.0 + minf(loss, 12.0))
	_gate_hp = state.gate_hp
	var breached := state.breach_s > 0.0
	if breached and not _breach_was:
		_play("boom", -2.0)
		_play("siege_gate", -4.0)
	_breach_was = breached


func _phase(state: SiegeState) -> void:
	if state.phase_index != _phase_was:
		var first := _phase_was == -2
		_phase_was = state.phase_index
		if not first and state.in_wave():
			_play("siege_horn", -8.0)


func _hooves_and_ram(state: SiegeState, dt: float) -> void:
	_hoof_t -= dt
	_ram_t -= dt
	var horses := 0
	var batter := false
	for e in state.enemies:
		if e.type == SiegeIds.ENEMY_HORSEMEN and e.st == SiegeIds.EN_WALK:
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
	if _denarii_was >= 0.0 and floorf(me.denarii) > floorf(_denarii_was) and _coin_t <= 0.0:
		_coin_t = COIN_EVERY_S
		_play("coin", -16.0)
	_denarii_was = me.denarii

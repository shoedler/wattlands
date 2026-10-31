class_name SiegeAudio
extends Node
## Castellum Rotae's sound: a thin adapter around GameAudioKit. The recipes, the stroke patterns, the
## loops, the bed and the cues are data (assets/siege/audio/audio.json); this class only maps game
## state to parameters and events to cue names. A child of SiegeView: it reads the state the view
## reads and hears the module's cues, so a client hears what the host does.
##
## The wheels are 1:1 with cadence: each rider's treadwheel strokes come from the same CrankClock
## that sets their walkers' frames (SiegeView.cranks), so sound and picture cannot drift. The mine
## and the pump are locked to their own drawn phase instead. Headless runs play nothing and `played`
## still records, for the tests.

const BANK_PATH := "res://assets/siege/audio/audio.json"
const BED := "hill_wind"
const MACHINE_WHEEL := "treadwheel"
const MACHINE_MINE := "mine"
const MACHINE_PUMP := "pump"
const LOOP_JUNCTION := "junction_clatter"
const LOOP_BUBBLE := "tar_bubble"
const LOOP_POUR := "tar_pour"
const LOOP_TOWER := "tower_creak"
const CUE_GATE_HIT := "gate_hit"
const CUE_HOOVES := "hooves"
const CUE_RAM := "ram_thud"
const CUE_GOLD := "gold"
const CUE_TAR_HISS := "tar_hiss"
## Events with no sound of their own. Every other event type maps to a cue (cue_for).
const SILENT_EVENTS: Array[String] = []
const HOOF_EVERY_S := 0.4
const RAM_EVERY_S := 1.2
const COIN_EVERY_S := 0.3
## A ram's battering is one leak per whole HP: the alarm answers the first, not each.
const LEAK_ALARM_EVERY_S := 3.0
const MAX_SHOT_SOUNDS_PER_TICK := 3
## A stone's or a volley's flight, as far as the delayed landing is concerned.
const FLIGHT_MIN_S := 0.1
const FLIGHT_MAX_S := 6.0
const FLIGHT_DRAG := 0.0016
## Gate hits and hooves grow with the damage and the horses, up to these.
const GATE_DMG_MAX_DB := 12.0
const HOOVES_MAX_DB := 10.0
## The three arrows of a volley's whistle: their pitches spread by the shot's own spread seed.
const WHISTLE_SPREAD := 0.03
## The hill wind's gusts: two slow sines. View-only, never in the rules.
const GUST_RATES := Vector2(0.13, 0.31)

var kit := GameAudioKit.new()
var rng_seed: int = 0  ## set by the view before add_child
var local_peer: int = 0
var played: Array[String]:
	get:
		return kit.played
var silent: bool:
	get:
		return kit.silent

var _gate_hp: float = -1.0
var _hoof_t: float = 0.0
var _ram_t: float = 0.0
var _coin_t: float = 0.0
var _leak_t: float = 0.0
var _gold_was: float = -1.0
var _shot_tick: int = -1
var _shot_sounds: int = 0
var _kill_sounds: int = 0
var _curtain_stage: int = -1
var _coat_stage: int = -1
var _gust_t: float = 0.0
var _mine_was: float = 0.0
var _mine_revs: float = 0.0
var _pump_was: float = 0.0
var _pump_revs: float = 0.0
var _local_slot: int = -1


func _ready() -> void:
	add_child(kit)
	kit.setup(BANK_PATH, rng_seed)
	kit.set_bed(BED)
	_gust_t = float(rng_seed % 1000)


## The cue of an event, "" when this one stays silent (a rush's end, a refused purchase). The
## shot's kind and the Overdrive's state choose among several.
static func cue_for(kind: String, data: Dictionary) -> String:
	match kind:
		SiegeIds.EV_SHOT:
			return _shot_cue(int(data.get("kind", 0)))
		SiegeIds.EV_RUSH:
			return "rush" if int(data.get("on", 0)) != 0 else ""
		SiegeIds.EV_BUY:
			return "buy" if int(data.get("ok", 0)) != 0 else ""
		SiegeIds.EV_OVERDRIVE:
			return _overdrive_cue(int(data.get("st", SiegeIds.OD_EV_END)))
	return kind


static func _shot_cue(shot: int) -> String:
	match shot:
		SiegeIds.SHOT_BOLT:
			return "shot_bolt"
		SiegeIds.SHOT_STONE:
			return "shot_stone"
		SiegeIds.SHOT_ARROW:
			return "shot_arrow"
	return "shot_scorpion"


static func _overdrive_cue(st: int) -> String:
	match st:
		SiegeIds.OD_EV_START:
			return "overdrive_on"
		SiegeIds.OD_EV_REFUSED:
			return "overdrive_no"
	return "overdrive_off"


## One frame, after the view has moved its cranks and phases: every machine, the loops, the bed,
## what the state tells that no event does (gate hits, hooves, the ram, coins, the tar).
func update(state: SiegeState, dt: float, p_local_peer: int, view: SiegeView) -> void:
	local_peer = p_local_peer
	var me := state.rider(local_peer)
	_local_slot = me.slot if me != null else -1
	_leak_t = maxf(_leak_t - dt, 0.0)
	_kill_sounds = 0
	_wheels(state, view)
	_works(state, view)
	_loops(state)
	_bed(state, dt)
	_gate(state)
	_tar_stages(state)
	_enemies(state, dt)
	_coins(state, dt)
	kit.commit(dt)


## A rider's strokes read the crank their walkers are drawn with. No rider: no drive, so the kit
## closes that slot's layers.
func _wheels(state: SiegeState, view: SiegeView) -> void:
	for slot in view.cranks.size():
		var r := state.rider_at(slot)
		if r == null:
			continue
		var params := {"p_eff": r.p_eff_w, "walkers": view.walker_count[slot]}
		var lead := r.peer == local_peer
		kit.drive(
			"wheel%d" % slot, MACHINE_WHEEL, view.cranks[slot].revs, r.cadence_rpm, params, lead
		)


## The mine and the pump: locked to the phase the view draws. The view wraps it to 0..1; the kit
## needs it unwrapped.
func _works(state: SiegeState, view: SiegeView) -> void:
	var m := state.station(SiegeIds.STATION_MINE).m
	var tar_m := state.station(SiegeIds.STATION_TAR).m
	_mine_revs += fposmod(view.mine_phase - _mine_was, 1.0)
	_mine_was = view.mine_phase
	_pump_revs += fposmod(view.pump_phase - _pump_was, 1.0)
	_pump_was = view.pump_phase
	var lead := _local_slot >= 0
	var rpm := m * SiegeView.MINE_HZ * 60.0
	kit.drive("mine", MACHINE_MINE, _mine_revs, rpm, {"m": m}, lead)
	rpm = tar_m * SiegeView.PUMP_HZ * 60.0 if state.tar.cauldron_l > 0.5 else 0.0
	kit.drive("pump", MACHINE_PUMP, _pump_revs, rpm, {"tar_m": tar_m}, lead)


func _loops(state: SiegeState) -> void:
	var in_wave := state.in_wave()
	if in_wave and state.team_w > 5.0:
		kit.set_loop(LOOP_JUNCTION, {"team_w": state.team_w})
	var tar_m := state.station(SiegeIds.STATION_TAR).m
	if state.tar.cauldron_l > 0.5:
		kit.set_loop(LOOP_BUBBLE, {"m": tar_m})
		if in_wave and tar_m > 0.0:
			kit.set_loop(LOOP_POUR, {})
	if _tower_walking(state):
		kit.set_loop(LOOP_TOWER, {})


static func _tower_walking(state: SiegeState) -> bool:
	for e in state.enemies:
		if e.type == SiegeIds.ENEMY_TOWER and e.st == SiegeIds.EN_WALK:
			return true
	return false


func _bed(state: SiegeState, dt: float) -> void:
	_gust_t += dt
	var gust := 0.5 + 0.3 * sin(_gust_t * GUST_RATES.x) + 0.2 * sin(_gust_t * GUST_RATES.y)
	var enemies := float(state.enemies.size())
	var warmup := 1.0 if state.role == SiegeIds.ROLE_WARMUP_WAVE else 0.0
	kit.bed_params({"gust": gust, "enemies": enemies, "warmup": warmup})


## The module's cues. A shot carries its flight to its landing; events of one rider are that
## rider's: full level for them, lower for the rest of the crew.
func on_cue(kind: String, data: Dictionary) -> void:
	var cue_name := cue_for(kind, data)
	if cue_name == "":
		return
	match kind:
		SiegeIds.EV_SHOT:
			_shot(cue_name, data)
		SiegeIds.EV_KILL:
			_kill_sounds += 1
			if _kill_sounds <= MAX_SHOT_SOUNDS_PER_TICK:
				kit.cue(cue_name)
		SiegeIds.EV_LEAK:
			if _leak_t <= 0.0:
				_leak_t = LEAK_ALARM_EVERY_S
				kit.cue(cue_name)
		SiegeIds.EV_ROUTE, SiegeIds.EV_BUY, SiegeIds.EV_OVERDRIVE:
			kit.cue(cue_name, {}, int(data.get("slot", -1)) == _local_slot)
		_:
			kit.cue(cue_name)


func _shot(cue_name: String, data: Dictionary) -> void:
	var tk := int(data.get("tk", 0))
	if tk != _shot_tick:
		_shot_tick = tk
		_shot_sounds = 0
	_shot_sounds += 1
	if _shot_sounds > MAX_SHOT_SOUNDS_PER_TICK:
		return
	var vars := {}
	var shot := int(data.get("kind", 0))
	if shot == SiegeIds.SHOT_STONE or shot == SiegeIds.SHOT_ARROW:
		vars["flight_s"] = flight_s(data)
	if shot == SiegeIds.SHOT_ARROW:
		var sd := int(data.get("sd", 0))
		for k in 3:
			vars["p%d" % k] = 1.0 + WHISTLE_SPREAD * float(posmod(sd >> (k * 3), 7) - 3)
	kit.cue(cue_name, vars)


## How long a shot flies before it comes down to the road (about z 0).
static func flight_s(data: Dictionary) -> float:
	var o := SiegeEvents.shot_origin(data)
	var v := SiegeEvents.shot_velocity(data)
	var t := SiegeBallistics.flight_time(o, v, FLIGHT_DRAG, 0.0)
	return clampf(t, FLIGHT_MIN_S, FLIGHT_MAX_S)


func _gate(state: SiegeState) -> void:
	if _gate_hp >= 0.0 and state.gate_hp < _gate_hp - 0.5:
		kit.cue(CUE_GATE_HIT, {"dmg_db": minf(_gate_hp - state.gate_hp, GATE_DMG_MAX_DB)})
	_gate_hp = state.gate_hp


## The curtain or the coat changed its drawn stage: hot tar on wet timber.
func _tar_stages(state: SiegeState) -> void:
	var curtain := SiegeViewMath.curtain_stage(state.tar)
	var coat := SiegeViewMath.coat_stage(state.tar)
	if _curtain_stage >= 0 and (curtain != _curtain_stage or coat != _coat_stage):
		kit.cue(CUE_TAR_HISS)
	_curtain_stage = curtain
	_coat_stage = coat


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
		kit.cue(CUE_HOOVES, {"count_db": minf(float(horses), HOOVES_MAX_DB)})
	if batter and _ram_t <= 0.0:
		_ram_t = RAM_EVERY_S
		kit.cue(CUE_RAM)


func _coins(state: SiegeState, dt: float) -> void:
	_coin_t -= dt
	var me := state.rider(local_peer)
	if me == null:
		return
	if _gold_was >= 0.0 and floorf(me.gold) > floorf(_gold_was) and _coin_t <= 0.0:
		_coin_t = COIN_EVERY_S
		kit.cue(CUE_GOLD)
	_gold_was = me.gold

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
const CUE_KILL_ENGINE := "kill_engine"
## Events with no sound of their own. Every other event type maps to a cue (cue_for).
const SILENT_EVENTS: Array[String] = []
const HOOF_EVERY_S := 0.4
## Hooves only for a chariot this near the gate: all along the road they ran 75 % of a wave, at 2.5 Hz against the
## footfalls' 3 Hz.
const HOOF_NEAR_GATE_M := 70.0
## A ram's stroke: about 1.2 s, never quite a metronome, and never quite the same blow.
const RAM_GAPS_S: Array[float] = [1.15, 1.25]
const RAM_PITCH: Array[float] = [1.0, 0.96, 1.03, 0.94]
const COIN_EVERY_S := 0.3
## Audio only, never the sim: other riders' bolts and Scorpions and all kills are thinned, so a rider's own hits can be
## told apart. Arrows are not: every arrow that lands is heard, a rider's own or another's.
const OTHER_IMPACT_EVERY_S := 0.7
const KILL_EVERY_S := 1.5
## hit_wood's pitch for each blow: three files at about one a second would otherwise repeat.
const WOOD_PITCH: Array[float] = [1.0, 0.95, 1.06, 0.97, 1.04, 0.94, 1.02]
## A ram's battering is one leak per whole HP: the alarm answers the first, not each.
const LEAK_ALARM_EVERY_S := 3.0
## An alarm is what a rider acts on, and it rings at about 660 Hz, where the arrows' crowd sits: the crowd steps back
## for its first strokes. On top of the arrow's own level, and only the arrows.
const ALARM_CROWD_DB := -6.0
const ALARM_CROWD_S := 0.7
const MAX_SHOT_SOUNDS_PER_TICK := 3
## A shot's flight sound never runs longer than the host flies anything.
const FLIGHT_MIN_S := 0.1
const FLIGHT_MAX_S := 8.0
## Side of the screen: art x from the middle over half the width, then the panned sends' reach.
const PAN_SPREAD := 0.75
## Volleys overlap: a real wave's organ fires every 0.87 to 1.5 s and an arrow flies about 4 s. Every other volley
## passes over at full level, the next this far under: with all of them at one level a rider hears haze and no single
## pass. Each still has its own release, flight and landing. Further under drops it below the scorecard's P3.
const VOLLEY_UNDER_DB := -6.0
## Each arrow's own small pitch and level, so about 12 a second of a few very short files never read as one file
## machine-gunning. Two low-discrepancy steps with no common period: no pair of an arrow's pitch and level comes back in
## an hour of arrows. View-only.
const ARROW_PITCH_SPREAD := 0.07
const ARROW_DB_SPREAD := 2.5
const ARROW_PITCH_STEP := 0.6180339887
const ARROW_DB_STEP := 0.7548776662
## The file of each arrow: never the one before it on that surface, otherwise out of order. A strict rotation came back
## on a near-twin in about two thirds of misses.
const ARROW_FILE_STEP := 0.4142135624
## The ear counts 3 or 4 events a second, and twelve arrows land in about 340 ms. An accent gives it those: every arrow
## on a body and at most one miss in SiegeShotSounds.ACCENT_GAP_S, this much over the rest.
const ARROW_ACCENT_DB := 6.0
## Near the camera louder, far quieter: this much either way, over this many art pixels from where on the screen the
## organ's arrows land on average (the road 40 to 115 m from it runs at about y 340 to 510).
const ARROW_DEPTH_DB := 3.0
const ARROW_DEPTH_MID_PX := 430.0
const ARROW_DEPTH_PX := 90.0
## An arrow's level over its cue never passes this, whatever accent and depth add: a body near the camera that is also
## an accent would otherwise go over the top of the master by itself.
const ARROW_LVL_MAX_DB := 2.0
## A volley comes down in a few metres, about one pan step of the road's side of the screen: the volley's place is a
## little wider than the picture and each arrow's distance from it much wider, or all twelve share one send.
const ARROW_PAN_WIDEN := 1.3
const ARROW_PAN_SCATTER := 7.0
## Gate hits answer what the gate lost since the last one, at most once a ram stroke, so the sound
## doesn't depend on the tick the damage came in: a host's fractions and a client's whole HP read
## the same. They and the hooves grow with the damage and the horses, up to these.
const GATE_HIT_EVERY_S := 1.2
const GATE_HIT_MIN_DROP := 0.5
const GATE_DMG_MAX_DB := 6.0
const HOOVES_MAX_DB := 4.0
## Every shot's own small pitch, from its spread seed: the release and flight of a single-file sound.
const SHOT_PITCH_STEP := 0.015
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

var _gate_mark: float = -1.0
var _gate_t: float = 0.0
var _paused: bool = false
var _hoof_t: float = 0.0
var _ram_t: float = 0.0
var _ram_n: int = 0
var last_flight_s: float = 0.0  ## the flight the last shot's sound was given (tests)
var _shots := SiegeShotSounds.new()
var _volley_n: int = 0
var _other_impact_t: float = 0.0
var _kill_t: float = 0.0
var _wood_n: int = 0
var _arrow_n: int = 0
var _arrow_file: Dictionary = {}
var _alarm_t: float = 0.0
var _view: SiegeView = null
var _coin_t: float = 0.0
var _leak_t: float = 0.0
var _gold_was: float = -1.0
var _shot_tick: int = -1
var _shot_sounds: int = 0
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
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("paused_changed", _on_paused_changed)


## SceneTree.paused is not used, so the view keeps calling update under a pause. The kit holds the
## strokes and the loops; the timers here are the adapter's own to stop.
func _on_paused_changed(paused: bool, _reason: String) -> void:
	_paused = paused


## The cue of an event, "" when this one stays silent (a rush's end, a refused purchase). The
## shot's kind and the Overdrive's state choose among several.
static func cue_for(kind: String, data: Dictionary) -> String:
	match kind:
		SiegeIds.EV_SHOT:
			return _shot_cue(int(data.get("kind", 0)))
		SiegeIds.EV_KILL:
			return CUE_KILL_ENGINE if SiegeIds.is_engine(int(data.get("et", 0))) else kind
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
	_alarm_t = maxf(_alarm_t - dt, 0.0)
	_other_impact_t = maxf(_other_impact_t - dt, 0.0)
	_kill_t = maxf(_kill_t - dt, 0.0)
	_view = view
	_shots.content = state.content
	_shots.path = state.path
	_shots.track(view.clock_s, state.enemies)
	_landings(state, view)
	_wheels(state, view)
	_works(state, view)
	_loops(state)
	_bed(state, dt)
	_gate(state, dt)
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
		var lead := r.peer == local_peer
		var params := {
			"p_eff": r.p_eff_w, "walkers": view.walker_count[slot], "far": 0.0 if lead else 1.0
		}
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
	# team_w is a 1 s mean: it outlives the last stroke of a rider who stopped dead.
	if in_wave and state.team_w > 5.0 and _a_wheel_turns(state):
		kit.set_loop(LOOP_JUNCTION, {"team_w": state.team_w})
	var tar_m := state.station(SiegeIds.STATION_TAR).m
	if state.tar.cauldron_l > 0.5:
		kit.set_loop(LOOP_BUBBLE, {"m": tar_m})
		if in_wave and tar_m > 0.0:
			kit.set_loop(LOOP_POUR, {})
	if _tower_walking(state):
		kit.set_loop(LOOP_TOWER, {})


static func _a_wheel_turns(state: SiegeState) -> bool:
	for r in state.riders:
		if r.cadence_rpm > CrankClock.STOP_RPM:
			return true
	return false


static func _tower_walking(state: SiegeState) -> bool:
	for e in state.enemies:
		if e.type == SiegeIds.ENEMY_TOWER and e.st == SiegeIds.EN_WALK:
			return true
	return false


func _bed(state: SiegeState, dt: float) -> void:
	_gust_t += dt
	var gust := 0.5 + 0.3 * sin(_gust_t * GUST_RATES.x) + 0.2 * sin(_gust_t * GUST_RATES.y)
	# Under a pause the bed still runs, and a burst spot's later beats wait for the resume: no spot of
	# the battle or of the calm may start, or they all land together when the picture moves again.
	var enemies := 0.0 if _paused else float(state.enemies.size())
	# A warm-up wave is the calm hill too: the lark and the anvil belong to all but a real wave.
	var in_wave := 1.0 if _paused or state.role == SiegeIds.ROLE_WAVE else 0.0
	kit.bed_params({"gust": gust, "enemies": enemies, "in_wave": in_wave})


## The module's cues. A shot starts its release and its flight here, and its landing comes from
## _landings; events of one rider are that rider's: full level for them, lower for the rest of the
## crew.
func on_cue(kind: String, data: Dictionary) -> void:
	var cue_name := cue_for(kind, data)
	if cue_name == "":
		return
	match kind:
		SiegeIds.EV_SHOT:
			_shot(cue_name, data)
		SiegeIds.EV_KILL:
			# A ram or a tower going down is always heard; a body among the many, one in a while.
			if cue_name == CUE_KILL_ENGINE or _kill_t <= 0.0:
				_kill_t = KILL_EVERY_S
				kit.cue(cue_name, {"pan": _enemy_pan(int(data.get("id", -1)))})
		SiegeIds.EV_LEAK:
			if _leak_t <= 0.0:
				_leak_t = LEAK_ALARM_EVERY_S
				_alarm_t = ALARM_CROWD_S
				kit.cue(cue_name)
		SiegeIds.EV_REACH:
			# It rings for the leak that comes with it: two alarms at once took a prompt's margin under +6 LU.
			_leak_t = LEAK_ALARM_EVERY_S
			_alarm_t = ALARM_CROWD_S
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
	var src := int(data.get("src", 0))
	var lead := is_mine(src)
	# Past the cap a shot has no release and no flight of its own, and it still lands.
	var flight := _shots.add(data, tk * Wl.SIM_DT, _level_of(src), lead)
	if _shot_sounds > MAX_SHOT_SOUNDS_PER_TICK:
		return
	var sd := int(data.get("sd", 0))
	var weapon := SiegeShotSounds.weapon_of(int(data.get("kind", 0)))
	var lvl := 0.0
	if weapon == SiegeShotSounds.WEAPON_ARROW:
		lvl = VOLLEY_UNDER_DB if _volley_n % 2 == 1 else 0.0
		_volley_n += 1
	last_flight_s = clampf(float(flight["flight_s"]), FLIGHT_MIN_S, FLIGHT_MAX_S)
	(
		kit
		. cue(
			cue_name,
			{
				"p": 1.0 + SHOT_PITCH_STEP * float(posmod(sd, 7) - 3),
				"flight_s": last_flight_s,
				"pan0": _pan(flight["from"]),
				"pan1": _pan(flight["to"]),
				"lvl": lvl,
			},
			lead
		)
	)


## A shot is the local rider's if their wheel drives the station that fired it. Nobody drives a pad's Scorpion.
func is_mine(src: int) -> bool:
	if _view == null or _view.state == null:
		return false
	var st := _view.state
	return src == SiegeViewMath.lit_station(st, st.rider(local_peer))


func _level_of(src: int) -> int:
	if _view == null or _view.state == null or src > SiegeIds.SRC_PAD or src < 1:
		return 0
	return _view.state.station(src).level


## The flight this shot's sound is given, in seconds, as _shot works it out (tests).
func flight_of(data: Dictionary) -> float:
	var probe := SiegeShotSounds.new()
	probe.content = _shots.content
	probe.path = _shots.path
	return clampf(float(probe.add(data, 0.0)["flight_s"]), FLIGHT_MIN_S, FLIGHT_MAX_S)


## Every landing due on the clock the picture draws by. Paused, the shots hang in the air with it.
func _landings(state: SiegeState, view: SiegeView) -> void:
	if _paused or _shots.flying.is_empty():
		return
	for impact: Dictionary in _shots.step(view.clock_s, state.enemies):
		var lead := bool(impact["lead"])
		var weapon: String = impact["weapon"]
		var cue_name := "hit_%s_%s" % [weapon, impact["surface"]]
		var pan := _pan(impact["at"])
		if weapon == SiegeShotSounds.WEAPON_ARROW:
			_arrow_landing(cue_name, impact, lead)
			continue
		# A stone is an event whoever threw it.
		if not lead and weapon != SiegeShotSounds.WEAPON_STONE:
			if _other_impact_t > 0.0:
				continue
			_other_impact_t = OTHER_IMPACT_EVERY_S
		var pv: float = WOOD_PITCH[_wood_n % WOOD_PITCH.size()]
		_wood_n += 1
		kit.cue(cue_name, {"pan": pan, "lvl": 0.0, "pv": pv}, lead)


func _arrow_landing(cue_name: String, impact: Dictionary, lead: bool) -> void:
	var spread := arrow_spread(_arrow_n)
	var lvl := spread.y + _arrow_depth_db(impact["at"])
	lvl += ARROW_ACCENT_DB if bool(impact["accent"]) else 0.0
	var sound := "arrow_%s" % impact["surface"]
	var file := next_file(_arrow_file.get(sound, 0), _arrow_n, kit.variants_of(sound))
	_arrow_file[sound] = file
	_arrow_n += 1
	var vars := {
		"pan": _arrow_pan(impact["at"], impact["mid"]),
		"lvl": minf(lvl, ARROW_LVL_MAX_DB) + (ALARM_CROWD_DB if _alarm_t > 0.0 else 0.0),
		"pv": spread.x,
		"vr": file,
		"acc": 1.0 if bool(impact["accent"]) else 0.0,
	}
	kit.cue(cue_name, vars, lead)


## Which of a sound's `count` files plays after `was`: any other, chosen by n.
static func next_file(was: int, n: int, count: int) -> int:
	if count <= 1:
		return 0
	var step := 1 + floori(fposmod(float(n) * ARROW_FILE_STEP, 1.0) * float(count - 1))
	return posmod(was + step, count)


func _arrow_depth_db(at: Vector3) -> float:
	if _view == null or _view.bank == null:
		return 0.0
	var near := (_view.bank.to_art(at).y - ARROW_DEPTH_MID_PX) / ARROW_DEPTH_PX
	return clampf(near, -1.0, 1.0) * ARROW_DEPTH_DB


func _arrow_pan(at: Vector3, mid: Vector3) -> float:
	var middle := _pan(mid)
	var pan := middle * ARROW_PAN_WIDEN + (_pan(at) - middle) * ARROW_PAN_SCATTER
	return clampf(pan, -AudioBuses.PAN_MAX, AudioBuses.PAN_MAX)


## The nth arrow's pitch (x) and level in dB (y).
static func arrow_spread(n: int) -> Vector2:
	var a := fposmod(float(n) * ARROW_PITCH_STEP, 1.0)
	var b := fposmod(float(n) * ARROW_DB_STEP, 1.0)
	return Vector2(1.0 + ARROW_PITCH_SPREAD * (2.0 * a - 1.0), -ARROW_DB_SPREAD * b)


## -1 left of the screen .. 1 right, where the view draws world point `p`.
func _pan(p: Vector3) -> float:
	if _view == null or _view.bank == null:
		return 0.0
	var half := float(SiegeBakeBank.ART_SIZE.x) * 0.5
	return clampf((_view.bank.to_art(p).x - half) / half * PAN_SPREAD, -1.0, 1.0)


## A kill's side of the screen, from where the body was last seen: the rules took it off the list before the cue.
func _enemy_pan(enemy_id: int) -> float:
	var at: Variant = _shots.last_seen(enemy_id)
	return _pan(at) if at is Vector3 else 0.0


## The mark lowers only when a hit fires and rises with a repair, so damage in any size of step adds up.
func _gate(state: SiegeState, dt: float) -> void:
	_gate_t = maxf(_gate_t - dt, 0.0)
	if state.gate_hp > _gate_mark:
		_gate_mark = state.gate_hp
	var drop := _gate_mark - state.gate_hp
	if drop > GATE_HIT_MIN_DROP and _gate_t <= 0.0:
		_gate_t = GATE_HIT_EVERY_S
		_gate_mark = state.gate_hp
		kit.cue(CUE_GATE_HIT, {"dmg_db": minf(drop, GATE_DMG_MAX_DB)})


## The curtain or the coat changed its drawn stage: hot tar on wet timber.
func _tar_stages(state: SiegeState) -> void:
	var curtain := SiegeViewMath.curtain_stage(state.tar)
	var coat := SiegeViewMath.coat_stage(state.tar)
	if _curtain_stage >= 0 and (curtain != _curtain_stage or coat != _coat_stage):
		kit.cue(CUE_TAR_HISS)
	_curtain_stage = curtain
	_coat_stage = coat


func _enemies(state: SiegeState, dt: float) -> void:
	if _paused:
		return
	_hoof_t -= dt
	_ram_t -= dt
	var horses := 0
	var batter := false
	for e in state.enemies:
		if e.type == SiegeIds.ENEMY_CHARIOT and e.st == SiegeIds.EN_WALK and _near_gate(state, e):
			horses += 1
		elif e.type == SiegeIds.ENEMY_RAM and e.st == SiegeIds.EN_BATTER:
			batter = true
	if horses > 0 and _hoof_t <= 0.0:
		_hoof_t = HOOF_EVERY_S
		kit.cue(CUE_HOOVES, {"count_db": minf(float(horses), HOOVES_MAX_DB)})
	if batter and _ram_t <= 0.0:
		_ram_t = RAM_GAPS_S[_ram_n % RAM_GAPS_S.size()]
		kit.cue(CUE_RAM, {"p": RAM_PITCH[_ram_n % RAM_PITCH.size()]})
		_ram_n += 1


static func _near_gate(state: SiegeState, e: SiegeEnemyState) -> bool:
	return state.path == null or state.path.dist_to_gate(e.prog_m) <= HOOF_NEAR_GATE_M


func _coins(state: SiegeState, dt: float) -> void:
	_coin_t -= dt
	var me := state.rider(local_peer)
	if me == null:
		return
	if _gold_was >= 0.0 and floorf(me.gold) > floorf(_gold_was) and _coin_t <= 0.0:
		_coin_t = COIN_EVERY_S
		kit.cue(CUE_GOLD)
	_gold_was = me.gold

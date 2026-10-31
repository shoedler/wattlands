class_name TankAudio
extends Node
## Diesel Domestiques' sound on the platform's audio kit: the view's crank revolutions drive the machines' strokes, the
## game's events pick cues, and the numbers live in assets/tank/audio/audio.json. It maps state to parameters and events
## to cue names, and nothing else: the bank says what plays, this says when.
##
## The view creates it as a child, connects TankGame.cue to on_cue and calls update() every frame. What FTMS allows:
## cadence about once a second, no crank angle, so the strokes lock to the crank on screen exactly and to the rider's
## feet in rate.

## TankRig.SEATS -> the bank's machine.
const MACHINE_OF_SEAT := {
	"drive": "diesel",
	"gun": "dynamo",
	"loader": "steam",
	"lights": "arc",
	"sec": "feed",
	"repair": "repair",
}
const TRACK := "track"
## The track machine's "revolution": 2.4 m of travel holds three links and one squeak.
const TRACK_M_PER_REV := 2.4
## Sound runs at twice real speed here: the real 2.4-7 s would feel detached from the flash.
const BOOM_M_PER_S := 680.0
const BOOM_DELAY_S := Vector2(0.6, 3.5)
## Metres -> dB of a far sound.
const RANGE_NEAR_M := 800.0
const RANGE_FAR_M := 2400.0
const RANGE_DB := Vector2(-5.0, -12.0)
## incoming_whistle's file ends at impact: its rate fits the flight, and a flight too long for it waits (a far shell's
## arc takes 1.4 s at 800 m and 4.7 s at 2500 m). It stays faint until its last second: the shell is far until then.
const WHISTLE_FILE_S := 2.5
const WHISTLE_RATE := Vector2(0.63, 1.8)
## The Behemoth's main gun, over a far tank's.
const BOSS_THUMP_DB := 3.0
const BOSS_THUMP_PITCH := 0.8
## A far shell whose event has no flight time or range (SPEC_AUDIO 4.1).
const FALLBACK_FLIGHT_S := 2.5
const FALLBACK_RANGE_M := 1400.0
const HEAVY_BOOST_DB := 3.0
const OVER_PITCH := 0.8
## Each main-gun round and small explosion takes the next of these: a counter, so no two run the same and tests can
## pin the sequence. The gun has one file of each layer, so this is all its variation.
const GUN_PITCHES: Array[float] = [1.0, 0.97, 1.025, 0.985, 1.01]
const GUN_BOOSTS_DB: Array[float] = [0.0, -0.8, 0.4]
const SMALL_PITCHES: Array[float] = [1.0, 0.94, 1.07, 0.97, 1.03]
## The reload and an impact beside or on the hull, one file each: the next of these, as for the gun.
const LOAD_PITCHES: Array[float] = [1.0, 0.975, 1.02]
const IMPACT_PITCHES: Array[float] = [1.0, 0.96, 1.05, 0.98]
## A barrage (an overrun clearing the road) has no shell and no range: its kills roll in one after another.
const BARRAGE_DELAY_S := 1.0
const BARRAGE_STEP_S := 0.35
const BLOWOFF_AT := 0.5
## Over band the exhaust spits a little too; a lift-off is the full crackle.
const SPIT_POWER := Vector2(1.05, 1.3)
const SPIT_LEVEL := 0.5
## The bed's gust, two slow sines (rad/s): 33 s and 88 s.
const GUST_RAD_S := Vector2(0.19, 0.071)
## A near engine's distance is measured from the hull's front (rules px), as the rules place it.
const NEAR_LOOPS := {TankIds.ENEMY_RECON: "recon_engine", TankIds.ENEMY_TANKETTE: "tankette_engine"}
## One that got away has left the near panel, not the night: it drives on at about its flee speed until the bank's
## distance curve has taken it down.
const NEAR_FLEE_PX_S := 120.0
const NEAR_GONE_PX := 620.0
## A round from a near gun on the hull: the event's damage, rounded (a far tank's is at least 2, solo). Not an impact.
const SMALL_ROUND_DMG := 1
## Events that make no sound of their own, each for a reason that holds. RAM: reserved, nothing emits it. OVERRUN: the
## segment's horn follows at once, and any kill it causes rolls in BY_BARRAGE. ESCAPED: the sound is the engine driving
## off, which _near_engines carries on after the event; a toast says so too.
const SILENT_EVENTS: Array[String] = [TankEvents.RAM, TankEvents.OVERRUN, TankEvents.ESCAPED]
## Event -> the cues it can play (the bank has each one; tests hold this to on_cue).
const EVENT_CUES := {
	TankEvents.SEGMENT: ["segment"],
	TankEvents.TIME_UP: ["segment"],
	TankEvents.ROTATION: ["lever"],
	TankEvents.LEVER: ["lever"],
	TankEvents.SEAT: ["lever"],
	TankEvents.TURN: ["lever"],
	TankEvents.SHOT: ["shot_main", "shot_bow", "shot_near_mg", "enemy_thump", "incoming_whistle"],
	TankEvents.HIT: ["hit_tank", "hit_small", "hit_far", "hit_near"],
	TankEvents.KILL: ["kill_near", "kill_far", "kill_boss"],
	TankEvents.BREAKDOWN: ["breakdown"],
	TankEvents.REPAIRED: ["repaired"],
	TankEvents.STAGE_RESTART: ["repaired"],
	TankEvents.BOSS_PHASE: ["boss_phase"],
	TankEvents.LATCH: ["latch_load", "latch_hoist"],
	TankEvents.EVADE: ["evade"],
	TankEvents.DODGE: ["evade"],
	TankEvents.TANK_LOST: ["tank_lost"],
	TankEvents.AMBUSH: ["ambush"],
	TankEvents.SPLASH: ["splash_far", "splash_near"],
}
## Cues that state, not an event, starts.
const STATE_CUES: Array[String] = ["turbo_blowoff", "patch"]
const BANK_PATH := "res://assets/tank/audio/audio.json"

var game: TankGame = null
var kit := GameAudioKit.new()
var rng_seed: int = 0
var local_peer: int = 0
## Base sound ids, newest last, with their levels and due times (the kit's records; tests read them).
var played: Array[String]:
	get:
		return kit.played
var played_db: Array[float]:
	get:
		return kit.played_db
var played_t: Array[float]:
	get:
		return kit.played_t
## What the bed was last told (tests read it).
var bed_now: Dictionary = {}

var _lift := LiftOffDetector.new()
var _lift_was: float = 0.0
var _patches_seen: int = -1
var _last_far_m: float = FALLBACK_RANGE_M
var _far_kills: int = 0
var _barrage_kills: int = 0
var _shots: int = 0
var _small_kills: int = 0
var _loads: int = 0
var _impacts: int = 0
## Near threats killed since the last update(). The rules erase one before they send the HIT that killed it, so the
## HIT can only know its target was near from here.
var _near_killed: Dictionary = {}
## Each near engine's distance last frame, and those driving off after an escape (loop id -> px).
var _near_last: Dictionary = {}
var _near_gone: Dictionary = {}
## The tread's metres as drawn, always forward: a tow runs it backwards, and it still clanks.
var _tread_m: float = 0.0
var _tread_was: float = NAN
var _t: float = 0.0


func _ready() -> void:
	if game != null and game.ctx != null:
		local_peer = game.ctx.local_peer
		if rng_seed == 0:
			rng_seed = SeededRng.derive(game.ctx.seed, "tank:audio")
	add_child(kit)
	kit.setup(BANK_PATH, rng_seed)
	kit.set_bed("night_forest")


# --- Curves -----------------------------------------------------------------------------------------------


## When a far landing is heard after it is seen.
static func boom_delay(range_m: float) -> float:
	return clampf(range_m / BOOM_M_PER_S, BOOM_DELAY_S.x, BOOM_DELAY_S.y)


## How much the distance takes off a far sound.
static func range_db(range_m: float) -> float:
	return remap(
		clampf(range_m, RANGE_NEAR_M, RANGE_FAR_M),
		RANGE_NEAR_M,
		RANGE_FAR_M,
		RANGE_DB.x,
		RANGE_DB.y
	)


## The whistle's rate, so that its file ends at the shell's impact.
static func whistle_rate(flight_s: float) -> float:
	return clampf(WHISTLE_FILE_S / maxf(flight_s, 0.01), WHISTLE_RATE.x, WHISTLE_RATE.y)


## How long the whistle waits, so that it still ends at impact on a flight longer than its slowest playing.
static func whistle_delay(flight_s: float) -> float:
	return maxf(flight_s - WHISTLE_FILE_S / whistle_rate(flight_s), 0.0)


## The hit's weight: 0 damage -6 dB, 24 or more 0 dB.
static func dmg_db(dmg: float) -> float:
	return -6.0 + clampf(dmg, 0.0, 24.0) * 0.25


## The crackle's drive: the lift-off detector's level, or the spit of a rider well over band.
static func crackle_level(lift: float, power: float) -> float:
	return maxf(lift, SPIT_LEVEL * smoothstep(SPIT_POWER.x, SPIT_POWER.y, power))


## How far the arc climbs its ladder (TankMech's `reach`): what its zap's level follows.
static func ladder_reach(power: float) -> float:
	return 0.25 + 0.75 * smoothstep(0.3, 0.9, power)


## The main gun's cue variables for its round number `n`.
static func shot_vars(shell: int, n: int = 0) -> Dictionary:
	var heavy := shell == TankIds.SHELL_HEAVY or shell == TankIds.SHELL_OVER
	var pitch := GUN_PITCHES[n % GUN_PITCHES.size()]
	return {
		"boost": GUN_BOOSTS_DB[n % GUN_BOOSTS_DB.size()] + (HEAVY_BOOST_DB if heavy else 0.0),
		"gun_pitch": pitch * (OVER_PITCH if shell == TankIds.SHELL_OVER else 1.0),
	}


# --- Events -----------------------------------------------------------------------------------------------


## Every game event (TankGame.cue: the host where it sends it, clients in apply_event).
func on_cue(kind: String, data: Dictionary) -> void:
	var own := _is_own_slot(int(data.get("s", -1)))
	match kind:
		TankEvents.SHOT:
			_shot(data, own)
		TankEvents.HIT:
			_hit(data)
		TankEvents.KILL:
			_kill(data)
		TankEvents.SPLASH:
			_splash(data)
		TankEvents.LATCH:
			_latch(own)
		TankEvents.EVADE:
			if int(data.get("ok", 0)) == 1:
				kit.cue("evade")
		TankEvents.DODGE:
			kit.cue("evade")
		TankEvents.SEAT, TankEvents.LEVER, TankEvents.ROTATION, TankEvents.TURN:
			kit.cue("lever", {}, own)
		TankEvents.SEGMENT, TankEvents.TIME_UP:
			kit.cue("segment")
		TankEvents.BREAKDOWN:
			kit.cue("breakdown")
		TankEvents.REPAIRED, TankEvents.STAGE_RESTART:
			kit.cue("repaired")
		TankEvents.BOSS_PHASE:
			kit.cue("boss_phase")
		TankEvents.TANK_LOST:
			kit.cue("tank_lost")
		TankEvents.AMBUSH:
			kit.cue("ambush")
		TankEvents.ESCAPED:
			_near_escaped(int(data.get("e", 0)))


func _shot(data: Dictionary, own: bool) -> void:
	var shell := int(data.get("sh", 0))
	if shell == TankIds.SHELL_BOW:
		kit.cue("shot_bow", {}, own)
	elif shell == TankIds.SHELL_ENEMY or shell == TankIds.SHELL_BOSS_MAIN:
		_enemy_shot(data)
	else:
		kit.cue("shot_main", shot_vars(shell, _shots), own)
		_shots += 1


func _enemy_shot(data: Dictionary) -> void:
	if TankIds.is_near_code(int(data.get("e", 0))):
		kit.cue("shot_near_mg")
		return
	var flight := float(data.get("flight_s", FALLBACK_FLIGHT_S))
	var range_m := float(data.get("rng_m", 0.0))
	if range_m <= 0.0:
		range_m = FALLBACK_RANGE_M
	var boss := int(data.get("sh", 0)) == TankIds.SHELL_BOSS_MAIN
	(
		kit
		. cue(
			"enemy_thump",
			{
				"delay": boom_delay(range_m),
				"range_db": range_db(range_m) + (BOSS_THUMP_DB if boss else 0.0),
				"thump_pitch": BOSS_THUMP_PITCH if boss else 1.0,
			}
		)
	)
	kit.cue("incoming_whistle", {"rate": whistle_rate(flight), "delay": whistle_delay(flight)})


func _hit(data: Dictionary) -> void:
	var on := int(data.get("on", -1))
	if on == TankEvents.ON_TANK:
		if _is_small_round(data):
			kit.cue("hit_small")
			return
		var dmg := dmg_db(float(data.get("dmg", 0)))
		kit.cue("hit_tank", {"dmg_db": dmg, "impact_pitch": _next_impact()})
	elif (
		on == TankEvents.ON_OBSTACLE
		or int(data.get("sh", 0)) == TankIds.SHELL_BOW
		or _is_near_target(int(data.get("id", 0)))
	):
		kit.cue("hit_near")
	else:
		var x := float(data.get("x", 0))
		_last_far_m = x if x > 0.0 else FALLBACK_RANGE_M
		kit.cue("hit_far", _far_vars(_last_far_m))


## A near gun's round rings on the plate. A breakdown or a tow also reports any shell as 0 damage: that one still lands.
func _is_small_round(data: Dictionary) -> bool:
	if int(data.get("sh", 0)) != TankIds.SHELL_ENEMY or int(data.get("dmg", 0)) > SMALL_ROUND_DMG:
		return false
	return game == null or game.state == null or not game.state.hull.out_of_action()


## A near shell's HIT sends world px in `x`, not metres, so it must not read as a far boom: its target says which.
func _is_near_target(id: int) -> bool:
	if _near_killed.has(id):
		return true
	if game == null or game.state == null:
		return false
	for e: TankEnemyState in game.state.enemies:
		if e.id == id:
			return e.is_near()
	return false


func _next_impact() -> float:
	var pitch := IMPACT_PITCHES[_impacts % IMPACT_PITCHES.size()]
	_impacts += 1
	return pitch


## A far kill goes up with the shell's own boom. The rules send the kill before the HIT or SPLASH that gives its range
## (TankShells._impact_far), so it waits for update(), by when the same tick's events have all arrived.
func _kill(data: Dictionary) -> void:
	var code := int(data.get("e", 0))
	if code == TankIds.BOSS_CODE:
		kit.cue("kill_boss")
	elif TankIds.is_near_code(code) or int(data.get("by", 0)) == TankEvents.BY_BOW:
		kit.cue("kill_near", {"small_pitch": SMALL_PITCHES[_small_kills % SMALL_PITCHES.size()]})
		_near_last.erase(NEAR_LOOPS.get(TankIds.enemy_of(code), ""))
		_small_kills += 1
		_near_killed[int(data.get("id", 0))] = true
	elif int(data.get("by", 0)) == TankEvents.BY_BARRAGE:
		var delay := BARRAGE_DELAY_S + BARRAGE_STEP_S * float(_barrage_kills)
		kit.cue("kill_far", {"delay": delay, "range_db": range_db(FALLBACK_RANGE_M)})
		_barrage_kills += 1
	else:
		_far_kills += 1


func _flush_far_kills() -> void:
	for _i in _far_kills:
		kit.cue("kill_far", _far_vars(_last_far_m))
	_far_kills = 0
	_barrage_kills = 0


func _splash(data: Dictionary) -> void:
	if int(data.get("f", 0)) == 1:
		var r := float(data.get("r", 0))
		_last_far_m = r if r > 0.0 else FALLBACK_RANGE_M
		kit.cue("splash_far", _far_vars(_last_far_m))
	else:
		kit.cue("splash_near", {"impact_pitch": _next_impact()})


func _far_vars(range_m: float) -> Dictionary:
	return {"delay": boom_delay(range_m), "range_db": range_db(range_m)}


## The rack holds shells: the hoist, the slide and the breech. An empty Loader's seat: only the pawl.
func _latch(own: bool) -> void:
	var loader: TankStationState = null
	if game != null and game.state != null:
		loader = game.state.station(TankIds.ENGINE_STEAM)
	if loader == null or loader.is_empty():
		kit.cue("latch_hoist", {}, own)
		return
	kit.cue("latch_load", {"load_pitch": LOAD_PITCHES[_loads % LOAD_PITCHES.size()]}, own)
	_loads += 1


func _is_own_slot(slot: int) -> bool:
	if slot < 0 or game == null or game.state == null:
		return false
	var r := game.state.rider(local_peer)
	return r != null and r.slot == slot


# --- Per frame --------------------------------------------------------------------------------------------


## `feed` is TankView.audio_feed(state): seat -> {revs, rpm, power, lead}. `travel_m`: the track's metres, as drawn.
## `far_fight`: the far panel shows an enemy.
func update(
	state: TankState,
	dt: float,
	p_local_peer: int,
	feed: Dictionary,
	travel_m: float,
	far_fight: bool = false
) -> void:
	local_peer = p_local_peer
	_t += dt
	_flush_far_kills()
	_near_killed.clear()
	for seat: String in MACHINE_OF_SEAT:
		_drive_seat(state, seat, feed.get(seat, {}), dt)
	_drive_track(state, travel_m, _has_seat(feed))
	_near_engines(state, dt)
	_patches(state, feed.get("repair", {}))
	bed_now = _bed_params(state, far_fight)
	kit.bed_params(bed_now)
	kit.commit(dt)


func _drive_seat(state: TankState, seat: String, f: Dictionary, dt: float) -> void:
	var rpm := float(f.get("rpm", 0.0))
	var power := float(f.get("power", 0.0))
	var lead := bool(f.get("lead", false))
	var turning := rpm > CrankClock.STOP_RPM
	var lift := _lift_off(power, turning, lead, dt) if seat == "drive" else 0.0
	# A lead who stops keeps the seat: the kit closes its loops and plans nothing, and the room still has a lead. Only
	# a spectator lifts the other machines (SPEC_AUDIO 1.3, 5).
	if not turning and not lead:
		kit.stop_machine(seat)
		return
	var machine: String = MACHINE_OF_SEAT[seat]
	var params := _machine_params(state, seat, power, lift)
	kit.drive(seat, machine, float(f.get("revs", 0.0)), rpm, params, lead)


## The detector's level. The turbo dumps once as it rises past BLOWOFF_AT, if the engine still turns.
func _lift_off(power: float, turning: bool, lead: bool, dt: float) -> float:
	var level := _lift.update(power, dt)
	if turning and level >= BLOWOFF_AT and _lift_was < BLOWOFF_AT:
		kit.cue("turbo_blowoff", {}, lead)
	_lift_was = level
	return level


func _machine_params(state: TankState, seat: String, power: float, lift: float) -> Dictionary:
	var over := TankMech._over(power)
	var params := {"power": power, "over": over}
	match seat:
		"drive":
			params["liftoff"] = crackle_level(lift, power)
			params["speed"] = state.hull.speed_mps
		"gun":
			var dynamo := state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
			params["hoist_s"] = dynamo.hoist_s if dynamo != null else 0.0
		"loader":
			var steam := state.station(TankIds.ENGINE_STEAM) as TankSteamState
			if steam != null:
				params["pressure_pct"] = steam.pressure_pct
				params["loaded"] = 1.0 if steam.loaded else 0.0
				params["over"] = maxf(over, 1.0 if steam.over else 0.0)
		"lights":
			params["reach"] = ladder_reach(power)
		"sec":
			var feed := state.station(TankIds.ENGINE_FEED) as TankFeedState
			params["rounds"] = float(feed.rounds) if feed != null else 0.0
			params["firing"] = 1.0 if feed != null and feed.rpm > 0.0 else 0.0
		"repair":
			var rep := state.station(TankIds.ENGINE_REPAIR) as TankRepairState
			params["repairing"] = 1.0 if rep != null and rep.working else 0.0
	return params


## The track is locked to the distance on screen, as a crank to its cadence. Every rider hears it at full level; a
## spectator hears it with the machines, or its lead would cost them the kit's lift for a room with no lead. Under tow
## the rules' hull stands still and the view creeps it back with the tread reversed: the links follow the tread.
func _drive_track(state: TankState, travel_m: float, lead: bool) -> void:
	if is_nan(_tread_was):
		_tread_was = travel_m
	_tread_m += absf(travel_m - _tread_was)
	_tread_was = travel_m
	var speed := (
		TankView.TOW_PX_S / (TankConst.PX_PER_M * TankView.S)
		if state.hull.tow_s > 0.0
		else state.hull.speed_mps
	)
	var rpm := speed / TRACK_M_PER_REV * 60.0
	if rpm <= CrankClock.STOP_RPM:
		kit.stop_machine(TRACK)
		return
	kit.drive(TRACK, TRACK, _tread_m / TRACK_M_PER_REV, rpm, {"speed": speed}, lead)


func _has_seat(feed: Dictionary) -> bool:
	for seat: String in feed:
		if bool((feed[seat] as Dictionary).get("lead", false)):
			return true
	return false


## Each near kind's engine runs while one of them lives, at the nearest one's distance, revving as it drives and
## idling down when it stops to fire. One that got away drives on and fades; a kill just ends it.
func _near_engines(state: TankState, dt: float) -> void:
	var front := state.hull.x_px + float(state.hull.hull_w)
	var nearest := {}
	var rev := {}
	for e: TankEnemyState in state.enemies:
		if not e.is_near() or e.mode == TankIds.EM_DEAD:
			continue
		var loop_id: String = NEAR_LOOPS.get(TankIds.enemy_of(e.code), "")
		var dist := maxf(e.x_px - front, 0.0)
		if loop_id != "" and dist < float(nearest.get(loop_id, INF)):
			nearest[loop_id] = dist
			rev[loop_id] = 0.0 if e.mode == TankIds.EM_PAUSE else 1.0
	for loop_id: String in nearest:
		_near_last[loop_id] = nearest[loop_id]
		kit.set_loop(loop_id, {"dist": nearest[loop_id], "rev": rev[loop_id]})
	for loop_id: String in _near_gone.keys():
		var dist: float = float(_near_gone[loop_id]) + NEAR_FLEE_PX_S * dt
		if nearest.has(loop_id) or dist >= NEAR_GONE_PX or state.hull.tow_s > 0.0:
			_near_gone.erase(loop_id)
			continue
		_near_gone[loop_id] = dist
		kit.set_loop(loop_id, {"dist": dist, "rev": 1.0})


## The rules erase it as they send this, so the distance is the last one heard. No engine heard, nothing to carry on.
func _near_escaped(code: int) -> void:
	var loop_id: String = NEAR_LOOPS.get(TankIds.enemy_of(code), "")
	if _near_last.has(loop_id):
		_near_gone[loop_id] = _near_last[loop_id]
		_near_last.erase(loop_id)


## The press closes when a patch is done: it follows the hull rebuilt, not the crank.
func _patches(state: TankState, f: Dictionary) -> void:
	var rep := state.station(TankIds.ENGINE_REPAIR) as TankRepairState
	if rep == null:
		return
	if _patches_seen >= 0 and rep.patches > _patches_seen:
		kit.cue("patch", {}, bool(f.get("lead", false)))
	_patches_seen = rep.patches


## gust: two slow sines that never quite repeat, and keep off the high wind's own 13 and 26 s.
## combat: the depot and the cool-down hear no far battle, and neither does a real fight in the far panel: a far thump
## there is a shot at this tank, and must never be just the night.
func _bed_params(state: TankState, far_fight: bool) -> Dictionary:
	var quiet := state.seg.seg == TankIds.SEG_DEPOT or state.in_cooldown() or far_fight
	return {
		"gust": 0.5 + 0.3 * sin(_t * GUST_RAD_S.x) + 0.2 * sin(_t * GUST_RAD_S.y + 1.3),
		"speed": state.hull.speed_mps,
		"combat": 0.0 if quiet else 1.0,
	}

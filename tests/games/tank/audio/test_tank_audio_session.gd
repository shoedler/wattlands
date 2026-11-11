extends GutTest
## D8 on the real rules: TankGame.cue through the adapter, as the view connects it, over a Hard session. Every event
## the game really emits, in the order it emits them, must leave a record or be listed silent. A table can agree with
## itself; this is the check that the far kill's order and the rules' numbers reach the sound.

const F := preload("res://tests/games/tank/tank_fakes.gd")
const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const FRAME_S := 1.0 / 20.0
const CHECKPOINT := 4

var _kinds: Dictionary = {}
var _silent_heard: Array[String] = []
var _unheard: Array[String] = []
var _far_kills: int = 0
var _far_kills_on_time: int = 0
var _shots_with_flight: int = 0
var _far_enemy_shots: int = 0
var _played_once: bool = false


func before_each() -> void:
	AudioBuses.clear_ducks()


func after_each() -> void:
	AudioBuses.clear_ducks()


## A sound starts now, or waits in the kit's queue for its delay.
func _heard(a: TankAudio, was_pending: int) -> int:
	return a.played.size() + a.kit._pending.size() - was_pending


## Hands one tick's events to the adapter in the order the game sent them, then the frame's update, as the view does.
func _deliver(a: TankAudio, game: TankGame, queued: Array[Array]) -> void:
	var far_kills := 0
	for ev: Array in queued:
		var kind: String = ev[0]
		var data: Dictionary = ev[1]
		_kinds[kind] = int(_kinds.get(kind, 0)) + 1
		var pending := a.kit._pending.size()
		a.kit.clear_played()
		a.on_cue(kind, data)
		var heard := _heard(a, pending)
		if kind in TankAudio.SILENT_EVENTS:
			if heard != 0:
				_silent_heard.append(kind)
			continue
		if kind == TankEvents.KILL and heard == 0:
			far_kills += 1  # goes up at update()
			continue
		if kind == TankEvents.EVADE and int(data.get("ok", 0)) == 0:
			continue  # a shot not evaded makes no lurch
		if heard == 0:
			_unheard.append(kind)
		if kind == TankEvents.SHOT:
			_note_shot(data)
	a.update(game.state, FRAME_S, 1, {}, 0.0)
	_far_kills += far_kills
	_far_kills_on_time += _kills_with_their_boom(a, far_kills)


func _note_shot(data: Dictionary) -> void:
	var sh := int(data.get("sh", 0))
	if sh != TankIds.SHELL_ENEMY and sh != TankIds.SHELL_BOSS_MAIN:
		return
	if TankIds.is_near_code(int(data.get("e", 0))):
		return
	_far_enemy_shots += 1
	if float(data.get("flight_s", 0.0)) > 0.0 and float(data.get("rng_m", 0.0)) > 0.0:
		_shots_with_flight += 1


## How many of the newest `n` explosions wait as long as a far_boom does, within 1 ms: the boom of their own shell.
func _kills_with_their_boom(a: TankAudio, n: int) -> int:
	if n == 0:
		return 0
	var booms: Array[float] = []
	var kills: Array[float] = []
	for p: Dictionary in a.kit._pending:
		if str(p["sound"]) == "far_boom":
			booms.append(float(p["left"]))
		elif str(p["sound"]) == "explode_big":
			kills.append(float(p["left"]))
	var on_time := 0
	for left: float in kills.slice(maxi(kills.size() - n, 0)):
		for b in booms:
			if absf(b - left) < 0.001:
				on_time += 1
				break
	return on_time


func _play(
	content: String, power_pct: float, seconds: float, humans: int = 2, bots: int = 2
) -> void:
	var ctx := F.make_ctx(humans, bots, content, Wl.HOST, 1, 3)
	ctx.options["difficulty"] = TankIds.DIFF_HARD
	var game := F.make_game(ctx)
	autofree(game)
	var a := TankAudio.new()
	a.game = game
	add_child_autofree(a)
	var queued: Array[Array] = []
	var on_game_cue := func(kind: String, data: Dictionary) -> void: queued.append([kind, data])
	game.cue.connect(on_game_cue)
	var clock := F.clock_of(game)
	var tick := 0
	var frames := roundi(seconds / FRAME_S)
	for _i in frames:
		tick = F.run(game, clock.plans, tick, FRAME_S, power_pct, clock)
		_deliver(a, game, queued)
		queued.clear()
	game.cue.disconnect(on_game_cue)


## One compliant Hard session, shared by the tests that read it.
func _compliant_session() -> void:
	if _played_once:
		return
	_played_once = true
	_play("ambush_15", 100.0, 600.0)


func test_a_hard_session_every_event_it_emits_is_heard_or_listed_silent() -> void:
	_compliant_session()
	gut.p("events: %s" % JSON.stringify(_kinds))
	assert_eq(_unheard, [] as Array[String], "every emitted event made its sound")
	assert_eq(_silent_heard, [] as Array[String], "the silent ones stayed silent")
	for kind: String in [
		TankEvents.SEGMENT,
		TankEvents.SHOT,
		TankEvents.HIT,
		TankEvents.KILL,
		TankEvents.SPLASH,
		TankEvents.AMBUSH,
		TankEvents.LATCH,
	]:
		assert_gt(int(_kinds.get(kind, 0)), 0, "the session really emitted %s" % kind)


func test_on_the_real_rules_a_far_kill_goes_up_with_its_own_boom() -> void:
	_compliant_session()
	assert_gt(_far_kills, 0, "the session killed something far away")
	assert_eq(_far_kills_on_time, _far_kills, "each with the boom of its own shell")


func test_on_the_real_rules_a_far_enemy_shot_brings_its_flight_and_range() -> void:
	_compliant_session()
	assert_gt(_far_enemy_shots, 0, "the enemy fired from far away")
	assert_eq(_shots_with_flight, _far_enemy_shots, "SHOT carries flight_s and rng_m")


## The one way a far boom could come from a near hit: the main gun with no target, its barrel low, a recon in the way.
## Returns [the adapter, the events], the shell's whole flight handed over as the view would.
func _near_shot(hp: float) -> Array:
	var quiet := func(files: Dictionary) -> void:
		(files["mission"]["segments"][CHECKPOINT] as Dictionary).merge(
			{"encounters": [], "obstacles": []}, true
		)
	var rig := TankRulesRig.new(2, "ashfall_road", 7, quiet)
	rig.enter(CHECKPOINT, 5.0)
	rig.dynamo().bank = 100.0
	var e := rig.near(TankIds.ENEMY_RECON, 90.0)
	TankAux.of(rig.state).enemy_age[e.id] = -1.0e6
	e.hp = hp
	e.hp_max = maxf(hp, 1.0)
	e.gun_s = 1.0e6
	rig.hull().target_id = 0
	rig.hull().elev_deg = -6.0
	rig.hull().elev_target_deg = -6.0
	rig.hull().aim_pause_s = 99.0
	rig.load_shell(TankIds.SHELL_HEAVY)
	var game := U.make_game(rig.state, Wl.HOST, 1)
	autofree(game)
	var a := TankAudio.new()
	a.game = game
	add_child_autofree(a)
	var all: Array[Dictionary] = []
	assert_true(TankGun.fire(rig.state, TankAux.of(rig.state), rig.dynamo(), false, all), "fired")
	for _i in 60:
		all.append_array(rig.run(0.05))
	for ev: Dictionary in all:
		a.on_cue(str(ev["type"]), ev)
	return [a, all]


func _main_gun_hits(events: Array) -> Array:
	return events.filter(
		func(ev: Dictionary) -> bool:
			return (
				str(ev["type"]) == TankEvents.HIT
				and int(ev["on"]) == TankEvents.ON_ENEMY
				and int(ev["sh"]) == TankIds.SHELL_HEAVY
			)
	)


func _pending_of(a: TankAudio, sound: String) -> int:
	var n := 0
	for p: Dictionary in a.kit._pending:
		if str(p["sound"]) == sound:
			n += 1
	return n


func test_on_the_real_rules_a_main_gun_round_on_a_near_threat_is_near() -> void:
	var run := _near_shot(5000.0)
	var a: TankAudio = run[0]
	var hits := _main_gun_hits(run[1])
	assert_eq(hits.size(), 1, "the round hit the recon")
	assert_gt(float(hits[0]["x"]), 0.0, "the rules send world px")
	assert_has(a.played, "far_hit_metal", "at once")
	assert_eq(_pending_of(a, "far_boom"), 0, "no boom on its way")
	assert_eq(_pending_of(a, "far_hit_metal"), 0)
	assert_does_not_have(a.played, "far_boom")


func test_on_the_real_rules_the_round_that_kills_a_near_threat_is_near() -> void:
	var run := _near_shot(1.0)
	var a: TankAudio = run[0]
	var kills: Array = (run[1] as Array).filter(
		func(ev: Dictionary) -> bool: return str(ev["type"]) == TankEvents.KILL
	)
	assert_eq(kills.size(), 1, "the round killed the recon")
	assert_eq(_main_gun_hits(run[1]).size(), 1, "and its HIT came after")
	assert_has(a.played, "explode_small")
	assert_eq(_pending_of(a, "far_boom"), 0, "no boom on its way")
	assert_eq(_pending_of(a, "explode_big"), 0)
	assert_does_not_have(a.played, "far_boom")


func test_a_crew_that_gives_up_loses_the_tank_and_hears_it() -> void:
	_kinds = {}
	_unheard = []
	_play("ambush_15", 20.0, 840.0)
	gut.p("events: %s" % JSON.stringify(_kinds))
	assert_eq(_unheard, [] as Array[String])
	assert_gt(int(_kinds.get(TankEvents.TANK_LOST, 0)), 0, "Hard takes the hull")
	assert_gt(int(_kinds.get(TankEvents.STAGE_RESTART, 0)), 0, "and the tow brings it back")

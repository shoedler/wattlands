extends GutTest
## BRIEF 3.6 cadence_band ("bots and MockTrainer's band-tracking cadence policy follow it"),
## end to end: run_game_sim's bots ride Bots.RIDER_SPEC on a real LocalRider, SafetyGovernor
## and MockTrainer, and a band the game publishes with ctx.directives.cadence_band reaches the
## bot's MockTrainer through the DirectiveRouter. Bot 1 gets a 100-120 rpm band at tick 10
## (0.5 s) and loses it at tick 500 (25 s); bot 2 never gets one. The game reads the bots'
## cadence in frame.players. Two runs with one seed give the same cadences and the same
## deterministic_hash (the band noise is seeded from the run's seed).

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")
const FIXTURES := "res://tests/fixtures/games"
const PUBLISH_TICK := 10
const CLEAR_TICK := 500
const BAND_LO := 100.0
const BAND_HI := 120.0
## Bots.make_slot's preferred cadence and MockTrainer's band noise bound.
const PREFERRED_RPM := 90.0
const NOISE_RPM := 1.5
## Lag left 6.5 s after a 20 rpm step at MockTrainer.BAND_LAG_S 2 s: 20 * e^-3.25 < 0.8 rpm.
const LAG_LEFT_RPM := 0.8

var _regs: Array[WlGameRegistry] = []
var _runners: Array[GameSimRunner] = []
var _tmp: String = ""
## Per bot peer: [t, cadence_rpm] for every sim step of the current run.
var _cad: Dictionary = {}


func before_each() -> void:
	_tmp = Paths.make_temp_dir("wattlands_bot_band")
	Paths.set_override(_tmp)


func after_each() -> void:
	for r in _runners:
		if is_instance_valid(r):
			r.cleanup()
			r.free()
	_runners.clear()
	for reg in _regs:
		reg.clear()
		reg.free()
	_regs.clear()
	Paths.set_override("")
	Kit.remove_tree(_tmp)


## The fixture game's sim_step hook: publishes and clears bot 1's band, records both bots.
func _on_step(g: GameModule, frame: InputFrame) -> void:
	if frame.tick == PUBLISH_TICK:
		g.ctx.directives.cadence_band(Bots.peer_id(1), BAND_LO, BAND_HI)
	if frame.tick == CLEAR_TICK:
		g.ctx.directives.cadence_band(Bots.peer_id(1), 0.0, 0.0)
	for peer: int in _cad.keys():
		var tm: Telemetry = frame.players[peer]
		(_cad[peer] as Array).append([frame.tick * Wl.SIM_DT, tm.cadence_rpm])


## One SOLO run of fx_conform "tiny" with one human and two bots, 60 sim seconds.
func _run_bots(rng_seed: int) -> GameSimRunner:
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	reg.content_root = FIXTURES.path_join("_content")
	reg.scan(FIXTURES.path_join("conform"))
	_regs.append(reg)
	var r := GameSimRunner.new()
	_runners.append(r)
	var args := {
		"game": "fx_conform",
		"content": "tiny",
		"registry": reg,
		"seed": rng_seed,
		"players": 1,
		"bots": 2,
		"riders": ["erg"],
		"max_sim_seconds": 60.0,
	}
	assert_eq(r.setup(args), "", "setup")
	_cad = {Bots.peer_id(1): [], Bots.peer_id(2): []}
	r.host.game.set("on_step", _on_step)
	assert_eq(r.run_to_end(), "timeout")
	return r


func _cadences(peer: int, t0: float, t1: float) -> Array[float]:
	var out: Array[float] = []
	for row: Array in _cad[peer]:
		if float(row[0]) >= t0 and float(row[0]) < t1:
			out.append(float(row[1]))
	return out


func test_bots_ride_the_band_tracking_spec() -> void:
	var r := _run_bots(5)
	for n: int in [1, 2]:
		var rider: LocalRider = r.riders[Bots.peer_id(n)]
		assert_true(rider.is_bot)
		assert_true(rider.device is MockTrainer)
		assert_eq((rider.device as MockTrainer).spec, Bots.RIDER_SPEC)
		assert_eq((rider.device as MockTrainer).spec, "erg:compliance=1.0+band")
	assert_eq(r.build_report()["slots"][1]["rider"], Bots.RIDER_SPEC)


func test_a_bot_follows_a_published_band_and_falls_back_when_cleared() -> void:
	_run_bots(5)
	var bot1 := Bots.peer_id(1)
	var publish_s := PUBLISH_TICK * Wl.SIM_DT
	var clear_s := CLEAR_TICK * Wl.SIM_DT
	# The telemetry carries the last ~1 Hz sample, so wait 2 s lag x 3 plus one sample.
	var inside := _cadences(bot1, publish_s + 7.5, clear_s)
	assert_gt(inside.size(), 300)
	for c in inside:
		assert_between(c, BAND_LO, BAND_HI, "bot 1 rides inside the published band")
		assert_almost_eq(c, 110.0, NOISE_RPM + LAG_LEFT_RPM, "the band's centre")
	var back := _cadences(bot1, clear_s + 8.0, 60.0)
	assert_gt(back.size(), 300)
	for c in back:
		assert_almost_eq(c, PREFERRED_RPM, NOISE_RPM, "a cleared band: the preferred cadence")


func test_a_bot_without_a_band_pedals_its_preferred_cadence() -> void:
	_run_bots(5)
	var bot2 := Bots.peer_id(2)
	var rows := _cadences(bot2, 2.0, 60.0)
	assert_gt(rows.size(), 1000)
	for c in rows:
		assert_almost_eq(c, PREFERRED_RPM, NOISE_RPM, "no band: 90 rpm within the noise bound")
	var distinct := {}
	for c in rows:
		distinct[c] = true
	assert_gt(distinct.size(), 1, "the band policy's seeded noise is present")


func test_same_seed_same_bot_cadence_and_hash() -> void:
	var hashes: Array[String] = []
	var cads: Array = []
	for rng_seed: int in [5, 5, 6]:
		var r := _run_bots(rng_seed)
		hashes.append(str(r.build_report()["deterministic_hash"]))
		cads.append(_cad.duplicate(true))
	assert_eq(hashes[0], hashes[1], "same seed, same hash")
	assert_eq(cads[0], cads[1], "same seed, same bot cadences")
	assert_ne(hashes[0], hashes[2], "another seed, another hash")
	assert_ne(cads[0], cads[2], "another seed, other band noise")

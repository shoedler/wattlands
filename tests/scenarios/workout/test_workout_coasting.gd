extends "res://tests/scenarios/lib/scenario_test.gd"
## BRIEF 7.4, coasting (4.6.4): a 0 W rider's applied target reaches the ERG floor
## max(30 % FTP, 50 W) no later than 3 s (plus one 0.05 s tick) after the first sample that meets
## not_pedaling (power < 15 W and cadence < 20 rpm), and the rider is paused (solo) or AFK (with
## others) no later than 10 s (plus one tick) after that sample. Neither happens a tick early.
## Owned by qa; a W2 gate (needs GameSimRunner, Workout, LocalRider and the governor). Riders:
## `zero` (0 W from the start) and `ramp` to 0 W (pedals for 60 s, then stops), on the host's own
## rider, which is SOLO with one human slot and HOST (multiplayer) with two.

const TICK := 0.05
const FLOOR_S := 3.0
const PAUSE_S := 10.0
const STOP_AFTER_PEDALING := "ramp:from_w=130,to_w=0,over_s=60,rpm=85"


## Steps the run until both moments were seen (or 30 s after not_pedaling). Returns
## {first_np, t_floor, t_pause, t_afk, floor_w, ok}.
func _watch(runner: GameSimRunner, rider: LocalRider) -> Dictionary:
	var obs := {
		"first_np": -1.0,
		"t_floor": -1.0,
		"t_pause": -1.0,
		"t_afk": -1.0,
		"floor_w": S.floor_w(rider.slot.ftp if rider.slot != null else S.FTP)
	}
	var mock := S.mock_of(rider)
	mock.sample_received.connect(
		func(s: TrainerSample) -> void:
			if float(obs["first_np"]) < 0.0 and S.is_not_pedaling(s):
				obs["first_np"] = s.t
	)
	var ticks := 0
	while ticks < int(400.0 / TICK):
		runner.step()
		ticks += 1
		var t := S.platform_t(runner, rider)
		var first_np := float(obs["first_np"])
		if first_np < 0.0:
			continue
		var st := rider.governor.status()
		if (
			float(obs["t_floor"]) < 0.0
			and str(st.get("mode", "")) == Wl.ERG
			and int(st.get("applied_target_w", -1)) == int(obs["floor_w"])
			and (bool(st.get("coasting", false)) or S.clamped(st, Wl.CLAMP_COASTING))
		):
			obs["t_floor"] = t
		if (
			float(obs["t_pause"]) < 0.0
			and (runner.host.is_paused() or bool(st.get("paused", false)))
		):
			obs["t_pause"] = t
		if float(obs["t_afk"]) < 0.0 and (bool(st.get("afk", false)) or rider.telemetry().afk):
			obs["t_afk"] = t
		if t > first_np + 30.0:
			break
	return obs


func _assert_timing(label: String, first_np: float, t: float, after_s: float) -> void:
	assert_gte(t, 0.0, "%s happened" % label)
	if t < 0.0:
		return
	var lag := t - first_np
	assert_lte(
		lag,
		after_s + TICK + S.EPS,
		(
			"%s %.3f s after the first not_pedaling sample (limit %.2f s + one tick)"
			% [label, lag, after_s]
		)
	)
	assert_gte(
		lag,
		after_s - TICK - S.EPS,
		"%s not before %.2f s of not_pedaling (it came after %.3f s)" % [label, after_s, lag]
	)


func _coast(players: int, riders: Array[String]) -> Dictionary:
	var extra: Array = ["--players=%d" % players, "--bots=0", "--max-sim-seconds=600"]
	for r in riders:
		extra.append("--rider=%s" % r)
	var runner := start_runner(S.flags("easy_30", report_path("coast"), extra))
	if runner == null:
		return {}
	var rider := human_rider(runner)
	if rider == null:
		return {}
	var obs := _watch(runner, rider)
	obs["runner"] = runner
	assert_gte(float(obs["first_np"]), 0.0, "a sample met not_pedaling")
	return obs


func test_zero_rider_solo_floors_then_pauses() -> void:
	var obs := _coast(1, ["zero"])
	if obs.is_empty():
		return
	_assert_timing("the coasting floor", float(obs["first_np"]), float(obs["t_floor"]), FLOOR_S)
	_assert_timing("the solo pause", float(obs["first_np"]), float(obs["t_pause"]), PAUSE_S)
	assert_lt(float(obs["t_afk"]), 0.0, "a solo rider pauses instead of going AFK")
	var runner: GameSimRunner = obs["runner"]
	assert_eq(runner.run_to_end(), "paused", "a SOLO run that stays paused 120 s ends as paused")


func test_rider_who_stops_pedaling_solo() -> void:
	var obs := _coast(1, [STOP_AFTER_PEDALING])
	if obs.is_empty():
		return
	assert_gte(float(obs["first_np"]), 59.0, "not_pedaling starts once the ramp reaches 0 W")
	_assert_timing("the coasting floor", float(obs["first_np"]), float(obs["t_floor"]), FLOOR_S)
	_assert_timing("the solo pause", float(obs["first_np"]), float(obs["t_pause"]), PAUSE_S)


func test_zero_rider_with_others_floors_then_goes_afk() -> void:
	var obs := _coast(2, ["zero", "erg"])
	if obs.is_empty():
		return
	_assert_timing("the coasting floor", float(obs["first_np"]), float(obs["t_floor"]), FLOOR_S)
	_assert_timing("AFK", float(obs["first_np"]), float(obs["t_afk"]), PAUSE_S)
	var runner: GameSimRunner = obs["runner"]
	assert_false(
		runner.host.is_paused(), "a multiplayer session never pauses for one coasting rider"
	)


func test_rider_who_stops_pedaling_with_others() -> void:
	var obs := _coast(2, [STOP_AFTER_PEDALING, "erg"])
	if obs.is_empty():
		return
	_assert_timing("the coasting floor", float(obs["first_np"]), float(obs["t_floor"]), FLOOR_S)
	_assert_timing("AFK", float(obs["first_np"]), float(obs["t_afk"]), PAUSE_S)

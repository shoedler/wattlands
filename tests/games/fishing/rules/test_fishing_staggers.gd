extends GutTest
## Brief 2.3 "Pauses" and 2.4: a rescue, AFK or dropped client staggers the lane, and the pull
## scheduler hears every start and end of it in any lane state (FishingPullScheduler's API), so
## a stagger that crosses a phase boundary neither silences later Fights nor lets a pull change
## land inside the 10 s after it ended.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")


## free_30 with a mackerel then a 150 s mahi with two runs.
func _two_fights() -> H:
	var probe := H.new()
	probe.content = H.load_content("free_30")
	var lane_slots: Array[FishingPlanSlot] = [
		H.make_slot(probe.content, "mackerel", 0, 80.0),
		H.make_slot(probe.content, "mahi", 1, 150.0, 2),
	]
	var h := H.new()
	h.setup("free_30", 1, 5, [lane_slots])
	h.follow_band[0] = true
	return h


func _threshold(seed: int) -> H:
	var h := H.new()
	h.setup("threshold", 1, seed)
	h.follow_band[0] = true
	return h


## Lane 0's pull steps, run steps and RUN events in (t0, t1].
func _count(h: H, t0: float, t1: float) -> Dictionary:
	var pulls := 0
	var runs := 0
	for d: Array in h.directives:
		var dd: Dictionary = d[2]
		if float(d[0]) > t0 and float(d[0]) <= t1 and dd.has("target_pct"):
			if str(dd["reason"]) == "pull":
				pulls += 1
			else:
				runs += 1
	var run_events := 0
	for k in h.events.size():
		var e: Dictionary = h.events[k]
		if e["type"] == FishingEvents.RUN and h.event_t[k] > t0 and h.event_t[k] <= t1:
			run_events += 1
	return {"pulls": pulls, "run_steps": runs, "run_events": run_events}


func test_the_scheduler_hears_every_stagger_edge_in_any_lane_state() -> void:
	var h := _threshold(1)
	var l := h.lane()
	h.run(100.0)
	assert_eq(l.state, FishingConst.ST_RIDE_OUT)
	h.rescue[0] = true
	h.run(1.0)
	assert_true(l.pull.staggered, "a rescue in the ride out reaches the scheduler")
	h.rescue[0] = false
	h.step()
	var t_end := h.state.t
	assert_false(l.pull.staggered, "and so does its end")
	assert_almost_eq(l.pull.paused_until_t, t_end + 10.0, 1e-6, "the 10 s pull pause starts")
	h.afk[0] = true
	h.run(1.0)
	assert_true(l.pull.staggered, "AFK")
	h.afk[0] = false
	h.connected[0] = false
	h.age_s[0] = 4.0
	h.run(1.0)
	assert_true(l.pull.staggered, "a dropped client keeps it staggered")
	h.connected[0] = true
	h.age_s[0] = 0.0
	h.step()
	assert_false(l.pull.staggered)
	assert_false(l.stagger_on)


## Control: a rescue that ends inside fight 1 leaves fight 2 its pull changes and runs.
func test_a_rescue_that_ends_inside_its_fight_leaves_the_next_fight_intact() -> void:
	var h := _threshold(7)
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 700.0), "fight 1 starts")
	h.rescue[0] = true
	h.run(30.0)
	h.rescue[0] = false
	assert_true(h.run_to_state(0, FishingConst.ST_LANDING, 600.0), "landing 1")
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 600.0), "fight 2 starts")
	var t2 := h.state.t
	h.run(300.0)
	var c := _count(h, t2, h.state.t)
	assert_gt(int(c["pulls"]), 10, "fight 2 sends pull changes: %s" % [c])
	assert_gt(int(c["run_events"]), 0, "fight 2 has runs: %s" % [c])


## A rescue from fight 1's start (S frozen, so it runs to max_s) released in the Landing.
func test_a_rescue_that_outlives_its_fight_does_not_silence_the_next_fight() -> void:
	var h := _threshold(7)
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 700.0), "fight 1 starts")
	h.rescue[0] = true
	assert_true(h.run_to_state(0, FishingConst.ST_LANDING, 600.0), "fight 1 ends at max_s")
	h.rescue[0] = false
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 600.0), "fight 2 starts")
	var t2 := h.state.t
	h.run(300.0)
	var c := _count(h, t2, h.state.t)
	assert_false(h.lane().pull.staggered, "the pull scheduler is not staggered in fight 2")
	assert_gt(int(c["pulls"]), 10, "fight 2 sends pull changes: %s" % [c])
	assert_gt(int(c["run_events"]), 0, "fight 2 has runs: %s" % [c])
	assert_eq(h.lane().pull.runs_skipped, 0, "no run of fight 2 is refused")


## An AFK (a dropped client) from fight 1 into its Landing: fight 2's mahi still pulls and runs.
func test_an_afk_that_outlives_its_fight_does_not_mute_the_next_fight() -> void:
	var h := _two_fights()
	var l := h.lane()
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 1200.0), "fight 1 starts")
	h.afk[0] = true
	assert_true(h.run_to_state(0, FishingConst.ST_LANDING, 200.0), "fight 1 ends at max_s")
	h.afk[0] = false
	h.run(20.0)
	assert_false(l.staggered, "the lane itself has resumed")
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 1200.0), "fight 2 starts")
	var t0 := h.state.t
	var dirs_before := h.directives.size()
	h.run_until(func() -> bool: return l.state != FishingConst.ST_FIGHT, 300.0)
	assert_false(l.pull.staggered, "the pull scheduler does not stay staggered into fight 2")
	assert_gt(h.directives.size() - dirs_before, 0, "fight 2 from t=%.0f sends pulls" % t0)
	assert_eq(h.events_of(FishingEvents.RUN).size(), 2, "fight 2's two mahi runs fire")


## A Threshold rider in rescue late in tuna 1, released 3 s into the Landing.
func test_a_rescue_released_in_the_landing_leaves_the_next_tuna_its_pulls_and_runs() -> void:
	var h := _threshold(3)
	var l := h.lane()
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 700.0), "tuna 1 starts")
	h.run(320.0)
	assert_eq(l.state, FishingConst.ST_FIGHT, "still fighting tuna 1")
	h.rescue[0] = true
	assert_true(h.run_to_state(0, FishingConst.ST_LANDING, 100.0), "tuna 1 lands")
	h.run(3.0)
	h.rescue[0] = false
	assert_true(h.run_to_state(0, FishingConst.ST_FIGHT, 600.0), "tuna 2 starts")
	var n0 := h.directives.size()
	var runs0 := h.events_of(FishingEvents.RUN).size()
	h.run(150.0)
	assert_false(l.pull.staggered, "scheduler not staggered in tuna 2")
	assert_gt(h.directives.size() - n0, 0, "tuna 2 sends pull changes")
	assert_gt(h.events_of(FishingEvents.RUN).size() - runs0, 0, "tuna 2's runs fire")


## Brief 2.3 Pauses: the pull-change clock stays stopped until 10 s after a rescue that ended in
## the Reel just before Threshold's fixed Fight (Reel 1 ends at 540 s), on every seed.
func test_no_request_within_10_s_of_a_rescue_that_ended_just_before_the_fight() -> void:
	var bad: Array[String] = []
	var cases: Array = []
	for seed in range(1, 41):
		cases.append([seed, 530.0, 9.0])
	for seed: int in [2, 7]:
		cases.append([seed, 535.0, 4.95])
	for c: Array in cases:
		var h := _threshold(int(c[0]))
		h.run(float(c[1]))
		h.rescue[0] = true
		h.run(float(c[2]))
		h.rescue[0] = false
		var cause_end := h.state.t
		h.run(12.0)
		assert_eq(h.lane().state, FishingConst.ST_FIGHT, "seed %d: the Fight started" % c[0])
		for d: Array in h.directives:
			var t := float(d[0])
			if t > cause_end and t < cause_end + 10.0 - 1e-6:
				bad.append("seed %d: request %.2f s after the rescue" % [c[0], t - cause_end])
				break
	assert_eq(bad, [] as Array[String], "no request inside the 10 s after a rescue")

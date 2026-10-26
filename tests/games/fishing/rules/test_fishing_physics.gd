extends GutTest
## The boat physics inside the rules: a hooked fish tows the boat (tension from size, stamina,
## strain, runs and slack), big-fish surges request an ERG haptic_pull and raise F_SURGE, the
## reel-in progress follows the line, and the snapshot carries heave, planing, tow, prop depth
## and reel-in.

const H := preload("res://tests/games/fishing/rules/fishing_rules_harness.gd")
const S := preload("res://src/games/fishing/contracts/fishing_snapshot_schema.gd")


func _fight(species: String, runs: int, kg: float = -1.0) -> H:
	var probe := H.new()
	probe.content = H.load_content("base_60")
	var one: Array[FishingPlanSlot] = [H.make_slot(probe.content, species, 0, 220.0, runs, kg)]
	var h := H.new()
	h.setup("base_60", 1, 5, [one])
	h.follow_band[0] = true
	assert_true(h.run_to_action(0, FishingConst.A_FIGHT, 1200.0), "the fight starts")
	return h


func _pulls(h: H) -> Array:
	var out := []
	for d: Array in h.directives:
		if (d[2] as Dictionary).has("haptic_pull"):
			out.append(d)
	return out


## Steps until the first run starts; returns its time (-1 none within max_s).
func _to_first_run(h: H, max_s: float) -> float:
	var l := h.rider()
	var t_end := h.state.t + max_s
	while l.action == FishingConst.A_FIGHT and h.state.t < t_end:
		h.step()
		if l.fish.run_active:
			return h.state.t
	return -1.0


func test_a_big_fish_run_requests_a_haptic_pull_and_shows_the_surge() -> void:
	var h := _fight("tuna", 3, 60.0)
	var l := h.rider()
	assert_eq(_pulls(h).size(), 0, "no pull before the run")
	var t := _to_first_run(h, 600.0)
	assert_gt(t, 0.0, "the tuna runs")
	var pulls := _pulls(h)
	assert_eq(pulls.size(), 1, "one pull as the run starts")
	var d: Dictionary = pulls[0][2]
	assert_eq(int(pulls[0][1]), h.players[0].peer_id)
	assert_eq(float(d["haptic_pull"]), FishingConst.SURGE_PULL_PCT, "+50 % FTP")
	assert_eq(float(d["duration_s"]), FishingConst.SURGE_S, "for 2 s")
	assert_eq(str(d["source"]), "fishing")
	assert_false(d.has("target_pct") or d.has("mode"), "a pull only: no target, no mode")
	var dir := EffortDirective.from_dict(d)
	assert_eq(dir.haptic_pull, FishingConst.SURGE_PULL_PCT, "a valid EffortDirective field")
	assert_lte(dir.haptic_pull, 50.0, "within the governor's +50 % FTP bound")
	assert_true(l.surging)
	var row: Array = FishingSnapshot.encode(h.state)["R"][0]
	assert_true(int(row[S.R_FLAGS]) & S.F_SURGE != 0, "F_SURGE on")
	var size := sqrt(60.0 / 200.0)
	assert_almost_eq(l.tow_n, FishingConst.TOW_MAX_N * size, 1e-3, "the line snaps taut")
	h.run(FishingConst.SURGE_S + 0.1)
	assert_false(l.surging, "the surge lasts 2 s")
	row = FishingSnapshot.encode(h.state)["R"][0]
	assert_eq(int(row[S.R_FLAGS]) & S.F_SURGE, 0)
	assert_lt(l.tow_n, FishingConst.TOW_MAX_N * size, "back to the run's pull")


func test_every_big_run_surges_at_most_once_per_gap() -> void:
	var h := _fight("tuna", 3, 60.0)
	var l := h.rider()
	while l.action == FishingConst.A_FIGHT and h.state.t < 3000.0:
		h.step()
	var pulls := _pulls(h)
	var runs := h.events_of(FishingEvents.RUN)
	assert_gt(runs.size(), 0)
	assert_eq(pulls.size(), runs.size(), "one pull per run")
	for k in range(1, pulls.size()):
		var gap := float(pulls[k][0]) - float(pulls[k - 1][0])
		assert_gte(gap, FishingConst.SURGE_GAP_S - 1e-6, "spaced by the governor's 15 s")


func test_small_fish_and_riders_without_haptics_get_no_pull() -> void:
	var h := _fight("mahi", 2, 12.0)
	assert_gt(_to_first_run(h, 600.0), 0.0, "the mahi runs")
	assert_false(h.rider().surging, "12 kg: no surge")
	assert_eq(_pulls(h).size(), 0)
	var off := _fight("tuna", 3, 60.0)
	off.rider().haptics_on = false
	assert_gt(_to_first_run(off, 600.0), 0.0)
	assert_true(off.rider().surging, "the cue still shows")
	assert_eq(_pulls(off).size(), 0, "opted out: no pull")


func test_the_fish_tows_the_boat_toward_it_during_the_fight() -> void:
	var h := _fight("tuna", 0, 60.0)
	var l := h.rider()
	h.run(2.0)
	var x0 := l.x_m
	var top_v := 0.0
	var top_tow := 0.0
	for i in 600:
		h.step()
		top_v = maxf(top_v, absf(l.v_mps))
		top_tow = maxf(top_tow, l.tow_n)
	gut.p("towed %.1f m in 30 s, top %.2f m/s, tension up to %.0f N" % [x0 - l.x_m, top_v, top_tow])
	assert_gt(top_tow, 0.0)
	assert_lte(top_tow, FishingConst.TOW_MAX_N)
	assert_lt(l.x_m, x0, "toward the fish behind the stern")
	assert_lt(top_v, 1.5, "slowly")
	assert_gt(l.prop_depth_m, FishingConst.PROP_REST_M, "the stern pulled down")
	l.fish.off_line = true
	l.fish.replace_at_t = h.state.t + FishingConst.REPLACEMENT_DELAY_S
	h.step()
	assert_eq(l.tow_n, 0.0, "no fish on the line, no tension")


func test_reel_in_progress_follows_the_line_to_the_boat() -> void:
	var h := _fight("tuna", 0, 60.0)
	var l := h.rider()
	var lo := 1.0
	var hi := 0.0
	while l.action == FishingConst.A_FIGHT and h.state.t < 3000.0:
		h.step()
		var full := Vector2(maxf(l.fish.d_max, l.fish.d), l.fish.hook_depth_m).length()
		assert_almost_eq(l.reel, 1.0 - l.line_m() / full, 1e-6)
		lo = minf(lo, l.reel)
		hi = maxf(hi, l.reel)
	assert_eq(l.action, FishingConst.A_LAND, "fought to the landing")
	gut.p("reel-in over the fight: %.2f .. %.2f" % [lo, hi])
	assert_gt(hi, 0.7, "near the boat at the end of the fight")
	var row: Array = FishingSnapshot.encode(h.state)["R"][0]
	assert_eq(int(row[S.R_REEL]), S.u8(l.reel), "R_REEL")
	assert_eq(int(row[S.R_LINE_DM]), roundi(l.line_m() * 10.0), "the distance number")
	while l.action == FishingConst.A_LAND and h.state.t < 3000.0:
		h.step()
		if l.fish.d <= 0.0 and l.fish.z <= 0.0:
			break
	assert_almost_eq(l.reel, 1.0, 1e-6, "aboard: all reeled in")
	assert_eq(l.tow_n, 0.0)


func test_the_snapshot_carries_the_hull_and_a_client_gets_it_back() -> void:
	var h := H.new()
	h.setup("roam_30", 1, 3)
	h.drive_w[0] = 300.0
	h.run(30.0)
	var l := h.rider()
	assert_true(l.planing, "300 W planes in the drive-out")
	var snap := FishingSnapshot.encode(h.state)
	var row: Array = snap["R"][0]
	assert_eq(row.size(), S.R_COLUMNS)
	assert_eq(int(row[S.R_HEAVE_CM]), roundi(l.heave_m * 100.0))
	assert_eq(int(row[S.R_PLANE]), 255)
	assert_eq(int(row[S.R_TOW]), 0)
	assert_eq(int(row[S.R_PROP_CM]), roundi(l.prop_depth_m * 100.0))
	assert_gte(int(row[S.R_PROP_CM]), roundi(FishingConst.PROP_MIN_M * 100.0))
	assert_eq(int(row[S.R_REEL]), 0, "no fish on")
	var other := H.new()
	other.setup("roam_30", 1, 3)
	var c := other.rider()
	FishingSnapshot.apply(other.state, JSON.parse_string(JSON.stringify(snap)))
	assert_almost_eq(c.heave_m, l.heave_m, 0.006)
	assert_almost_eq(c.plane, 1.0, 1e-6)
	assert_true(c.planing)
	assert_almost_eq(c.prop_depth_m, l.prop_depth_m, 0.006)
	assert_eq(c.tow_n, 0.0)
	assert_eq(c.reel, 0.0)

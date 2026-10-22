extends GutTest
## SiegePlanBuilder (brief 2.3, 4): every content at FTP 80, 200 and 400, verified or not, at
## wave offsets -10, 0 and +5 passes the PlanValidator with no errors and no warnings, with
## exactly the brief's phases, totals and BRIEF 4.6 checks; offsets clamp; bots ride 0.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const CONTENTS: Array[String] = ["short", "vo2", "sweetspot", "endurance", "drill"]
## Minutes with the 180 s cool-down (drill: 120 s + 180 s).
const TOTAL_MIN := {"short": 31.0, "vo2": 37.0, "sweetspot": 45.0, "endurance": 55.0, "drill": 5.0}
## Waves (count, seconds, target at offset 0) and breaks (count, seconds, target).
const WAVES := {
	"short": [3, 300.0, 95.0],
	"vo2": [6, 120.0, 112.0],
	"sweetspot": [2, 900.0, 90.0],
	"endurance": [1, 2700.0, 70.0],
	"drill": [1, 100.0, 60.0],
}
const BREAKS := {
	"short": [2, 180.0, 50.0],
	"vo2": [5, 180.0, 50.0],
	"sweetspot": [1, 300.0, 55.0],
	"endurance": [0, 0.0, 0.0],
	"drill": [0, 0.0, 0.0],
}
## FIT laps per run: every lap-true phase + 1 for the appended cool-down.
const FIT_LAPS := {"short": 8, "vo2": 14, "sweetspot": 6, "endurance": 4, "drill": 3}

var _content: SiegeContent


func before_all() -> void:
	_content = F.content("short")


func _shift(id: String) -> Dictionary:
	return _content.shifts[id]


func _slot(ftp: float, verified: bool, offset: Variant, bot: bool = false) -> PlayerSlot:
	var s := PlayerSlot.new()
	s.peer_id = -1 if bot else 1
	s.is_bot = bot
	s.ftp = ftp
	s.ftp_verified = verified
	s.options = {"wave_offset": offset}
	return s


func _expected_wave_pct(id: String, offset: int) -> float:
	var w: Array = WAVES[id]
	if id == "drill":
		return float(w[2])
	var cap := 105.0 if float(w[1]) > 240.0 else 117.0
	return minf(float(w[2]) + offset, cap)


func test_the_shift_content_validates() -> void:
	assert_eq(SiegeContent.validate_shifts(_content.shifts), [] as Array[String])
	for id in CONTENTS:
		assert_true(_content.shifts.has(id), id)
	assert_eq(_content.shifts.keys().size(), CONTENTS.size(), "no other shifts")


func test_every_plan_passes_the_validator_without_warnings_at_every_ftp_and_offset() -> void:
	var checked := 0
	for id in CONTENTS:
		for ftp: float in [80.0, 200.0, 400.0]:
			for verified: bool in [true, false]:
				for offset: int in [-10, 0, 5]:
					var plan := SiegePlanBuilder.build(_shift(id), _slot(ftp, verified, offset), id)
					var v := PlanValidator.validate(plan)
					var at := (
						"%s ftp %d %s offset %d"
						% [id, ftp, "verified" if verified else "unverified", offset]
					)
					assert_true(v["ok"], "%s: %s" % [at, v["errors"]])
					assert_eq(v["errors"], [], at)
					assert_eq(v["warnings"], [], at)
					var fin := PlanValidator.finalize(plan)
					assert_not_null(fin, at)
					if fin != null:
						assert_almost_eq(
							fin.nominal_length_s() / 60.0, float(TOTAL_MIN[id]), 1e-6, at + " total"
						)
					checked += 1
	assert_eq(checked, 5 * 3 * 2 * 3)


func test_exact_phases_of_every_content() -> void:
	for id in CONTENTS:
		for offset: int in [-10, 0, 5]:
			var plan := SiegePlanBuilder.build(_shift(id), _slot(200, true, offset), id)
			var w: Array = WAVES[id]
			var b: Array = BREAKS[id]
			var waves := 0
			var breaks := 0
			var at := "%s %d" % [id, offset]
			for i in plan.size():
				var ph := plan.phase(i)
				assert_eq(ph.mode, Wl.ERG, at)
				assert_true(ph.lap, "%s phase %d laps" % [at, i])
				assert_eq(ph.range_pct, [], "%s phase %d has no range_pct" % [at, i])
				assert_false(ph.open_ended, at)
				var role := str(ph.meta.get("role", ""))
				match role:
					SiegeIds.ROLE_WARMUP_WAVE:
						assert_eq(i, 0, at)
						assert_eq(
							[ph.kind, ph.target_pct, ph.ramp_to_pct, ph.duration_s],
							[Wl.WARMUP, 50.0, 65.0, 300.0],
							at
						)
						assert_eq(ph.label, "SIEGE_PHASE_WARMUP_WAVE")
						assert_eq(int(ph.meta["number"]), 0)
					SiegeIds.ROLE_BUILD_BREAK:
						var dur := 20.0 if id == "drill" else 120.0
						var kind := Wl.WARMUP if id == "drill" else Wl.RECOVERY
						assert_eq([ph.kind, ph.target_pct, ph.duration_s], [kind, 50.0, dur], at)
						assert_eq(ph.label, "SIEGE_PHASE_BUILD_BREAK")
					SiegeIds.ROLE_WAVE:
						waves += 1
						assert_eq(ph.kind, Wl.WARMUP if id == "drill" else Wl.WORK, at)
						assert_eq(ph.duration_s, float(w[1]), at)
						assert_eq(ph.target_pct, _expected_wave_pct(id, offset), at)
						assert_eq(ph.label, "SIEGE_PHASE_WAVE_%d" % waves)
						assert_eq(int(ph.meta["number"]), waves)
						assert_eq(bool(ph.meta["last_wave"]), waves == int(w[0]), at)
						assert_false(ph.has_ramp(), at)
					SiegeIds.ROLE_BREAK:
						breaks += 1
						assert_eq(
							[ph.kind, ph.target_pct, ph.duration_s],
							[Wl.RECOVERY, float(b[2]), float(b[1])],
							at
						)
						assert_eq(ph.label, "SIEGE_PHASE_BREAK_%d" % breaks)
						assert_eq(int(ph.meta["number"]), breaks, "break n follows wave n")
					_:
						fail_test("%s phase %d: unknown role %s" % [at, i, role])
				assert_eq(int(ph.meta["waves"]), int(w[0]), at)
				assert_eq(str(ph.meta["shift"]), id, at)
			assert_eq(waves, int(w[0]), at + " waves")
			assert_eq(breaks, int(b[0]), at + " breaks")


func test_the_first_300_s_are_erg_at_most_65_pct_and_waves_start_at_420_s() -> void:
	for id in CONTENTS:
		var plan := SiegePlanBuilder.build(_shift(id), _slot(200, true, 5), id)
		var t := 0.0
		for i in plan.size():
			var ph := plan.phase(i)
			if t < 300.0:
				assert_eq(ph.mode, Wl.ERG, id)
				assert_lte(ph.peak_pct(), 65.0, "%s phase %d starts at %d s" % [id, i, t])
			if ph.kind == Wl.WORK:
				assert_gte(t, 420.0, "%s: WORK phases start at >= 420 s" % id)
			t += ph.duration_s


func test_bounds_of_every_target_at_every_offset() -> void:
	for id in CONTENTS:
		for offset: int in [-10, 0, 5]:
			var plan := SiegePlanBuilder.build(_shift(id), _slot(200, true, offset), id)
			for i in plan.size():
				var ph := plan.phase(i)
				assert_between(ph.target_pct, 50.0, 117.0, "%s %d phase %d" % [id, offset, i])
				if ph.duration_s > 300.0:
					assert_lte(ph.peak_pct(), 95.0, "%s: phases over 300 s stay <= 95%%" % id)
				if str(ph.meta["role"]) == SiegeIds.ROLE_WAVE:
					assert_gte(
						ph.target_pct,
						60.0,
						"%s %d: every wave >= 60%% (rescue armed)" % [id, offset]
					)
			if id == "short":
				assert_lte(plan.phase(2).target_pct, 100.0, "short <= 100% at every offset")
			if id == "endurance":
				assert_lte(plan.phase(2).target_pct, 75.0, "endurance <= 75%")


func test_vo2_offsets_clamp_at_117_and_its_breaks_reset_the_duration_limits() -> void:
	var plus := SiegePlanBuilder.build(_shift("vo2"), _slot(200, true, 5), "vo2")
	var minus := SiegePlanBuilder.build(_shift("vo2"), _slot(200, true, -10), "vo2")
	assert_eq(plus.phase(2).target_pct, 117.0)
	assert_eq(minus.phase(2).target_pct, 102.0)
	for i in plus.size():
		var ph := plus.phase(i)
		if ph.kind == Wl.RECOVERY and i > 1:
			assert_gte(ph.duration_s, 120.0, "a break >= 120 s ...")
			assert_lte(ph.target_pct, 90.0, "... at <= 90% resets both counters")
		if ph.target_pct > 105.0:
			assert_lte(ph.duration_s, 120.0, "above 105% for at most 120 s per wave")


func test_the_drill_is_two_warmup_phases_with_no_offset() -> void:
	for offset: int in [-10, 0, 5]:
		var plan := SiegePlanBuilder.build(_shift("drill"), _slot(200, true, offset), "drill")
		assert_eq(plan.size(), 2)
		assert_eq(
			[plan.phase(0).kind, plan.phase(0).target_pct, plan.phase(0).duration_s],
			[Wl.WARMUP, 50.0, 20.0]
		)
		assert_eq(
			[plan.phase(1).kind, plan.phase(1).target_pct, plan.phase(1).duration_s],
			[Wl.WARMUP, 60.0, 100.0]
		)
		assert_eq(str(plan.phase(0).meta["role"]), SiegeIds.ROLE_BUILD_BREAK)
		assert_eq(str(plan.phase(1).meta["role"]), SiegeIds.ROLE_WAVE)
		assert_eq(int(plan.phase(1).meta["number"]), 1, "the drill's wave counts as wave 1")
		assert_eq(str(plan.phase(1).meta["mix"]), SiegeIds.MIX_RAIDERS_HORSEMEN)
		assert_true(bool(plan.phase(1).meta["last_wave"]))


func test_endurance_carries_its_rush_times() -> void:
	var plan := SiegePlanBuilder.build(_shift("endurance"), _slot(200, true, 0), "endurance")
	assert_eq(plan.phase(2).meta["rushes_at_s"], [480.0, 960.0, 1440.0, 1920.0, 2400.0])
	for i in plan.size():
		if i != 2:
			assert_false(plan.phase(i).meta.has("rushes_at_s"))


func test_offset_comes_from_player_options_clamped_and_bots_ride_zero() -> void:
	assert_eq(SiegePlanBuilder.offset_of(_slot(200, true, 0)), 0)
	assert_eq(SiegePlanBuilder.offset_of(_slot(200, true, -10)), -10)
	assert_eq(SiegePlanBuilder.offset_of(_slot(200, true, 5)), 5)
	assert_eq(SiegePlanBuilder.offset_of(_slot(200, true, 9)), 5)
	assert_eq(SiegePlanBuilder.offset_of(_slot(200, true, -25)), -10)
	assert_eq(SiegePlanBuilder.offset_of(_slot(200, true, 3.0)), 3, "a JSON float")
	assert_eq(SiegePlanBuilder.offset_of(_slot(200, true, "5")), 0, "not a number")
	assert_eq(SiegePlanBuilder.offset_of(_slot(200, true, 5, true)), 0, "bots ride 0")
	var none := PlayerSlot.new()
	assert_eq(SiegePlanBuilder.offset_of(none), 0, "missing option")
	var bot_plan := SiegePlanBuilder.build(_shift("short"), _slot(200, true, 5, true), "short")
	assert_eq(bot_plan.phase(2).target_pct, 95.0, "a bot's wave has no offset")


func test_custom_wave_clamps_from_the_brief() -> void:
	assert_eq(
		SiegePlanBuilder.wave_target(105.0, 300.0, 5), 105.0, "300 s at 105% +5 builds at 105"
	)
	assert_eq(
		SiegePlanBuilder.wave_target(115.0, 240.0, 5), 117.0, "240 s at 115% +5 builds at 117"
	)
	assert_eq(SiegePlanBuilder.wave_target(112.0, 241.0, 5), 105.0, "over 240 s: 105")
	assert_eq(SiegePlanBuilder.wave_target(60.0, 600.0, -10), 50.0, "never below 50")
	assert_eq(SiegePlanBuilder.wave_target(95.0, 300.0, -10), 85.0)


func test_every_slot_shares_the_phase_boundaries() -> void:
	var slots := F.make_slots(3, 1)
	slots[0].options["wave_offset"] = 5
	slots[1].options["wave_offset"] = -10
	var plans := SiegePlanBuilder.build_all(_shift("vo2"), slots, "vo2")
	assert_eq(plans.size(), 4)
	var ref: EffortPlan = plans[slots[2].peer_id]
	for p in slots:
		var plan: EffortPlan = plans[p.peer_id]
		assert_eq(plan.size(), ref.size())
		for i in plan.size():
			assert_eq(plan.phase(i).duration_s, ref.phase(i).duration_s)
			assert_eq(plan.phase(i).kind, ref.phase(i).kind)
			assert_eq(plan.phase(i).meta, ref.phase(i).meta)
	assert_eq((plans[1] as EffortPlan).phase(2).target_pct, 117.0)
	assert_eq((plans[2] as EffortPlan).phase(2).target_pct, 102.0)
	assert_eq((plans[-1] as EffortPlan).phase(2).target_pct, 112.0)


func test_fit_laps_per_content() -> void:
	for id in CONTENTS:
		var fin := PlanValidator.finalize(
			SiegePlanBuilder.build(_shift(id), _slot(200, true, 0), id)
		)
		var laps := 0
		for i in fin.size():
			laps += int(fin.phase(i).lap)
		assert_eq(laps, int(FIT_LAPS[id]), "%s: lap-true phases + the cool-down" % id)


func test_role_of_and_mean_pct() -> void:
	var plan := SiegePlanBuilder.build(_shift("short"), _slot(200, true, 0), "short")
	assert_eq(str(SiegePlanBuilder.role_of(plan, 0)["role"]), SiegeIds.ROLE_WARMUP_WAVE)
	assert_eq(str(SiegePlanBuilder.role_of(plan, plan.size())["role"]), SiegeIds.ROLE_COOLDOWN)
	assert_eq(
		str(SiegePlanBuilder.role_of(F.with_cooldown(plan), plan.size())["role"]),
		SiegeIds.ROLE_COOLDOWN
	)
	assert_eq(str(SiegePlanBuilder.role_of(null, 0)["role"]), SiegeIds.ROLE_NONE)
	assert_eq(str(SiegePlanBuilder.role_of(plan, -1)["role"]), SiegeIds.ROLE_NONE)
	assert_eq(SiegePlanBuilder.mean_pct(plan.phase(0)), 57.5, "the warm-up wave's mean target")
	assert_eq(SiegePlanBuilder.mean_pct(plan.phase(2)), 95.0)
	assert_eq(SiegePlanBuilder.wave_count(_shift("vo2")), 6)
	assert_eq(SiegePlanBuilder.total_s(_shift("short")), 1680.0)


func test_every_phase_label_is_a_string_key() -> void:
	var keys := {}
	var f := FileAccess.open(F.CONTENT_DIR.path_join("strings.csv"), FileAccess.READ)
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2:
			keys[row[0]] = true
	for id in CONTENTS:
		var plan := SiegePlanBuilder.build(_shift(id), _slot(200, true, 0), id)
		for i in plan.size():
			assert_true(keys.has(plan.phase(i).label), plan.phase(i).label)
	for n in range(1, SiegePlanBuilder.MAX_LABEL_N + 1):
		assert_true(keys.has(SiegePlanBuilder.label_for(SiegeIds.ROLE_WAVE, n)))
		assert_true(keys.has(SiegePlanBuilder.label_for(SiegeIds.ROLE_BREAK, n)))

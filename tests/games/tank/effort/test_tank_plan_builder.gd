extends GutTest
## TankPlanBuilder against brief 2.2, 2.3 and 2.9 (and BRIEF 4.5, 4.6; the v3 effort table): every
## crew 1-4 x FTP {80, 200, 400} x verified / unverified, plus the drill. v3: one tank, every slot
## on its start seat for the whole plan (rotation is gone; seat switches replan, TankSeatPlan). The
## expected tables are written out from the brief here, never read back from stations.json, so a
## content edit that leaves the brief fails these tests.

## Brief 2.3 segment table: [type, kind, duration_s, min_s, max_s, stage].
const ASHFALL := [
	["depot", Wl.WARMUP, 300.0, 0.0, 0.0, 0],
	["advance", Wl.WORK, 180.0, 90.0, 300.0, 1],
	["gun_line", Wl.WORK, 120.0, 60.0, 180.0, 1],
	["checkpoint", Wl.RECOVERY, 60.0, 0.0, 0.0, 1],
	["advance", Wl.WORK, 180.0, 90.0, 300.0, 2],
	["gun_line", Wl.WORK, 120.0, 60.0, 180.0, 2],
	["checkpoint", Wl.RECOVERY, 60.0, 0.0, 0.0, 2],
	["advance", Wl.WORK, 180.0, 90.0, 300.0, 3],
	["gun_line", Wl.WORK, 120.0, 60.0, 180.0, 3],
	["checkpoint", Wl.RECOVERY, 60.0, 0.0, 0.0, 3],
	["boss", Wl.WORK, 240.0, 120.0, 360.0, 4],
]
## Brief 2.9.
const DRILL := [
	["depot", Wl.WARMUP, 30.0, 0.0, 0.0, 0],
	["skirmish", Wl.WARMUP, 70.0, 0.0, 0.0, 1],
	["checkpoint", Wl.RECOVERY, 30.0, 0.0, 0.0, 1],
]
## Brief 2.3 engine table: engine -> segment type -> [mode, target_pct, ramp_to_pct, range_pct,
## grade_source] (null where not set).
const ENGINE_TABLE := {
	"diesel":
	{
		"depot": ["SIM", null, null, null, "game"],
		"advance": ["SIM", null, null, null, "game"],
		"gun_line": ["SIM", null, null, null, "flat"],
		"boss": ["SIM", null, null, null, "flat"],
	},
	"dynamo":
	{
		"depot": ["ERG", 50.0, 65.0, null, null],
		"advance": ["ERG", 55.0, null, [55.0, 100.0], null],
		"gun_line": ["ERG", 55.0, null, [55.0, 100.0], null],
		"boss": ["ERG", 55.0, null, [55.0, 100.0], null],
	},
	"steam":
	{
		"depot": ["SIM", null, null, null, "flat"],
		"advance": ["SIM", null, null, null, "flat"],
		"gun_line": ["SIM", null, null, null, "flat"],
		"boss": ["SIM", null, null, null, "flat"],
	},
	"arc":
	{
		"depot": ["ERG", 50.0, 65.0, null, null],
		"advance": ["ERG", 65.0, null, [65.0, 80.0], null],
		"gun_line": ["ERG", 65.0, null, [65.0, 80.0], null],
		"boss": ["ERG", 65.0, null, [65.0, 80.0], null],
	},
	"feed":
	{
		"depot": ["SIM", null, null, null, "flat"],
		"advance": ["SIM", null, null, null, "flat"],
		"gun_line": ["SIM", null, null, null, "flat"],
		"boss": ["SIM", null, null, null, "flat"],
	},
}
## Brief 2.9 drill table.
const DRILL_TABLE := {
	"diesel":
	{
		"depot": ["SIM", null, null, null, "game"],
		"skirmish": ["SIM", null, null, null, "game"],
	},
	"dynamo":
	{
		"depot": ["ERG", 50.0, null, null, null],
		"skirmish": ["ERG", 55.0, null, [55.0, 65.0], null],
	},
	"steam":
	{
		"depot": ["SIM", null, null, null, "flat"],
		"skirmish": ["SIM", null, null, null, "flat"],
	},
	"arc":
	{
		"depot": ["ERG", 50.0, null, null, null],
		"skirmish": ["ERG", 55.0, null, [55.0, 65.0], null],
	},
	"feed":
	{
		"depot": ["SIM", null, null, null, "flat"],
		"skirmish": ["SIM", null, null, null, "flat"],
	},
}
## Checkpoints: ERG 50% for everyone.
const CHECKPOINT := ["ERG", 50.0, null, null, null]
## v3: the start seat of each slot (Drive, Gun, Loader, Lights); a crew of n takes the first n.
const START := {
	1: ["diesel"],
	2: ["diesel", "dynamo"],
	3: ["diesel", "dynamo", "steam"],
	4: ["diesel", "dynamo", "steam", "arc"],
}
const FTPS := [80.0, 200.0, 400.0]


func _slots(crew: int, ftp: float, verified: bool) -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for i in crew:
		var s := PlayerSlot.new()
		s.peer_id = i + 1
		s.slot_index = i
		s.ftp = ftp
		s.ftp_verified = verified
		out.append(s)
	return out


func _content(mission: String = "ashfall_road") -> TankContent:
	return TankFixtures.content(mission)


## Every (crew, ftp, verified) case of the brief's matrix, plus the content id ([mission, crew,
## ftp, verified]).
func _matrix() -> Array:
	var out: Array = []
	for mission: String in ["ashfall_road", "drill"]:
		for crew in [1, 2, 3, 4]:
			for ftp: float in FTPS:
				for verified in [true, false]:
					out.append([mission, crew, ftp, verified])
	return out


func _build(case: Array) -> Dictionary:
	var c := _content(str(case[0]))
	return TankPlanBuilder.build_all(c, _slots(int(case[1]), float(case[2]), bool(case[3])))


func _at(case: Array, peer: int) -> String:
	return (
		"%s crew %d FTP %d %s peer %d"
		% [case[0], case[1], case[2], "verified" if case[3] else "unverified", peer]
	)


# --- Validator, shape and tables -----------------------------------------------------------------


func test_every_plan_validates_with_no_warning() -> void:
	for case: Array in _matrix():
		var plans := _build(case)
		assert_eq(plans.size(), int(case[1]))
		for peer: int in plans:
			var v := PlanValidator.validate(plans[peer])
			assert_true(v["ok"], "%s: %s" % [_at(case, peer), v["errors"]])
			assert_eq(v["warnings"], [], _at(case, peer))
			var final := PlanValidator.finalize(plans[peer])
			assert_not_null(final, _at(case, peer))
			if final != null:
				assert_eq(final.phase(final.size() - 1).kind, Wl.COOLDOWN, _at(case, peer))


## Every phase: kind, duration, open-ended min / max, lap true, the mission's label, the meta, and
## every boundary shared by the whole crew.
func test_segments_kinds_lengths_labels_meta_and_shared_boundaries() -> void:
	for case: Array in _matrix():
		var mission := str(case[0])
		var want: Array = ASHFALL if mission == "ashfall_road" else DRILL
		var c := _content(mission)
		var plans := _build(case)
		for peer: int in plans:
			var plan: EffortPlan = plans[peer]
			assert_eq(plan.size(), want.size(), _at(case, peer))
			for i in want.size():
				var w: Array = want[i]
				var ph := plan.phase(i)
				var at := "%s phase %d" % [_at(case, peer), i]
				assert_eq([ph.kind, ph.duration_s, ph.lap], [w[1], w[2], true], at)
				assert_eq(ph.open_ended, float(w[3]) > 0.0, at)
				assert_eq([ph.min_s, ph.max_s], [w[3], w[4]], at)
				assert_eq(ph.label, str(c.segment(i)["label"]), at)
				assert_true(ph.label.begins_with("TANK_PHASE_"), at)
				assert_eq(str(ph.meta["seg"]), str(w[0]), at)
				assert_eq(int(ph.meta["stage"]), int(w[5]), at)
				assert_eq(int(ph.meta["segment"]), i, at)
				assert_eq(str(ph.meta["mission"]), mission, at)
				assert_has(TankIds.ENGINES, str(ph.meta["engine"]), at)
				# Shared boundaries: the same kind, lengths and segment for every rider.
				var p0: EffortPlan = plans[1]
				var q := p0.phase(i)
				assert_eq(
					[ph.kind, ph.duration_s, ph.open_ended, ph.min_s, ph.max_s, ph.meta["seg"]],
					[q.kind, q.duration_s, q.open_ended, q.min_s, q.max_s, q.meta["seg"]],
					at + " shares the boundary"
				)


## v3: each slot's seat per segment is its start seat (rotation is gone: seat choice replaces it),
## one rider per seat; the drill likewise.
func test_every_slot_keeps_its_start_seat() -> void:
	for mission: String in ["ashfall_road", "drill"]:
		var c := _content(mission)
		for crew in [1, 2, 3, 4]:
			var plans := TankPlanBuilder.build_all(c, _slots(crew, 200.0, true))
			for slot in crew:
				var plan: EffortPlan = plans[slot + 1]
				var start: String = START[crew][slot]
				for i in plan.size():
					var at := "%s crew %d slot %d phase %d" % [mission, crew, slot, i]
					assert_eq(str(plan.phase(i).meta["engine"]), start, at)
			for i in c.segments().size():
				var seen := {}
				for slot in crew:
					seen[str((plans[slot + 1] as EffortPlan).phase(i).meta["engine"])] = true
				assert_eq(seen.size(), crew, "crew %d phase %d: one rider per seat" % [crew, i])


## Brief 2.3 and 2.9: mode, target_pct, ramp_to_pct, range_pct and grade_source per engine and
## segment; checkpoints ERG 50% for everyone.
func test_modes_and_numbers_follow_the_engine_tables() -> void:
	for case: Array in _matrix():
		var drill := str(case[0]) == "drill"
		var table: Dictionary = DRILL_TABLE if drill else ENGINE_TABLE
		var plans := _build(case)
		for peer: int in plans:
			var plan: EffortPlan = plans[peer]
			for i in plan.size():
				var ph := plan.phase(i)
				var seg := str(ph.meta["seg"])
				var want: Array = (
					CHECKPOINT if seg == "checkpoint" else table[str(ph.meta["engine"])][seg]
				)
				assert_eq(_shape(ph), want, "%s phase %d (%s)" % [_at(case, peer), i, seg])


## [mode, target_pct, ramp_to_pct, range_pct, grade_source] with null for unset fields.
func _shape(ph: PlanPhase) -> Array:
	if ph.mode == Wl.SIM:
		return [ph.mode, null, null, null, ph.grade_source]
	var ramp: Variant = ph.ramp_to_pct if ph.has_ramp() else null
	var rng: Variant = null
	if ph.range_pct.size() == 2:
		rng = [float(ph.range_pct[0]), float(ph.range_pct[1])]
	return [ph.mode, ph.target_pct, ramp, rng, null]


# --- Safety: BRIEF 4.5 and 4.6 -------------------------------------------------------------------


## BRIEF 4.5: per rider every ERG <-> SIM switch (the cool-down included) is >= 60 s apart with
## every combination of open-ended phases at their min_s and their max_s.
func test_switches_are_60_s_apart_with_every_open_phase_at_min_and_max() -> void:
	for case: Array in _matrix():
		if float(case[2]) != 200.0 or not bool(case[3]):
			continue  # plans are %-only: FTP and the verified flag change nothing here
		var plans := _build(case)
		for peer: int in plans:
			var final := PlanValidator.finalize(plans[peer])
			var open: Array[int] = []
			for i in final.size():
				if final.phase(i).open_ended:
					open.append(i)
			var worst := INF
			for mask in 1 << open.size():
				worst = minf(worst, _min_switch_gap(final, open, mask))
			assert_gte(worst, 60.0, _at(case, peer))


## The smallest gap between two mode switches; open phase open[k] runs max_s when bit k of `mask`
## is set, else min_s.
func _min_switch_gap(plan: EffortPlan, open: Array[int], mask: int) -> float:
	var t := 0.0
	var last := -INF
	var gap := INF
	for i in plan.size():
		var ph := plan.phase(i)
		if i > 0 and ph.mode != plan.phase(i - 1).mode:
			gap = minf(gap, t - last)
			last = t
		var k := open.find(i)
		if k >= 0:
			t += ph.max_s if mask & (1 << k) else ph.min_s
		else:
			t += ph.duration_s
	return gap


## BRIEF 4.6.8: every phase that can start in the first 300 s (open phases at min_s) asks ERG <=
## 65% (after the governor's floor at FTP 80 too) and no SIM grade source but flat or game with
## warm-up terrain (0..+2%); the depot ramp climbs 15 points over its 300 s.
func test_the_first_300_s_stay_within_the_warm_up_limits() -> void:
	for case: Array in _matrix():
		var c := _content(str(case[0]))
		var plans := _build(case)
		var ftp := float(case[2])
		for peer: int in plans:
			var plan: EffortPlan = plans[peer]
			var t := 0.0
			for i in plan.size():
				var ph := plan.phase(i)
				if t < TankConst.FIRST_S:
					var at := "%s phase %d" % [_at(case, peer), i]
					assert_has([Wl.WARMUP, Wl.RECOVERY], ph.kind, at + ": no WORK yet")
					if ph.mode == Wl.ERG:
						assert_lte(ph.peak_pct(), 65.0, at)
						assert_lte(_applied_pct(ph.peak_pct(), ftp, bool(case[3])), 65.0, at)
						if ph.has_ramp():
							assert_eq(ph.ramp_to_pct - ph.target_pct, 15.0, at + " ramp")
							assert_eq(ph.duration_s, 300.0, at + " ramp length")
					else:
						assert_has([Wl.GRADE_FLAT, Wl.GRADE_GAME], ph.grade_source, at)
						if ph.grade_source == Wl.GRADE_GAME:
							for pt: Array in c.segment(i).get("terrain", []):
								assert_between(float(pt[1]), 0.0, 2.0, at + " terrain")
				t += ph.min_s if ph.open_ended else ph.duration_s


## BRIEF 4.6.1: every ERG target, ramp end and range bound is 50-100% FTP; nothing is planned at 90%
## or more (v3: the gun line is the Drive seat's SIM flat dig, no ERG 90% block); the boss (max_s
## 360, the only phase over 300 s) stays under its 105% cap with every directive, after the
## governor's floor and the unverified factor.
func test_every_erg_value_is_50_to_100_and_the_long_boss_stays_under_105() -> void:
	for case: Array in _matrix():
		var c := _content(str(case[0]))
		var plans := _build(case)
		var ftp := float(case[2])
		var verified := bool(case[3])
		for peer: int in plans:
			var plan: EffortPlan = plans[peer]
			for i in plan.size():
				var ph := plan.phase(i)
				var at := "%s phase %d" % [_at(case, peer), i]
				if ph.mode == Wl.ERG:
					var values: Array[float] = [ph.target_pct]
					if ph.has_ramp():
						values.append(ph.ramp_to_pct)
					for v: Variant in ph.range_pct:
						values.append(float(v))
					for v in values:
						assert_between(v, 50.0, 100.0, at)
					var planned := maxf(ph.target_pct, ph.ramp_to_pct)
					assert_lt(planned, 90.0, at + " no 90% block in v3")
				if ph.worst_case_length_s() > 300.0:
					assert_eq(str(ph.meta["seg"]), "boss", at + " the only long phase")
					assert_lte(ph.peak_pct(), 105.0, at)
					for bank in range(0, 101, 5):
						var b := TankDirector.bank_target_pct(c, float(bank), ph)
						if ph.mode == Wl.ERG:
							assert_lte(_applied_pct(b, ftp, verified), 105.0, at + " bank")
				if not verified and ph.mode == Wl.ERG:
					assert_lte(
						_applied_pct(ph.peak_pct(), ftp, false),
						_applied_pct(ph.peak_pct(), ftp, true),
						at
					)


## The governor's applied ERG % FTP (SDK 21): x 0.85 unverified, whole watts rounded down, never
## below max(30% FTP, 50 W) rounded up.
func _applied_pct(pct: float, ftp: float, verified: bool) -> float:
	var w := floorf(pct / 100.0 * ftp * (1.0 if verified else 0.85))
	var floor_w := ceilf(maxf(0.3 * ftp, 50.0))
	return maxf(w, floor_w) / ftp * 100.0


## The bank's span (55..100) stays inside the phase's range_pct in every dynamo phase, so no bank
## directive is ever refused outside_range_pct; 55..65 in the drill's skirmish.
func test_the_bank_span_fits_every_dynamo_range() -> void:
	for mission: String in ["ashfall_road", "drill"]:
		var c := _content(mission)
		for crew in [2, 3, 4]:
			var plans := TankPlanBuilder.build_all(c, _slots(crew, 200.0, true))
			for peer: int in plans:
				var plan: EffortPlan = plans[peer]
				for i in plan.size():
					var ph := plan.phase(i)
					if not TankDirector.bank_phase(str(ph.meta["engine"]), ph):
						continue
					var r := ph.effective_range()
					for bank in range(0, 101, 10):
						var b := TankDirector.bank_target_pct(c, float(bank), ph)
						assert_between(b, float(r[0]), float(r[1]))
					var hi := 65.0 if mission == "drill" else 100.0
					assert_eq(TankDirector.bank_target_pct(c, 0.0, ph), hi)


# --- The drill (brief 2.9) and laps --------------------------------------------------------------


func test_the_drill_is_130_s_with_at_most_one_switch() -> void:
	for crew in [1, 2, 3, 4]:
		var plans := TankPlanBuilder.build_all(_content("drill"), _slots(crew, 200.0, true))
		for peer: int in plans:
			var plan: EffortPlan = plans[peer]
			assert_eq(plan.nominal_length_s(), 130.0)
			assert_eq(plan.max_length_s(), 130.0)
			var final := PlanValidator.finalize(plan)
			var switches := 0
			for i in range(1, final.size()):
				if final.phase(i).mode != final.phase(i - 1).mode:
					switches += 1
			assert_lte(switches, 1, "crew %d peer %d" % [crew, peer])
			for i in plan.size():
				assert_ne(plan.phase(i).kind, Wl.WORK, "no WORK phase in the drill")


## FIT laps: every phase is lap-true; with the platform's cool-down lap that is 12 for
## ashfall_road and 4 for the drill (notes).
func test_one_lap_per_segment() -> void:
	for mission: String in ["ashfall_road", "drill"]:
		var plans := TankPlanBuilder.build_all(_content(mission), _slots(3, 200.0, true))
		for peer: int in plans:
			var final := PlanValidator.finalize(plans[peer])
			var laps := 0
			for i in final.size():
				laps += 1 if final.phase(i).lap else 0
			assert_eq(laps, 12 if mission == "ashfall_road" else 4, mission)


## seg_of names each phase's segment and "" past the plan (the cool-down).
func test_seg_of() -> void:
	var plans := TankPlanBuilder.build_all(_content(), _slots(1, 200.0, true))
	var plan: EffortPlan = plans[1]
	for i in ASHFALL.size():
		assert_eq(TankPlanBuilder.seg_of(plan, i), str(ASHFALL[i][0]))
	assert_eq(TankPlanBuilder.seg_of(plan, plan.size()), "")
	assert_eq(TankPlanBuilder.seg_of(null, 0), "")

extends GutTest
## The cutaway on the tank is the machine card's engine, topping out on the strokes you hear (the owner's 1:1 cadence
## sync). The strokes' fractions are read from audio.json, so moving a stroke or the picture without the other fails.
## The picture is repainted on UNIT_STEPS and at MAX_HZ, so the painted tests hold how late it can be, not only where.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const BANK := "res://assets/tank/audio/audio.json"
## audio.json writes its fractions to 4 places.
const AT_EPS := 0.0002
const SWEEP := 7200
const FIRES: Array[String] = ["diesel_fire_a", "diesel_fire_b", "diesel_fire_c"]
const ROOM_AT := Vector2i(33, 6)
const RPMS: Array[float] = [60.0, 90.0, 110.0]

var _machine: Dictionary = {}


func before_all() -> void:
	var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BANK))
	_machine = bank["machines"]["diesel"]


## The `at` fractions of those sounds in the bank.
func _ats(sounds: Array[String]) -> Array[float]:
	var out: Array[float] = []
	for ev: Dictionary in _machine["events"]:
		if str(ev["sound"]) in sounds:
			for at: Variant in ev["at"]:
				out.append(float(at))
	out.sort()
	return out


## Where in a revolution a bore's place in its cycle reaches `target` degrees (0 a firing top, 360 an overlap top).
func _tops(target: float) -> Array[float]:
	var out: Array[float] = []
	for k in TankMechDiesel.D_THROW.size():
		var last := fposmod(
			TankMechDiesel.cycle_deg(TankMechDiesel.stroke_crank_deg(0.0), k) - target, 720.0
		)
		for n in range(1, SWEEP + 1):
			var ph := float(n) / float(SWEEP)
			var now := fposmod(
				TankMechDiesel.cycle_deg(TankMechDiesel.stroke_crank_deg(ph), k) - target, 720.0
			)
			if now < last:
				out.append(fposmod(ph, 1.0))
			last = now
	out.sort()
	return out


## The furthest any top lies from the stroke it pairs with, in revolutions; 1.0 if the counts differ.
func _worst(tops: Array[float], ats: Array[float]) -> float:
	if tops.size() != ats.size():
		return 1.0
	var worst := 0.0
	for i in tops.size():
		worst = maxf(worst, absf(tops[i] - ats[i]))
	return worst


func _inp(revs: float, on := true) -> Dictionary:
	var inp := {"t": 0.0}
	for seat: String in TankRig.SEATS:
		inp[seat] = {"slot": 0, "revs": revs, "on": on}
	inp["loader_seat"] = inp["loader"]
	inp["loader"] = {"lt": -1.0, "ready": 0, "elev": 0.0, "fire_t": 99.0}
	inp["bow"] = {"revs": revs}
	inp["repair"]["press_t"] = 0.0
	inp["repair"]["patches"] = 0
	return inp


## The bores showing a spark in the painted room.
func _sparks(it: TankInterior) -> Array[int]:
	var out: Array[int] = []
	var r := Rect2i(it.rig.rooms["drive"])
	for k in TankMechDiesel.D_THROW.size():
		var x := (
			r.position.x
			+ ROOM_AT.x
			+ 3
			+ k * TankInterior.DIESEL_BORE_PITCH
			+ TankInterior.DIESEL_BORE_W / 2
			- 1
		)
		var c := it.img.get_pixel(x, r.position.y + ROOM_AT.y + 3)
		if c.is_equal_approx(TankInterior.FIRE1):
			out.append(k)
	return out


## The topmost row of each piston in the painted room (ST4 is its lit top row).
func _piston_rows(it: TankInterior) -> Array[int]:
	var out: Array[int] = []
	var r := Rect2i(it.rig.rooms["drive"])
	var y0 := r.position.y + ROOM_AT.y
	for k in TankMechDiesel.D_THROW.size():
		var x := r.position.x + ROOM_AT.x + 3 + k * TankInterior.DIESEL_BORE_PITCH + 2
		var row := -1
		for y in range(y0 + 2, y0 + 13):
			var c := it.img.get_pixel(x, y)
			if c.r > 0.5 and c.g > 0.5 and c.b > 0.4 and row < 0:
				row = y - y0
		out.append(row)
	return out


func test_it_is_the_cards_engine() -> void:
	assert_eq(TankMechDiesel.D_THROW.size(), 3, "three bores, as the card")
	assert_eq(float(TankMechDiesel.RATIO["diesel"]), 2.0)
	# Throw and cycle agree on where a top is, on the card's constants.
	for k in TankMechDiesel.D_THROW.size():
		for n in 720:
			var crank := float(n)
			var t := TankMechDiesel.throw_deg(crank, k)
			var c := TankMechDiesel.cycle_deg(crank, k)
			assert_almost_eq(fposmod(c, 360.0), t, 0.001, "bore %d at %d degrees" % [k, n])
	var source := FileAccess.get_file_as_string("res://src/games/tank/view/tank_interior.gd")
	assert_false(source.contains("ad * 2.4"), "no ratio of its own")
	assert_true(source.contains("for k in TankMechDiesel.D_THROW.size():"))


func test_the_bores_fill_the_room_with_no_gap_at_one_end() -> void:
	var left := 3
	var right := 48 - (3 + 2 * TankInterior.DIESEL_BORE_PITCH + TankInterior.DIESEL_BORE_W)
	assert_eq(left, right, "the same margin at both ends of 48 px")


func test_the_firing_tops_fall_on_the_fire_strokes_in_the_bank() -> void:
	var fires := _ats(FIRES)
	assert_eq(fires.size(), 3)
	var worst := _worst(_tops(0.0), fires)
	assert_lte(
		worst,
		AT_EPS + 1.0 / float(SWEEP),
		"the furthest top from its stroke, in revolutions: %f" % worst
	)


func test_the_overlap_tops_fall_on_the_inlet_strokes_in_the_bank() -> void:
	var inlets := _ats(["diesel_valve_in"] as Array[String])
	var worst := _worst(_tops(360.0), inlets)
	assert_lte(
		worst,
		AT_EPS + 1.0 / float(SWEEP),
		"the furthest top from its stroke, in revolutions: %f" % worst
	)


func test_moving_a_stroke_without_the_picture_would_fail() -> void:
	# The bank is read, not copied: one step off in the file is more than the tolerance above.
	var moved := _ats(FIRES)
	moved[1] += 1.0 / TankInterior.UNIT_STEPS
	assert_gt(_worst(_tops(0.0), moved), AT_EPS + 1.0 / float(SWEEP))
	var dropped := _ats(FIRES)
	dropped.pop_back()
	assert_eq(_worst(_tops(0.0), dropped), 1.0)


func test_the_cards_own_tops_stay_where_the_lead_says() -> void:
	# The card's firing tops, with no lead, are 40 crank degrees after the strokes. The lead is that gap, not a guess.
	var card_top := 240.0 / (float(TankMechDiesel.RATIO["diesel"]) * 360.0)
	var lead := _lead_revs()
	assert_almost_eq(card_top - lead, _ats(FIRES)[0], AT_EPS)


func _lead_revs() -> float:
	return TankMechDiesel.D_STROKE_LEAD / (float(TankMechDiesel.RATIO["diesel"]) * 360.0)


func test_each_fire_stroke_has_its_own_bore_and_its_top_is_the_highest() -> void:
	var it := TankInterior.new(TankRig.shared())
	var seen := {}
	for at: float in _ats(FIRES):
		it.paint_all(_inp(at + 0.0001))
		var sparks := _sparks(it)
		assert_eq(sparks.size(), 1, "one bore lit just after the stroke at %f" % at)
		if sparks.size() == 1:
			seen[sparks[0]] = true
			var rows := _piston_rows(it)
			for k in rows.size():
				assert_gte(
					rows[k], rows[sparks[0]], "at %f bore %d is at its top" % [at, sparks[0]]
				)
	assert_eq(seen.size(), 3, "three strokes, three bores")


func test_no_spark_at_an_overlap_top_nor_just_before_a_firing_top() -> void:
	var it := TankInterior.new(TankRig.shared())
	for at: float in _ats(["diesel_valve_in"] as Array[String]):
		it.paint_all(_inp(at + 0.0001))
		assert_eq(_sparks(it), [] as Array[int], "an overlap top at %f" % at)
	for at: float in _ats(FIRES):
		it.paint_all(_inp(at - 0.002))
		assert_eq(_sparks(it), [] as Array[int], "just ahead of the stroke at %f" % at)


func test_a_stopped_machine_shows_no_spark() -> void:
	var it := TankInterior.new(TankRig.shared())
	it.paint_all(_inp(0.2779, false))
	assert_eq(_sparks(it), [] as Array[int])


func test_the_step_after_a_stroke_is_within_one_unit_step() -> void:
	# paint() repaints a machine when floor(revs * UNIT_STEPS) changes, so a top is first drawn at the next step.
	for sounds: Array[String] in [FIRES, ["diesel_valve_in"] as Array[String]]:
		for at: float in _ats(sounds):
			var next := (floorf(at * TankInterior.UNIT_STEPS) + 1.0) / TankInterior.UNIT_STEPS
			assert_lte(next - at, 1.0 / TankInterior.UNIT_STEPS, "the top at %f" % at)


## Plays the crew's rooms through paint() at 60 frames a second, every seat changing, as a full crew does.
## Returns the delay in seconds from each stroke to the first frame its bore shows lit, -1.0 for one never shown.
func _lags(rpm: float, seconds: float) -> Array[float]:
	var it := TankInterior.new(TankRig.shared())
	var strokes := _ats(FIRES)
	var dt := 1.0 / 60.0
	var rate := rpm / 60.0
	it.paint_all(_inp(0.0))
	var pending: Array[float] = []
	var out: Array[float] = []
	var next_at := 0
	var next_rev := 0
	var had := false
	for f in int(seconds * 60.0):
		var now := float(f + 1) * dt
		var revs := now * rate
		var inp := _inp(revs)
		inp["t"] = now
		while float(next_rev) + strokes[next_at] <= revs + AT_EPS:
			pending.append((float(next_rev) + strokes[next_at]) / rate)
			next_at += 1
			if next_at == strokes.size():
				next_at = 0
				next_rev += 1
		it.paint(inp, now)
		var lit := not _sparks(it).is_empty()
		if lit and not had and not pending.is_empty():
			out.append(maxf(now - float(pending.pop_front()), 0.0))
		while pending.size() > 1:
			pending.pop_front()
			out.append(-1.0)
		had = lit
	return out


func test_a_full_crew_never_loses_a_spark_and_it_lands_within_one_step_of_its_stroke() -> void:
	for rpm: float in RPMS:
		var lags := _lags(rpm, 4.0)
		assert_gte(lags.size(), int(rpm / 60.0 * 3.0 * 3.0), "%d rpm: sparks seen" % int(rpm))
		var worst := 0.0
		for lag in lags:
			assert_gte(lag, 0.0, "%d rpm: a stroke with no spark" % int(rpm))
			worst = maxf(worst, lag)
		var step := 60.0 / rpm / TankInterior.UNIT_STEPS
		gut.p("%d rpm: worst %.1f ms, one step %.1f ms" % [int(rpm), worst * 1000.0, step * 1000.0])
		assert_lte(worst, step, "%d rpm: worst %.1f ms" % [int(rpm), worst * 1000.0])


func test_a_firing_top_still_keeps_to_the_budget() -> void:
	var it := TankInterior.new(TankRig.shared())
	it.paint_all(_inp(0.2))
	var before := it.paints
	var inp := _inp(0.2779)
	inp["t"] = 1.0
	assert_true(it.paint(inp, 10.0, 1))
	assert_eq(it.paints - before, 1, "a budget of one paints one")
	assert_eq(_sparks(it).size(), 1, "and that one is the Drive room")


func test_the_room_and_the_audio_read_one_crank() -> void:
	var s := U.fixture("state", 3)
	var v := U.view_of(self, s)
	U.run(v, 30)
	var paint := v.paint_input(s)
	var heard := v.audio_feed(s)
	var moved := 0
	for seat: String in TankRig.SEATS:
		assert_eq(
			float(paint[seat if seat != "loader" else "loader_seat"]["revs"]),
			float(heard[seat]["revs"]),
			seat
		)
		if float(heard[seat]["revs"]) > 0.0:
			moved += 1
	assert_gt(moved, 0, "a crew's cranks turn")
	assert_eq(float(paint["drive"]["revs"]), v.machine_phase("drive"))

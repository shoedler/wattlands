extends GutTest
## TankHud.spec() sits exactly at the G0 Rect2i table (ADR "HUD layout"): kit widgets at or above
## their 1080p minimums / 3, the HUD only in y 0-60 and 300-360, nothing in the PANIC corner, no
## overlaps, and the Tank Controls at their rects.

const F := preload("res://tests/games/tank/tank_fakes.gd")
## The G0 table, written out here so a change to TankHud.RECTS must be deliberate.
const TABLE := {
	"timeline": Rect2i(4, 2, 200, 36),
	"hull_hp": Rect2i(206, 2, 60, 36),
	"teammates": Rect2i(268, 2, 140, 22),
	"boss_bars": Rect2i(410, 2, 226, 22),
	"toasts": Rect2i(268, 26, 368, 13),
	"banners": Rect2i(206, 40, 430, 19),
	"power_gauge": Rect2i(4, 302, 100, 36),
	"cadence": Rect2i(106, 302, 98, 36),
	"watts": Rect2i(206, 302, 60, 36),
	"wbal": Rect2i(4, 342, 100, 15),
	"gear": Rect2i(106, 342, 98, 15),
	"station_card": Rect2i(268, 302, 232, 56),
	"objective": Rect2i(504, 300, 132, 15),
}
## Kit minimums at 1080p (GAME_SDK 10.1) divided by 3, rounded up.
const KIT_MIN := {
	"power_gauge": Vector2i(100, 36),
	"cadence": Vector2i(97, 33),
	"timeline": Vector2i(127, 36),
	"hull_hp": Vector2i(57, 36),
	"watts": Vector2i(57, 36),
	"wbal": Vector2i(80, 14),
	"gear": Vector2i(50, 14),
	"teammates": Vector2i(134, 21),
}

var _game: TankGame = null
var _spec: HudSpec = null


func before_each() -> void:
	_game = autofree(F.make_game(F.make_ctx(3)))
	_spec = TankHud.spec(_game)


func after_each() -> void:
	for c: Dictionary in _spec.controls:
		(c["control"] as Control).free()


func _widget(id: String, source: String = "") -> Dictionary:
	for w: Dictionary in _spec.widgets:
		if (
			w["widget"] == id
			and (
				source == ""
				or str(w["options"].get("source", "")) == source
				or str(w["options"].get("id", "")) == source
			)
		):
			return w
	return {}


func test_the_rect_table_is_the_g0_table() -> void:
	assert_eq(TankHud.RECTS.size(), TABLE.size())
	for k: String in TABLE:
		assert_eq(TankHud.RECTS[k], TABLE[k], k)


func test_every_widget_sits_at_its_rect() -> void:
	assert_eq(_widget(HudSpec.TIMELINE)["at"], TABLE["timeline"])
	assert_eq(_widget(HudSpec.TEAMMATES)["at"], TABLE["teammates"])
	assert_eq(_widget(HudSpec.POWER_GAUGE)["at"], TABLE["power_gauge"])
	assert_eq(_widget(HudSpec.CADENCE)["at"], TABLE["cadence"])
	assert_eq(_widget(HudSpec.WBAL)["at"], TABLE["wbal"])
	assert_eq(_widget(HudSpec.GEAR)["at"], TABLE["gear"])
	var hull := _widget(HudSpec.READOUT, TankHud.READOUT_HULL)
	assert_eq(hull["at"], TABLE["hull_hp"])
	assert_eq(hull["options"]["source"], "custom", "the module feeds the hull HP")
	var watts := _widget(HudSpec.READOUT, "power_w")
	assert_eq(watts["at"], TABLE["watts"])
	assert_eq(_spec.toast_area, TABLE["toasts"])
	assert_eq(_spec.banner_area, TABLE["banners"])
	assert_true(_spec.show_safety_banners, "the warm-up and pause banners stay on")


func test_the_kit_widgets_are_at_least_their_1080p_minimum() -> void:
	for k: String in KIT_MIN:
		var r: Rect2i = TankHud.RECTS[k]
		assert_gte(r.size.x, KIT_MIN[k].x, "%s width" % k)
		assert_gte(r.size.y, KIT_MIN[k].y, "%s height" % k)


func test_the_hud_stays_in_its_bands_and_off_the_panic_corner() -> void:
	var panic := Rect2i(
		TankConst.PANIC_X, TankConst.PANIC_Y, 640 - TankConst.PANIC_X, 360 - TankConst.PANIC_Y
	)
	for k: String in TankHud.RECTS:
		var r: Rect2i = TankHud.RECTS[k]
		assert_true(
			r.end.y <= TankConst.HUD_TOP_H or r.position.y >= TankConst.HUD_BOTTOM_Y,
			"%s in a HUD band" % k
		)
		assert_false(r.intersects(panic), "%s clear of PANIC" % k)
		assert_true(r.position.x >= 0 and r.end.x <= 640 and r.end.y <= 360, "%s on screen" % k)
		assert_false(
			r.end.x > TankConst.PANIC_X and r.end.y > TankConst.PANIC_Y, "%s misses the corner" % k
		)


func test_no_two_rects_overlap() -> void:
	var names := TankHud.RECTS.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			assert_false(
				(TankHud.RECTS[names[i]] as Rect2i).intersects(TankHud.RECTS[names[j]]),
				"%s and %s" % [names[i], names[j]]
			)


func test_the_tank_controls_are_real_controls_at_their_rects_reading_the_game() -> void:
	var by_name := {}
	for c: Dictionary in _spec.controls:
		by_name[(c["control"] as Control).name] = c
	assert_eq(by_name.keys().size(), 3)
	assert_eq(by_name["TankStationCard"]["at"], TABLE["station_card"])
	assert_eq(by_name["TankObjectiveLine"]["at"], TABLE["objective"])
	assert_eq(by_name["TankBossBars"]["at"], TABLE["boss_bars"])
	assert_is(by_name["TankStationCard"]["control"], TankStationCard)
	assert_is(by_name["TankObjectiveLine"]["control"], TankObjectiveLine)
	assert_is(by_name["TankBossBars"]["control"], TankBossBars)
	for n: String in by_name:
		assert_eq((by_name[n]["control"] as TankHudPanel).game, _game, n)


func test_every_position_is_valid_for_the_hud_layer() -> void:
	for w: Dictionary in _spec.widgets:
		assert_true(HudSpec.is_valid_position(w["at"]), str(w["widget"]))
	for c: Dictionary in _spec.controls:
		assert_true(HudSpec.is_valid_position(c["at"]))
	assert_true(HudSpec.is_valid_position(_spec.toast_area))
	assert_true(HudSpec.is_valid_position(_spec.banner_area))


func test_key_numbers_are_at_least_48_px_at_1080p() -> void:
	assert_gte(TankStationCard.KEY_PX, 48.0)
	var rect: Rect2i = TankHud.RECTS["station_card"]
	var card := _spec.controls[0]["control"] as TankStationCard
	assert_eq(card.design_size, Vector2(rect.size * 3), "designed for the rect at 1080p")
	card.size = Vector2(rect.size * 3)
	assert_almost_eq(card.k(), 1.0, 1e-6)
	assert_gte(TankStationCard.KEY_PX * card.k(), float(WlTheme.KEY_NUMBER_MIN_PX))
	var objective := _spec.controls[1]["control"] as TankObjectiveLine
	assert_eq(objective.design_size, Vector2(TankHud.RECTS["objective"].size * 3))
	var boss := _spec.controls[2]["control"] as TankBossBars
	assert_eq(boss.design_size, Vector2(TankHud.RECTS["boss_bars"].size * 3))


func test_the_station_card_cells_fit_the_card_without_overlap() -> void:
	var card_w := 696.0
	for i in 3:
		var c := TankStationCard.cell_rect(i)
		assert_gte(c.position.x, 0.0)
		assert_lte(c.end.x, card_w)
		assert_lte(c.end.y, 168.0)
		if i > 0:
			assert_gt(c.position.x, TankStationCard.cell_rect(i - 1).end.x)
	for i in 3:
		var lr := TankStationCard.lever_rect(i)
		assert_true(
			TankStationCard.cell_rect(0).encloses(lr), "lever position %d inside cell 0" % i
		)
		if i > 0:
			assert_gt(lr.position.x, TankStationCard.lever_rect(i - 1).end.x)


func test_a_new_spec_is_built_each_call() -> void:
	var other := TankHud.spec(_game)
	assert_ne(other.controls[0]["control"], _spec.controls[0]["control"])
	for c: Dictionary in other.controls:
		(c["control"] as Control).free()

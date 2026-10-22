extends GutTest
## Siege's HudSpec (brief 3 "HUD" table): the right widgets at the right anchors, and nothing of
## Siege's in the bottom-right corner the app reserves for its PANIC button (BRIEF 4.6.5).

const PANIC := Vector2(380, 100)
const SCREEN := Vector2(1920, 1080)

var _game: SiegeGame = null
var _spec: HudSpec = null


func before_each() -> void:
	_game = SiegeHudUtil.make_game()
	_spec = SiegeHud.spec(_game)


func after_each() -> void:
	SiegeHudUtil.free_game(_game)


func _widgets_at(anchor: String) -> Array[String]:
	var out: Array[String] = []
	for w in _spec.widgets:
		if w["at"] is String and w["at"] == anchor:
			out.append(str(w["widget"]))
	return out


func _controls_at(anchor: Variant) -> Array[Control]:
	var out: Array[Control] = []
	for c in _spec.controls:
		if c["at"] is String and c["at"] == anchor:
			out.append(c["control"])
	return out


func test_top_left_holds_the_timeline_then_the_rush_strip_and_wave_info() -> void:
	assert_eq(_widgets_at(HudSpec.TOP_LEFT), [HudSpec.TIMELINE] as Array[String])
	var ctl := _controls_at(HudSpec.TOP_LEFT)
	assert_eq(ctl.size(), 2)
	assert_true(ctl[0] is SiegeRushStrip, "the rush strip sits right below the timeline")
	assert_true(ctl[1] is SiegeWaveInfo)


func test_top_right_has_the_gate_hp_and_the_denarii_readouts() -> void:
	var ids: Array[String] = []
	for w in _spec.widgets:
		if w["at"] is String and w["at"] == HudSpec.TOP_RIGHT:
			assert_eq(w["widget"], HudSpec.READOUT)
			assert_eq((w["options"] as Dictionary)["source"], "custom")
			ids.append(str((w["options"] as Dictionary)["id"]))
	assert_eq(ids, [SiegeHud.READOUT_GATE, SiegeHud.READOUT_DENARII] as Array[String])


func test_bottom_left_has_gauge_cadence_and_wbal() -> void:
	assert_eq(
		_widgets_at(HudSpec.BOTTOM_LEFT),
		[HudSpec.POWER_GAUGE, HudSpec.CADENCE, HudSpec.WBAL] as Array[String]
	)


func test_bottom_centre_has_the_teammate_strip_and_siege_own_strip_beside_it() -> void:
	assert_eq(_widgets_at(HudSpec.BOTTOM), [HudSpec.TEAMMATES] as Array[String])
	var ctl := _controls_at(HudSpec.BOTTOM)
	assert_eq(ctl.size(), 1)
	assert_true(ctl[0] is SiegeStripOverlay)


func test_bottom_right_has_the_gear_the_overdrive_button_and_the_routing_card() -> void:
	assert_eq(_widgets_at(HudSpec.BOTTOM_RIGHT), [HudSpec.GEAR] as Array[String])
	var ctl := _controls_at(HudSpec.BOTTOM_RIGHT)
	assert_eq(ctl.size(), 2)
	assert_true(ctl[0] is SiegeOverdriveButton, "the button sits lowest, right above PANIC")
	assert_true(ctl[1] is SiegeRouteCard)


func test_the_shop_is_a_centre_rect_clear_of_the_panic_corner_and_the_corner_stacks() -> void:
	var r := SiegeHud.SHOP_RECT
	var found := false
	for c in _spec.controls:
		if c["control"] is SiegeShopPanel:
			found = true
			assert_eq(c["at"], r)
	assert_true(found)
	var panic := Rect2(Vector2(SCREEN.x - 32.0 - PANIC.x, SCREEN.y - 32.0 - PANIC.y), PANIC)
	assert_false(Rect2(r).intersects(panic))
	assert_gt(r.position.x, 672, "right of the top-left stack (640 wide + 32 margin)")
	assert_lt(r.end.x, 1548, "left of the top-right stack")
	assert_gte(r.position.y, 96, "below the top-centre banners")
	assert_lte(r.end.y, 700, "above the bottom-centre strip")


func test_toasts_and_banners_and_the_safety_banners_stay_on() -> void:
	assert_eq(_spec.toast_area, HudSpec.TOP_RIGHT, "clear of the centre shop")
	assert_eq(_spec.banner_area, HudSpec.TOP)
	assert_true(_spec.show_safety_banners)


func test_every_position_is_valid() -> void:
	for w in _spec.widgets:
		assert_true(HudSpec.is_valid_position(w["at"]))
	for c in _spec.controls:
		assert_true(HudSpec.is_valid_position(c["at"]))


func test_a_spec_without_a_game_builds() -> void:
	var s := SiegeHud.spec(null)
	assert_true(s.has_widget(HudSpec.TIMELINE))
	for c in s.controls:
		(c["control"] as Control).free()


func test_nothing_of_siege_sits_in_the_panic_reserve() -> void:
	var ctx := _game.ctx
	var hud := HudLayer.new()
	hud.screen_size_override = SCREEN
	hud.sounds = false
	add_child_autofree(hud)
	hud.set_process(false)
	hud.reserve_corner(HudSpec.BOTTOM_RIGHT, PANIC)
	hud.build(_spec, ctx)
	hud.relayout()
	await wait_frames(3)
	hud.relayout()
	var panic := Rect2(Vector2(SCREEN.x - 32.0 - PANIC.x, SCREEN.y - 32.0 - PANIC.y), PANIC)
	var checked := 0
	for node: Node in [
		_controls_at(HudSpec.BOTTOM_RIGHT)[0], _controls_at(HudSpec.BOTTOM_RIGHT)[1]
	]:
		var c := node as Control
		c.visible = true
		var rect := c.get_global_rect()
		assert_false(rect.intersects(panic), "%s overlaps the PANIC reserve: %s" % [c.name, rect])
		assert_lte(rect.end.y, panic.position.y, "%s sits above PANIC" % c.name)
		checked += 1
	assert_eq(checked, 2)
	for gear in hud.widgets_of(HudSpec.GEAR):
		assert_lte((gear as Control).get_global_rect().end.y, panic.position.y + 0.5)


func test_the_centre_is_clear_in_a_wave() -> void:
	# The shop is the only centre Control and it hides outside the breaks.
	var shop: SiegeShopPanel = null
	for c in _spec.controls:
		if c["control"] is SiegeShopPanel:
			shop = c["control"]
	add_child_autofree(shop)
	shop.refresh()
	assert_false(shop.visible, "the mid-wave fixture is a wave")
	_game.state.role = SiegeIds.ROLE_BREAK
	shop.refresh()
	assert_true(shop.visible)

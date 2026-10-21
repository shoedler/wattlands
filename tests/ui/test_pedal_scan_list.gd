extends GutTest
## PedalScanList (BRIEF 3.5, 3.9; docs/OWNERSHIP.md PSL1-PSL3): scan timing, picks by surge,
## confirm and ERG auto-confirm (after two full cycles, auto = true, via "auto"), backing out,
## focus moves that pause scanning for 10 s, disabled items, and following the router.

const DT := Wl.SIM_DT
const FakeRider := preload("res://tests/ui/fake_local_rider.gd")

var _list: PedalScanList = null


func before_each() -> void:
	_list = PedalScanList.new()
	_list.listen_to_input = false
	_list.real_time = false
	_list.sounds = false
	add_child_autofree(_list)
	watch_signals(_list)


func _items(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"id": "item%d" % i, "text": "Item %d" % i})
	return out


## Advance `seconds` in fixed 0.05 s steps.
func _run(seconds: float) -> void:
	var steps := roundi(seconds / DT)
	for _i in steps:
		_list.tick(DT)


# --- scanning ---------------------------------------------------------------------------------

func test_defaults() -> void:
	assert_eq(_list.scan_interval_s, 1.6, "the profile default")
	assert_true(_list.scanning)
	assert_false(_list.erg_auto_confirm)
	assert_false(_list.follow_local_mode)
	assert_eq(_list.highlighted(), -1)
	assert_eq(_list.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_set_items_highlights_the_first_enabled() -> void:
	_list.set_items([{"id": "a", "text": "A", "disabled": true}, {"id": "b", "text": "B"}])
	assert_eq(_list.highlighted(), 1)
	assert_eq(_list.highlighted_id(), "b")
	assert_eq(_list.item_count(), 2)


func test_scan_advances_every_interval_and_wraps() -> void:
	_list.set_items(_items(3))
	_run(1.55)
	assert_eq(_list.highlighted(), 0)
	_run(0.05)
	assert_eq(_list.highlighted(), 1, "after 1.6 s")
	_run(1.6)
	assert_eq(_list.highlighted(), 2)
	_run(1.6)
	assert_eq(_list.highlighted(), 0, "wraps around")
	assert_signal_emit_count(_list, "highlight_changed", 4, "set_items + 3 steps")


func test_custom_interval() -> void:
	_list.scan_interval_s = 0.5
	_list.set_items(_items(4))
	_run(1.0)
	assert_eq(_list.highlighted(), 2)


func test_scanning_off_holds_focus() -> void:
	_list.scanning = false
	_list.set_items(_items(3))
	_run(10.0)
	assert_eq(_list.highlighted(), 0)


func test_disabled_items_are_skipped() -> void:
	_list.set_items([
		{"id": 0, "text": "zero"}, {"id": 1, "text": "one", "disabled": true}, {"id": 2, "text": "two"},
	])
	_run(1.6)
	assert_eq(_list.highlighted(), 2)
	_run(1.6)
	assert_eq(_list.highlighted(), 0)
	_list.feed_action(&"down")
	assert_eq(_list.highlighted(), 2, "focus moves skip it too")


func test_disabled_item_cannot_be_picked_or_highlighted() -> void:
	_list.set_items([{"id": 0, "text": "zero"}, {"id": 1, "text": "one", "disabled": true}])
	_list.set_highlight(1)
	assert_push_warning("can't highlight")
	assert_eq(_list.highlighted(), 0)
	_list.set_item_disabled(0, true)
	assert_eq(_list.highlighted(), -1, "nothing left to highlight")
	_list.feed_gesture(Wl.G_SURGE)
	assert_signal_not_emitted(_list, "item_chosen")
	_list.set_item_disabled(1, false)
	assert_eq(_list.highlighted(), 1)


func test_set_item_disabled_out_of_range_is_rejected() -> void:
	_list.set_items(_items(2))
	_list.set_item_disabled(5, true)
	assert_push_error("no item 5")


# --- picks ------------------------------------------------------------------------------------

func test_surge_picks_the_highlighted_item() -> void:
	_list.set_items(_items(3))
	_run(1.6)
	_list.feed_gesture(Wl.G_SURGE)
	assert_signal_emit_count(_list, "item_chosen", 1)
	assert_eq(get_signal_parameters(_list, "item_chosen"), [1, "item1", false])
	assert_eq(get_signal_parameters(_list, "item_picked"), [1, "item1", "surge"])


func test_confirm_picks_with_via_action() -> void:
	_list.set_items(_items(3))
	_list.feed_action(&"confirm")
	assert_eq(get_signal_parameters(_list, "item_chosen"), [0, "item0", false])
	assert_eq(get_signal_parameters(_list, "item_picked"), [0, "item0", "action"])


func test_coast_and_back_back_out() -> void:
	_list.set_items(_items(2))
	_list.feed_gesture(Wl.G_COAST)
	_list.feed_action(&"back")
	assert_signal_emit_count(_list, "backed_out", 2)
	assert_signal_not_emitted(_list, "item_chosen")


func test_coast_never_backs_out_in_erg() -> void:
	_list.set_items(_items(2))
	_list.set_local_mode(Wl.ERG)
	_list.feed_gesture(Wl.G_COAST)
	assert_signal_not_emitted(_list, "backed_out")
	_list.feed_action(&"back")
	assert_signal_emit_count(_list, "backed_out", 1, "the back action still works")


func test_other_gestures_and_actions_are_ignored() -> void:
	_list.set_items(_items(2))
	_list.feed_gesture(Wl.G_PEDAL_START)
	_list.feed_gesture(Wl.G_STOP_5S)
	_list.feed_action(&"item")
	assert_signal_not_emitted(_list, "item_chosen")
	assert_signal_not_emitted(_list, "backed_out")


# --- focus moves ------------------------------------------------------------------------------

func test_up_down_move_focus_and_pause_scanning_for_10_s() -> void:
	_list.set_items(_items(4))
	_list.feed_action(&"down")
	_list.feed_action(&"down")
	assert_eq(_list.highlighted(), 2)
	_list.feed_action(&"up")
	assert_eq(_list.highlighted(), 1)
	assert_almost_eq(_list.scan_paused_left_s(), 10.0, 1e-6)
	_run(9.95)
	assert_eq(_list.highlighted(), 1, "no scanning during the pause")
	_run(0.05)
	assert_eq(_list.scan_paused_left_s(), 0.0)
	_run(1.55)
	assert_eq(_list.highlighted(), 1)
	_run(0.05)
	assert_eq(_list.highlighted(), 2, "scanning resumed after 10 s")


func test_left_right_move_like_up_down() -> void:
	_list.set_items(_items(3))
	_list.feed_action(&"right")
	assert_eq(_list.highlighted(), 1)
	_list.feed_action(&"left")
	_list.feed_action(&"left")
	assert_eq(_list.highlighted(), 2, "wraps")


func test_set_highlight() -> void:
	_list.set_items(_items(3))
	_list.set_highlight(2)
	assert_eq(_list.highlighted(), 2)
	assert_eq(get_signal_parameters(_list, "highlight_changed"), [2])


# --- ERG auto-confirm ---------------------------------------------------------------------------

func test_auto_confirm_after_two_full_cycles() -> void:
	_list.erg_auto_confirm = true
	_list.set_items(_items(3))
	assert_almost_eq(_list.auto_confirm_after_s(), 9.6, 1e-6, "2 x 3 items x 1.6 s")
	_run(9.55)
	assert_signal_not_emitted(_list, "item_chosen")
	_run(0.05)
	assert_signal_emit_count(_list, "item_chosen", 1)
	assert_eq(get_signal_parameters(_list, "item_chosen"), [0, "item0", true], "two cycles end on the first item")
	assert_eq(get_signal_parameters(_list, "item_picked"), [0, "item0", "auto"])


func test_auto_confirm_without_scanning() -> void:
	_list.erg_auto_confirm = true
	_list.scanning = false
	_list.set_items(_items(2))
	_list.set_highlight(1)
	_run(6.35)
	assert_signal_not_emitted(_list, "item_chosen")
	_run(0.05)
	assert_eq(get_signal_parameters(_list, "item_chosen"), [1, "item1", true])


func test_auto_confirm_counts_enabled_items_only() -> void:
	_list.erg_auto_confirm = true
	_list.set_items([{"id": 0, "text": "a"}, {"id": 1, "text": "b", "disabled": true}, {"id": 2, "text": "c"}])
	assert_almost_eq(_list.auto_confirm_after_s(), 6.4, 1e-6)


func test_auto_confirm_repeats_two_cycles_after_a_pick() -> void:
	_list.erg_auto_confirm = true
	_list.set_items(_items(2))
	_run(6.4)
	_run(6.4)
	assert_signal_emit_count(_list, "item_chosen", 2)


func test_input_restarts_the_auto_confirm_count() -> void:
	_list.erg_auto_confirm = true
	_list.set_items(_items(2))
	_run(5.0)
	_list.feed_action(&"down")
	var moved := _list.highlighted()
	_run(6.35)
	assert_signal_not_emitted(_list, "item_chosen")
	_run(0.05)
	assert_eq(get_signal_parameters(_list, "item_chosen"), [moved, "item%d" % moved, true], "still on the moved focus (scan paused 10 s)")


func test_no_auto_confirm_outside_erg() -> void:
	_list.set_items(_items(2))
	_run(30.0)
	assert_signal_not_emitted(_list, "item_chosen")
	assert_eq(_list.auto_confirm_left_s(), INF)


func test_follow_local_mode() -> void:
	_list.follow_local_mode = true
	_list.set_items(_items(2))
	_list.set_local_mode(Wl.ERG)
	assert_true(_list.erg_auto_confirm)
	_list.set_local_mode(Wl.SIM)
	assert_false(_list.erg_auto_confirm)
	_list.follow_local_mode = false
	_list.set_local_mode(Wl.ERG)
	assert_false(_list.erg_auto_confirm, "without follow_local_mode the flag is left alone")


## Sessions: with follow_local_mode the list reads the InputRouter's attached rider on every
## tick (headless too), so an ERG pick auto-confirms and a SIM one doesn't.
func test_follow_local_mode_reads_the_router_rider_each_tick() -> void:
	var bus: WlEventBus = autofree(WlEventBus.new())
	var router := WlInputRouter.new()
	router.bus = bus
	router.load_on_ready = false
	add_child_autofree(router)
	var rider: FakeRider = autofree(FakeRider.new())
	rider.fake_mode = Wl.ERG
	router.attach_rider(rider)
	_list.router = router
	_list.follow_local_mode = true
	_list.set_items(_items(2))
	_list.tick(DT)
	assert_true(_list.erg_auto_confirm, "ERG rider: auto-confirm on")
	_list.feed_gesture(Wl.G_COAST)
	assert_signal_not_emitted(_list, "backed_out", "coast never backs out in ERG")
	_run(6.4)
	assert_signal_emit_count(_list, "item_chosen", 1)
	assert_eq(get_signal_parameters(_list, "item_picked")[2], "auto")
	rider.fake_mode = Wl.SIM
	_list.tick(DT)
	assert_false(_list.erg_auto_confirm, "SIM rider: off")
	_run(20.0)
	assert_signal_emit_count(_list, "item_chosen", 1, "no auto pick outside ERG")
	_list.feed_gesture(Wl.G_COAST)
	assert_signal_emit_count(_list, "backed_out", 1, "coast backs out outside ERG")


## A game that sets erg_auto_confirm itself from Telemetry.mode (no set_local_mode) still
## gets "coast never backs out in ERG".
func test_coast_never_backs_out_of_an_erg_pick_without_a_mode() -> void:
	_list.erg_auto_confirm = true
	_list.set_items(_items(2))
	_list.feed_gesture(Wl.G_COAST)
	assert_signal_not_emitted(_list, "backed_out")
	_list.feed_action(&"back")
	assert_signal_emit_count(_list, "backed_out", 1, "the back action still works")
	_list.set_local_mode(Wl.SIM)
	_list.feed_gesture(Wl.G_COAST)
	assert_signal_emit_count(_list, "backed_out", 2, "a known SIM mode wins")


func test_scan_interval_comes_from_the_profile() -> void:
	var settings := get_tree().root.get_node_or_null("Settings") as WlSettings
	assert_not_null(settings, "the Settings autoload")
	if settings == null:
		return
	var old := settings.profile.scan_interval_s
	settings.profile.scan_interval_s = 2.4
	var list := PedalScanList.new()
	assert_eq(list.scan_interval_s, 2.4, "the profile's scan interval")
	list.free()
	settings.profile.scan_interval_s = old


func test_hint_never_offers_coast_in_erg() -> void:
	_list.set_items(_items(2))
	var hint := _list.find_child("Hint", false, false) as Label
	assert_not_null(hint)
	assert_eq(hint.text, tr("UI_SCAN_HINT"))
	_list.set_local_mode(Wl.ERG)
	assert_eq(hint.text, tr("UI_SCAN_HINT_ERG"))
	_list.erg_auto_confirm = true
	_list.tick(DT)
	assert_string_contains(hint.text, "7", "the auto-pick countdown (6.4 s)")


func test_auto_confirm_left_counts_down() -> void:
	_list.erg_auto_confirm = true
	_list.set_items(_items(2))
	_run(2.0)
	assert_almost_eq(_list.auto_confirm_left_s(), 4.4, 1e-4)


# --- router -------------------------------------------------------------------------------------

func test_listens_to_the_router_menu_input() -> void:
	var bus: WlEventBus = autofree(WlEventBus.new())
	var router := WlInputRouter.new()
	router.bus = bus
	router.load_on_ready = false
	add_child_autofree(router)
	var list := PedalScanList.new()
	list.router = router
	list.real_time = false
	list.sounds = false
	add_child_autofree(list)
	watch_signals(list)
	list.set_items(_items(3))
	router.inject_action(&"down")
	assert_eq(list.highlighted(), 1)
	router.inject_gesture(Wl.G_SURGE)
	assert_eq(get_signal_parameters(list, "item_picked"), [1, "item1", "surge"])
	router.inject_action(&"confirm")
	assert_eq(get_signal_parameters(list, "item_picked"), [1, "item1", "action"])
	router.inject_gesture(Wl.G_COAST)
	assert_signal_emit_count(list, "backed_out", 1)
	list.visible = false
	router.inject_action(&"confirm")
	assert_signal_emit_count(list, "item_picked", 2, "a hidden list ignores input")
	list.visible = true
	list.listen_to_input = false
	router.inject_action(&"confirm")
	assert_signal_emit_count(list, "item_picked", 2, "listen_to_input off")


## A list taken out of the tree and put back (a menu stack popping back to it) listens again.
func test_relistens_after_leaving_and_reentering_the_tree() -> void:
	var bus: WlEventBus = autofree(WlEventBus.new())
	var router := WlInputRouter.new()
	router.bus = bus
	router.load_on_ready = false
	add_child_autofree(router)
	var list := PedalScanList.new()
	list.router = router
	list.real_time = false
	list.sounds = false
	add_child_autofree(list)
	watch_signals(list)
	list.set_items(_items(3))
	remove_child(list)
	router.inject_action(&"confirm")
	assert_signal_not_emitted(list, "item_picked", "out of the tree: deaf")
	add_child(list)
	router.inject_action(&"down")
	router.inject_action(&"confirm")
	assert_eq(get_signal_parameters(list, "item_picked"), [1, "item1", "action"], "back in the tree: listening")


func test_router_coast_in_erg_never_backs_out() -> void:
	var bus: WlEventBus = autofree(WlEventBus.new())
	var router := WlInputRouter.new()
	router.bus = bus
	router.load_on_ready = false
	add_child_autofree(router)
	var rider: FakeRider = autofree(FakeRider.new())
	rider.fake_mode = Wl.ERG
	router.attach_rider(rider)
	var list := PedalScanList.new()
	list.router = router
	list.real_time = false
	list.sounds = false
	add_child_autofree(list)
	watch_signals(list)
	list.set_items(_items(2))
	router.inject_gesture(Wl.G_COAST)
	assert_signal_not_emitted(list, "backed_out")


# --- view ----------------------------------------------------------------------------------------

func test_rows_are_big_and_readable() -> void:
	_list.set_items([{"id": 0, "text": "Ballista", "detail": "40 denarii"}, {"id": 1, "text": "Save"}])
	assert_eq(_list.row(0).name, "Item0")
	var text := _list.row(0).find_child("Text", true, false) as Label
	assert_not_null(text)
	assert_eq(text.text, "Ballista")
	assert_gte(text.label_settings.font_size, 32, "readable from 3 m")
	assert_not_null(_list.row(0).find_child("Detail", true, false))
	assert_null(_list.row(1).find_child("Detail", true, false))
	assert_null(_list.row(5))


func test_highlight_has_a_marker_not_only_a_color() -> void:
	_list.set_items(_items(2))
	var m0 := _list.row(0).find_child("Marker", true, false) as Label
	var m1 := _list.row(1).find_child("Marker", true, false) as Label
	assert_eq(m0.modulate.a, 1.0)
	assert_eq(m1.modulate.a, 0.0)
	_list.feed_action(&"down")
	assert_eq(m0.modulate.a, 0.0)
	assert_eq(m1.modulate.a, 1.0)


func test_set_items_again_rebuilds() -> void:
	_list.set_items(_items(3))
	_list.feed_action(&"down")
	_list.set_items(_items(2))
	assert_eq(_list.item_count(), 2)
	assert_eq(_list.highlighted(), 0)
	assert_null(_list.row(2))


func test_plain_values_become_items() -> void:
	_list.set_items(["a", "b"])
	_list.feed_action(&"confirm")
	assert_eq(get_signal_parameters(_list, "item_chosen"), [0, "a", false])


func test_sounds_on_do_not_error_headless() -> void:
	var list := PedalScanList.new()
	list.listen_to_input = false
	list.real_time = false
	add_child_autofree(list)
	list.set_items(_items(2))
	list.tick(1.6)
	list.feed_gesture(Wl.G_SURGE)
	list.feed_action(&"back")
	assert_eq(list.highlighted(), 1)

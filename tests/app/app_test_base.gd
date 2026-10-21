extends GutTest
## Shared setup for the app-shell tests (not collected by GUT: no test_ prefix): a fresh
## AppFixture of test doubles per test, screens opened headless with manual time, and helpers to
## drive pedal-scan menus.

const AppFixture := preload("res://tests/app/fakes/app_fixture.gd")
const FakeScanList := preload("res://tests/app/fakes/fake_scan_list.gd")
const FakeHost := preload("res://tests/app/fakes/fake_game_host.gd")
const FakeRider := preload("res://tests/app/fakes/fake_rider.gd")
const FakeNet := preload("res://tests/app/fakes/fake_net.gd")
const FakeRegistry := preload("res://tests/app/fakes/fake_registry.gd")
const MainScene := preload("res://src/app/main.gd")

var fx: AppFixture = null
var _opened: Array[Node] = []


func before_each() -> void:
	fx = AppFixture.new()


func after_each() -> void:
	for n in _opened:
		if is_instance_valid(n):
			if n is AppScreen:
				(n as AppScreen).leave()
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_opened.clear()
	fx.free_all()
	fx = null


## Open a screen headless with the fixture's services and manual time.
func open_screen(s: AppScreen, params: Dictionary = {}) -> AppScreen:
	s.services = fx.services
	s.auto_process = false
	add_child(s)
	_opened.append(s)
	s.enter(params)
	return s


## The main scene with the fixture's services (no boot side effects, manual time).
func open_main(config: AppScriptedConfig = null) -> Control:
	var m: Control = MainScene.new()
	m.set("services", fx.services)
	m.set("skip_boot", true)
	m.set("screens_auto_process", false)
	m.set("scripted_config", config if config != null else AppScriptedConfig.new())
	add_child(m)
	_opened.append(m)
	return m


func current_screen(m: Control) -> AppScreen:
	return m.get("screen") as AppScreen


func menu(s: AppScreen) -> FakeScanList:
	return s.active_menu() as FakeScanList


## Highlight the item with `id` in the screen's active menu and surge to pick it.
func surge_pick(s: AppScreen, id: Variant) -> void:
	var m := menu(s)
	assert_not_null(m, "an active menu")
	if m == null:
		return
	var i := m.index_of_id(id)
	assert_true(i >= 0, "menu has %s (has %s)" % [str(id), str(m.ids())])
	assert_false(m.is_disabled_id(id), "%s is enabled" % str(id))
	m.set_highlight(i)
	s.feed_gesture(Wl.G_SURGE)


## Confirm-pick (keyboard/controller) the item with `id`.
func confirm_pick(s: AppScreen, id: Variant) -> void:
	var m := menu(s)
	var i := m.index_of_id(id)
	assert_true(i >= 0, "menu has %s (has %s)" % [str(id), str(m.ids())])
	m.set_highlight(i)
	s.feed_action(&"confirm")


## Let the pedal-scan highlight move until `id` is highlighted (at most two cycles).
func scan_to(s: AppScreen, id: Variant) -> bool:
	var m := menu(s)
	var target := m.index_of_id(id)
	for _i in m.items.size() * 2 + 1:
		if m.highlighted() == target:
			return true
		s.tick(m.scan_interval_s)
	return m.highlighted() == target


func sample(t: float, power: float, cadence: float) -> TrainerSample:
	return TrainerSample.make(t, power, cadence)


## Font size of a Label (override or theme default).
func font_size(l: Label) -> int:
	return AppStyle.font_size_of(l)


func find_label(root: Node, label_name: String) -> Label:
	return root.find_child(label_name, true, false) as Label

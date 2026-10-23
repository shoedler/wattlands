extends "res://tests/app/app_test_base.gd"
## BRIEF 3.9: a form's menu column scrolls. The Profile screen is taller than a 1080p screen:
## whichever row the keyboard, a controller or the pedal scan highlights is fully on screen, the
## last rows (Autopilot, Back) can be reached and picked, and a page that fits never scrolls.

var _old_root_size: Vector2i = Vector2i.ZERO


func after_each() -> void:
	if _old_root_size != Vector2i.ZERO:
		get_tree().root.size = _old_root_size
		_old_root_size = Vector2i.ZERO
	super.after_each()


func _profile_at_1080p() -> AppProfileScreen:
	_old_root_size = get_tree().root.size
	get_tree().root.size = Vector2i(1920, 1080)
	fx.give_profile()
	var s := open_screen(AppProfileScreen.new()) as AppProfileScreen
	await wait_process_frames(2)
	assert_eq(s.get_viewport_rect(), Rect2(0, 0, 1920, 1080), "precondition: a 1080p screen")
	return s


## "" when `c` is fully inside the menu column's scroll view, else why not.
func _off_view(s: AppScreen, c: Control, what: String) -> String:
	var r := c.get_global_rect()
	var view := s.menu_scroll.get_global_rect()
	if r.position.y >= view.position.y - 0.5 and r.end.y <= view.end.y + 0.5:
		return ""
	return (
		"%s at y=%.0f..%.0f (view y=%.0f..%.0f)"
		% [what, r.position.y, r.end.y, view.position.y, view.end.y]
	)


func test_every_profile_row_is_on_screen_when_highlighted() -> void:
	var s: AppProfileScreen = await _profile_at_1080p()
	var m := menu(s)
	var holder := m.get_parent() as Control
	assert_gt(
		holder.size.y,
		s.menu_scroll.size.y,
		"precondition: the form (%.0f px) is taller than its view" % holder.size.y
	)
	var off: Array[String] = []
	for i in m.item_count():
		if not m.is_item_enabled(i):
			continue
		m.set_highlight(i)
		await wait_process_frames(2)
		var why := _off_view(s, m.row(i), "row %d (%s)" % [i, str(m.ids()[i])])
		if why != "":
			off.append(why)
	assert_eq(off, [] as Array[String], "every highlighted row is on screen")
	assert_eq(m.highlighted(), m.item_count() - 1, "the last row is Back")
	assert_gt(s.menu_scroll.scroll_vertical, 0, "the form scrolled to reach it")
	m.set_highlight(0)
	await wait_process_frames(2)
	assert_eq(s.menu_scroll.scroll_vertical, 0, "and back up to the name")


func test_the_keyboard_walks_down_to_the_last_row_and_picks_it() -> void:
	var s: AppProfileScreen = await _profile_at_1080p()
	var m := menu(s)
	for _i in m.item_count() - 2:
		s.feed_action(&"down")
	await wait_process_frames(2)
	assert_eq(m.ids()[m.highlighted()], "autopilot", "the last field before Back")
	assert_eq(_off_view(s, m.row(m.highlighted()), "Autopilot"), "")
	s.feed_action(&"down")
	await wait_process_frames(2)
	assert_eq(m.ids()[m.highlighted()], "back")
	assert_eq(_off_view(s, m.row(m.highlighted()), "Back"), "")
	var left: Array = []
	s.leaving.connect(func(state: String) -> void: left.append(state))
	s.feed_action(&"confirm")
	assert_eq(left, ["title"])


func test_the_scan_reaches_the_last_rows_too() -> void:
	var s: AppProfileScreen = await _profile_at_1080p()
	var m := menu(s)
	assert_true(m.scanning)
	var seen_autopilot := false
	for _i in m.item_count() * 2:
		s.tick(m.scan_interval_s)
		await wait_process_frames(2)
		var why := _off_view(s, m.row(m.highlighted()), "row %d" % m.highlighted())
		assert_eq(why, "", "the scanned row is on screen")
		seen_autopilot = seen_autopilot or m.ids()[m.highlighted()] == "autopilot"
	assert_true(seen_autopilot, "the scan visits the last field")

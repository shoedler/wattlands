extends GutTest
## assets/workout/kit.json is what the view codes against: it validates, its numbers agree with the
## rig, and every path resolves.


func _data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(WorkoutKit.PATH))


func test_the_committed_kit_validates() -> void:
	assert_eq(WorkoutKit.problems(_data()), [] as Array[String])


func test_the_kit_agrees_with_the_rig() -> void:
	var kit := WorkoutKit.shared()
	assert_eq(int(kit.rider["frames"]), WorkoutRig.CRANK_FRAMES)
	assert_eq(int(kit.data["wheel"]["frames"]), WorkoutRig.WHEEL_FRAMES)
	assert_eq(float(kit.data["wheel"]["radius"]), WorkoutRig.WHEEL_RADIUS_PX)
	assert_eq((kit.rider["near_pedal"] as Array).size(), WorkoutRig.CRANK_FRAMES)
	assert_eq(WorkoutKit.vec(kit.data["base"]), Vector2i(WorkoutArt.W, WorkoutArt.H))


func test_the_pose_rows_fit_the_sheet() -> void:
	var kit := WorkoutKit.shared()
	var cell := WorkoutKit.vec(kit.rider["cell"])
	var slots: Array = kit.rider["slots"]
	assert_eq(slots.size(), Wl.MAX_SLOTS)
	var sheet := kit.texture(slots[0])
	assert_eq(sheet.get_width(), cell.x * int(kit.rider["cols"]))
	for pose in WorkoutRig.POSE_NAMES.size():
		var last := WorkoutRig.cell_of(pose, WorkoutRig.CRANK_FRAMES - 1, kit.rider["pose_rows"])
		assert_lte((last.y + 1) * cell.y, sheet.get_height(), WorkoutRig.POSE_NAMES[pose])
		assert_lte((last.x + 1) * cell.x, sheet.get_width(), WorkoutRig.POSE_NAMES[pose])


func test_the_slot_colours_are_the_platforms() -> void:
	var colours: Array = WorkoutKit.shared().rider["slot_colors"]
	assert_eq(colours.size(), Wl.SLOT_COLORS.size())
	for i in colours.size():
		assert_eq(Color(str(colours[i])), Wl.SLOT_COLORS[i], "slot colour %d" % i)


func test_every_path_resolves_and_every_pose_has_a_mouth() -> void:
	var kit := WorkoutKit.shared()
	for pose_name in WorkoutRig.POSE_NAMES:
		assert_true((kit.rider["mouth_by_pose"] as Dictionary).has(pose_name), pose_name)
	for p: Dictionary in kit.data["planes"]:
		if p.has("path"):
			assert_not_null(kit.texture(p["path"]), str(p["name"]))
	for key: String in WorkoutKit.PROP_NAMES:
		assert_not_null(kit.texture(kit.props[key]["path"]), key)
	assert_not_null(kit.texture(kit.data["lut"]["path"]))


func test_a_missing_key_or_file_is_a_problem() -> void:
	var d := _data()
	d.erase("road")
	assert_eq(WorkoutKit.problems(d), ["missing key road"] as Array[String])
	d = _data()
	(d["rider"] as Dictionary).erase("origin")
	assert_true(WorkoutKit.problems(d).has("missing key rider.origin"))
	d = _data()
	(d["props"] as Dictionary).erase("crowd")
	assert_true(WorkoutKit.problems(d).has("missing key props.crowd"))
	d = _data()
	(d["planes"] as Array).pop_front()
	assert_true(WorkoutKit.problems(d).has("missing plane sky"))
	d = _data()
	d["sun"]["path"] = "res://assets/workout/world/no_such.png"
	assert_true(WorkoutKit.problems(d).has("missing file res://assets/workout/world/no_such.png"))
	d = _data()
	(d["tod"] as Array).pop_back()
	assert_eq(WorkoutKit.problems(d).size(), 1, "a short day")


func test_load_from_reports_a_broken_file() -> void:
	var kit := WorkoutKit.load_from("res://assets/workout/no_kit.json")
	assert_push_error("cannot read")
	assert_eq(kit.data, {})

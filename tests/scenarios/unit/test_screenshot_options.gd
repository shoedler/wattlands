extends GutTest
## QaScreenshotOptions (tools/qa/screenshot_options.gd): the flags tools/qa/screenshot_main.gd
## reads, the split between screenshot flags and run_game_sim flags, and the PNG names.


func _parse(args: Array) -> Dictionary:
	return QaScreenshotOptions.parse(PackedStringArray(args))


func test_game_mode() -> void:
	var o := _parse(["--mock-trainer=erg", "--game=siege", "--content=short", "--at=600,60,360,60", "--players=4", "--bots=0", "--rider=zero", "--seed=3"])
	assert_eq(o["error"], "")
	assert_eq(o["mode"], "game")
	assert_eq(o["at"], [60.0, 360.0, 600.0], "sorted and unique")
	assert_eq(o["game"], "siege")
	assert_eq(o["content"], "short")
	assert_eq(o["players"], 4)
	assert_eq(o["mock_trainer"], "erg")
	assert_eq(o["out"], "build/screenshots/siege")
	assert_eq(Array(o["sim_args"]), ["--game=siege", "--content=short", "--players=4", "--bots=0", "--rider=zero", "--seed=3"], "screenshot flags never reach GameSimRunner")


func test_repeated_riders_keep_their_order() -> void:
	var o := _parse(["--game=tank", "--at=1", "--rider=erg", "--rider=erg+cadence_drop:rpm=30,at_phase=4,after_s=20,for_s=30"])
	assert_eq(Array(o["sim_args"]), ["--game=tank", "--rider=erg", "--rider=erg+cadence_drop:rpm=30,at_phase=4,after_s=20,for_s=30"])


func test_game_needs_at() -> void:
	assert_string_contains(_parse(["--game=siege"])["error"], "--game needs --at")


func test_bad_values() -> void:
	assert_string_contains(_parse(["--game=g", "--at=-5"])["error"], "--at needs")
	assert_string_contains(_parse(["--game=g", "--at=x"])["error"], "--at needs")
	assert_string_contains(_parse(["--game=g", "--at=1", "--players=0"])["error"], "--players")
	assert_string_contains(_parse(["--scene=res://a.tscn", "--frames=0"])["error"], "--frames")
	assert_string_contains(_parse(["--game=g", "--at=1", "--settle=-1"])["error"], "--settle")
	assert_string_contains(_parse(["--scene=demo.tscn"])["error"], "res://")
	assert_string_contains(_parse(["--app-screen=settings"])["error"], "--app-screen")
	assert_string_contains(_parse(["--game=g", "--at=1", "--out="])["error"], "--out needs")
	assert_string_contains(_parse(["stray"])["error"], "unexpected argument")


func test_exactly_one_mode() -> void:
	assert_string_contains(_parse([])["error"], "exactly one of")
	assert_string_contains(_parse(["--game=g", "--at=1", "--app-screen=title"])["error"], "exactly one of")


func test_scene_mode() -> void:
	var o := _parse(["--scene=res://addons/wattlands/world2d/demo.tscn", "--frames=12"])
	assert_eq(o["error"], "")
	assert_eq(o["mode"], "scene")
	assert_eq(o["frames"], 12)
	assert_eq(o["out"], "build/screenshots/scenes")


func test_app_mode() -> void:
	var o := _parse(["--app-screen=lobby", "--app-game=tank", "--screenshot-dir=build/shots"])
	assert_eq(o["error"], "")
	assert_eq(o["mode"], "app")
	assert_eq(o["app_screen"], "lobby")
	assert_eq(o["app_game"], "tank")
	assert_eq(o["out"], "build/shots")
	assert_eq(o["frames"], QaScreenshotOptions.DEFAULT_FRAMES)


func test_file_names() -> void:
	assert_eq(QaScreenshotOptions.file_name("siege", "short", 4, 360.0), "siege_short_4p_360s.png")
	assert_eq(QaScreenshotOptions.file_name("fishing", "free_30", 2, 90.5), "fishing_free_30_2p_90.5s.png")
	assert_eq(QaScreenshotOptions.format_seconds(0.25), "0.25")
	assert_eq(QaScreenshotOptions.format_seconds(12.0), "12")
	assert_eq(QaScreenshotOptions.scene_file_name("res://addons/wattlands/world2d/demo.tscn"), "world2d_demo.png")
	assert_eq(QaScreenshotOptions.scene_file_name("res://addons/wattlands/world3d/demo.tscn"), "world3d_demo.png")
	assert_eq(QaScreenshotOptions.app_file_name("picker"), "app_picker.png")


func test_output_dirs_resolve_against_the_project() -> void:
	var root := ProjectSettings.globalize_path("res://").replace("\\", "/")
	assert_eq(QaScreenshotOptions.resolve_dir("build/screenshots/siege"), root.path_join("build/screenshots/siege").simplify_path())
	assert_eq(QaScreenshotOptions.resolve_dir("C:\\shots"), "C:/shots")
	assert_eq(QaScreenshotOptions.default_out("game", "tank"), "build/screenshots/tank")
	assert_eq(QaScreenshotOptions.default_out("app", ""), "build/screenshots/app")

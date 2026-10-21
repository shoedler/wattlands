extends GutTest
## WlSettings' default relay URL (W4fin, DoD 2): the project setting
## wattlands/net/default_relay_url (an exported build sets it in override.cfg) is the default;
## a relay_url the rider chose in settings.json wins over it and --relay=<url> wins over both.

const Util := preload("res://tests/core/helpers/core_test_util.gd")
const BUILT_IN := "ws://localhost:8787/v1"
const BUILD_URL := "ws://192.0.2.10:8787/v1"
const NEXT_BUILD_URL := "wss://relay.example.test/v1"
const CHOSEN_URL := "ws://10.0.0.9:8787/v1"

var _dirs: Array[String] = []
var _bus: WlEventBus = null


func before_each() -> void:
	CmdLine.set_args(PackedStringArray(), true)
	Paths.set_override(_temp())
	_bus = WlEventBus.new()
	autofree(_bus)
	_set_build_url(null)


func after_each() -> void:
	_set_build_url(null)
	Paths.set_override("")
	CmdLine.set_args(PackedStringArray(), false)
	for d in _dirs:
		Util.remove_tree(d)
	_dirs.clear()


func _temp() -> String:
	var d := Paths.make_temp_dir("wattlands_relay_default_test")
	_dirs.append(d)
	return d


func _make() -> WlSettings:
	var s := WlSettings.new()
	s.bus = _bus
	autofree(s)
	return s


## Set (or with null remove) the project setting, as override.cfg does at startup.
func _set_build_url(v: Variant) -> void:
	ProjectSettings.set_setting(WlSettings.DEFAULT_RELAY_SETTING, v)


func _saved() -> Dictionary:
	return Util.read_json(Paths.settings_path()) as Dictionary


func test_setting_name_and_built_in_default() -> void:
	assert_eq(WlSettings.DEFAULT_RELAY_SETTING, "wattlands/net/default_relay_url")
	assert_eq(WlSettings.DEFAULTS["relay_url"], BUILT_IN, "the shipped default stays localhost")
	assert_false(
		ProjectSettings.has_setting(WlSettings.DEFAULT_RELAY_SETTING),
		"project.godot leaves it unset"
	)
	assert_eq(WlSettings.default_relay_url(), BUILT_IN)
	var s := _make()
	s.load_all()
	assert_eq(s.relay_url(), BUILT_IN)
	assert_eq(s.get_value("relay_url"), BUILT_IN)


func test_default_follows_the_project_setting() -> void:
	_set_build_url(BUILD_URL)
	assert_eq(WlSettings.default_relay_url(), BUILD_URL)
	var s := _make()
	assert_eq(s.relay_url(), BUILD_URL, "before load_all too")
	s.load_all()
	assert_eq(s.relay_url(), BUILD_URL)
	assert_eq(s.get_value("relay_url"), BUILD_URL)
	assert_false(s.is_overridden("relay_url"))
	assert_false(FileAccess.file_exists(Paths.settings_path()), "loading writes nothing")
	assert_push_warning_count(0)


func test_a_joining_client_with_default_settings_uses_the_build_relay() -> void:
	# DoD 2: with no Settings change and no --relay, the relay transport a client opens to join
	# by code (NetSession uses RelayTransport.default_url) goes to the build's relay.
	var autoload := get_node_or_null("/root/Settings") as WlSettings
	assert_not_null(autoload, "the Settings autoload")
	assert_eq(RelayTransport.default_url(self), BUILT_IN)
	_set_build_url(BUILD_URL)
	assert_eq(autoload.relay_url(), BUILD_URL, "read live, no reload needed")
	assert_eq(RelayTransport.default_url(self), BUILD_URL)
	CmdLine.set_args(PackedStringArray(["--relay=ws://127.0.0.1:9999/v1"]))
	assert_eq(RelayTransport.default_url(self), "ws://127.0.0.1:9999/v1", "--relay wins")
	CmdLine.set_args(PackedStringArray())
	_set_build_url(null)
	assert_eq(RelayTransport.default_url(self), BUILT_IN)


func test_project_setting_is_trimmed_and_accepts_wss_ipv6_and_ports() -> void:
	for pair: Array in [
		["  " + BUILD_URL + "  ", BUILD_URL],
		["wss://relay.example.test", "wss://relay.example.test"],
		["ws://[::1]:8787/v1", "ws://[::1]:8787/v1"],
		["ws://relay.example.test:8787/v1?x=1", "ws://relay.example.test:8787/v1?x=1"],
	]:
		_set_build_url(pair[0])
		var s := _make()
		s.load_all()
		assert_eq(s.relay_url(), pair[1], str(pair[0]))
	assert_push_warning_count(0)


func test_an_empty_project_setting_is_the_built_in_default() -> void:
	_set_build_url("")
	var s := _make()
	s.load_all()
	assert_eq(s.relay_url(), BUILT_IN)
	assert_push_warning_count(0, "empty means unset")


func test_an_unusable_project_setting_falls_back_with_a_warning() -> void:
	var bad: Array = [
		"http://relay.example.test/v1",
		"relay.example.test:8787",
		"ws://",
		"ws:///v1",
		"wss://:8787/v1",
		"ws://bad host/v1",
		'ws://a"b/v1',
		"ws://a\\b/v1",
		"ws://a\nb/v1",
		42,
	]
	for v: Variant in bad:
		_set_build_url(v)
		assert_eq(WlSettings.default_relay_url(), BUILT_IN, str(v))
		var s := _make()
		s.load_all()
		assert_eq(s.relay_url(), BUILT_IN, str(v))
	assert_push_warning_count(bad.size(), "one warning per load_all, none from _init")


func test_the_warning_names_the_setting_and_the_value() -> void:
	_set_build_url("http://relay.example.test/v1")
	var s := _make()
	s.load_all()
	assert_eq(s.relay_url(), BUILT_IN)
	assert_push_warning(
		(
			'ignoring wattlands/net/default_relay_url "http://relay.example.test/v1"'
			+ " (not a ws:// or wss:// URL with a host); using ws://localhost:8787/v1"
		)
	)


func test_a_saved_choice_wins_over_the_project_setting() -> void:
	_set_build_url(BUILD_URL)
	var s := _make()
	s.load_all()
	s.set_value("relay_url", CHOSEN_URL)
	assert_eq(s.relay_url(), CHOSEN_URL)
	assert_eq(_saved().get("relay_url"), CHOSEN_URL)
	assert_eq(_saved().get("relay_url_custom"), true)
	_set_build_url(NEXT_BUILD_URL)
	var t := _make()
	t.load_all()
	assert_eq(t.relay_url(), CHOSEN_URL, "a new build default never replaces the rider's choice")
	assert_eq(t.get_value("relay_url_custom"), null, "the marker is not a setting")
	t.set_value("locale", "de")
	assert_eq(_saved().get("relay_url"), CHOSEN_URL, "kept on the next save")
	assert_eq(_saved().get("relay_url_custom"), true)


func test_a_chosen_localhost_survives_a_build_default_elsewhere() -> void:
	_set_build_url(BUILD_URL)
	var s := _make()
	s.load_all()
	s.set_value("relay_url", BUILT_IN)
	var t := _make()
	t.load_all()
	assert_eq(t.relay_url(), BUILT_IN, "relay_url_custom marks it as chosen")


func test_the_marker_cannot_be_set() -> void:
	_set_build_url(BUILD_URL)
	var s := _make()
	s.load_all()
	s.set_value("relay_url_custom", true)
	assert_push_error("relay_url_custom is kept by Settings itself")
	assert_eq(s.get_value("relay_url_custom"), null)
	assert_eq(s.relay_url(), BUILD_URL)
	assert_false(FileAccess.file_exists(Paths.settings_path()), "nothing was saved")


func test_relay_flag_wins_over_both() -> void:
	_set_build_url(BUILD_URL)
	var s := _make()
	s.load_all()
	CmdLine.set_args(PackedStringArray(["--relay=ws://127.0.0.1:9999/v1"]))
	assert_eq(s.relay_url(), "ws://127.0.0.1:9999/v1", "over the build default")
	s.set_value("relay_url", CHOSEN_URL)
	assert_eq(s.relay_url(), "ws://127.0.0.1:9999/v1", "over the rider's choice")
	assert_true(s.is_overridden("relay_url"))
	assert_false(Util.read_text(Paths.settings_path()).contains("9999"), "never saved")
	CmdLine.set_args(PackedStringArray())
	assert_eq(s.relay_url(), CHOSEN_URL)


func test_the_default_is_never_saved_so_a_new_build_default_applies() -> void:
	_set_build_url(BUILD_URL)
	var s := _make()
	s.load_all()
	s.set_value("locale", "fr")
	assert_false(_saved().has("relay_url"), "the default is not written")
	assert_false(_saved().has("relay_url_custom"))
	_set_build_url(NEXT_BUILD_URL)
	var t := _make()
	t.load_all()
	assert_eq(t.relay_url(), NEXT_BUILD_URL)
	assert_eq(t.get_value("locale"), "fr")


func test_clearing_or_choosing_the_default_follows_it_again() -> void:
	_set_build_url(BUILD_URL)
	var s := _make()
	s.load_all()
	var seen: Array[String] = []
	s.changed.connect(func(k: String) -> void: seen.append(k))
	s.set_value("relay_url", CHOSEN_URL)
	s.set_value("relay_url", "   ")
	assert_eq(s.relay_url(), BUILD_URL, "blank means the default")
	assert_false(_saved().has("relay_url"))
	s.set_value("relay_url", "")
	assert_eq(seen, ["relay_url", "relay_url"], "no change, no signal")
	s.set_value("relay_url", CHOSEN_URL)
	s.set_value("relay_url", " " + BUILD_URL + " ")
	assert_eq(s.relay_url(), BUILD_URL)
	assert_false(_saved().has("relay_url"), "the default's own value is not a choice")
	_set_build_url(NEXT_BUILD_URL)
	var t := _make()
	t.load_all()
	assert_eq(t.relay_url(), NEXT_BUILD_URL)


func test_saved_values_from_earlier_builds() -> void:
	_set_build_url(BUILD_URL)
	Util.write_text(Paths.settings_path(), JSON.stringify({"relay_url": BUILT_IN, "locale": "de"}))
	var s := _make()
	s.load_all()
	assert_eq(s.relay_url(), BUILD_URL, "an auto-written localhost follows the build default")
	assert_eq(s.get_value("locale"), "de")
	Util.write_text(Paths.settings_path(), JSON.stringify({"relay_url": CHOSEN_URL}))
	s.load_all()
	assert_eq(s.relay_url(), CHOSEN_URL, "any other saved URL was typed by the rider")
	Util.write_text(Paths.settings_path(), JSON.stringify({"relay_url": BUILD_URL}))
	s.load_all()
	assert_eq(s.relay_url(), BUILD_URL)
	s.set_value("locale", "it")
	assert_false(_saved().has("relay_url"), "a saved default follows the default")
	assert_push_warning_count(0)

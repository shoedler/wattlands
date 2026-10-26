extends GutTest
## GameHost and the help overlay (v0.3.0): config.auto_help opens a game's HudSpec.help once
## per profile and game (HelpSeen); the `help` action toggles it and never reaches the game;
## while it is open `back` and `confirm` close it and are consumed; the game keeps running.

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")
const FxGame := preload("res://tests/fixtures/games/fx_game.gd")

var _root: Node = null
var _tmp: Array[String] = []
var _profile_dir: String = ""


class FakeRouter:
	extends Node
	var actions: Array[StringName] = []

	func take_actions() -> Array[StringName]:
		var out := actions
		actions = []
		return out

	func take_gestures() -> Array[StringName]:
		return [] as Array[StringName]


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)
	_profile_dir = Paths.make_temp_dir("wl_help_profile")
	Paths.set_override(_profile_dir)


func after_each() -> void:
	Paths.set_override("")
	_tmp.append(_profile_dir)
	for d in _tmp:
		Kit.remove_tree(d)
	_tmp.clear()


func _help() -> Array[Dictionary]:
	return [{"text": "Pedal to reel", "at": Vector2(320, 180), "arrow_to": Vector2(100, 100)}]


func _session(help: Array[Dictionary], extra: Dictionary = {}) -> Dictionary:
	var router := FakeRouter.new()
	_root.add_child(router)
	var game: GameModule = FxGame.new()
	game.set("help_entries", help)
	game.set("keep_frames", true)
	var cfg := {"headless": false, "input_router": router, "game": game, "auto_help": true}
	cfg.merge(extra, true)
	var b := Kit.solo(_root, "tiny", cfg)
	_tmp.append(str(b["tmp"]))
	b["router"] = router
	assert_eq(b["err"], "")
	return b


func _host(b: Dictionary) -> GameHost:
	return b["host"]


func _actions_seen(b: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for c: Dictionary in _host(b).game.get("local_intent_calls"):
		out.append_array(c["actions"])
	return out


func _press(b: Dictionary, action: StringName) -> void:
	(b["router"] as FakeRouter).actions.append(action)
	Kit.step(b, 1)


func test_first_session_opens_the_help_once() -> void:
	var b := _session(_help())
	var hud := _host(b).hud_layer()
	assert_true(hud.help_visible(), "the first session of the game opens it")
	assert_true(HelpSeen.has("fx_solo"))
	_host(b).end_session("timeout")
	var b2 := _session(_help())
	assert_false(_host(b2).hud_layer().help_visible(), "never again on this profile")


func test_auto_help_off_and_games_without_help() -> void:
	var b := _session(_help(), {"auto_help": false})
	assert_false(_host(b).hud_layer().help_visible())
	assert_false(HelpSeen.has("fx_solo"))
	var b2 := _session([])
	assert_false(_host(b2).hud_layer().help_visible())
	assert_false(HelpSeen.has("fx_solo"), "help a game adds later still opens once")


func test_confirm_and_back_close_it_and_are_consumed() -> void:
	var b := _session(_help())
	var host := _host(b)
	host.start()
	Kit.step(b, 2)
	var steps_before := int(host.game.get("steps"))
	assert_true(host.hud_layer().help_visible())
	_press(b, &"confirm")
	assert_false(host.hud_layer().help_visible())
	assert_gt(int(host.game.get("steps")), steps_before, "the game kept running")
	_press(b, &"help")
	assert_true(host.hud_layer().help_visible(), "F1 opens it again")
	_press(b, &"back")
	assert_false(host.hud_layer().help_visible())
	assert_eq(_actions_seen(b), [] as Array[StringName], "the game saw none of them")
	_press(b, &"confirm")
	assert_eq(_actions_seen(b), [&"confirm"] as Array[StringName], "closed: confirm is the game's")


func test_help_toggles_and_never_reaches_the_game() -> void:
	var b := _session(_help(), {"auto_help": false})
	var host := _host(b)
	host.start()
	Kit.step(b, 2)
	_press(b, &"help")
	assert_true(host.hud_layer().help_visible())
	_press(b, &"ability_1")
	assert_true(host.hud_layer().help_visible(), "other actions pass under the overlay")
	_press(b, &"help")
	assert_false(host.hud_layer().help_visible())
	assert_eq(_actions_seen(b), [&"ability_1"] as Array[StringName])


func test_no_help_toast() -> void:
	var b := _session([])
	var host := _host(b)
	host.start()
	Kit.step(b, 2)
	_press(b, &"help")
	assert_false(host.hud_layer().help_visible())
	assert_has(host.hud_layer().toasts().texts(), tr("UI_HELP_NONE"))


func test_headless_drops_help() -> void:
	var router := FakeRouter.new()
	_root.add_child(router)
	var b := Kit.solo(_root, "tiny", {"input_router": router})
	_tmp.append(str(b["tmp"]))
	var host := _host(b)
	assert_null(host.hud_layer())
	host.start()
	Kit.step(b, 2)
	router.actions.append(&"help")
	router.actions.append(&"confirm")
	Kit.step(b, 1)
	assert_eq(_actions_seen(b), [&"confirm"] as Array[StringName])

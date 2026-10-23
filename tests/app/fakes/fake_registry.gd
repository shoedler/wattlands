extends WlGameRegistry
## Test double of GameRegistry with fixture manifests. first_run_game() follows BRIEF 3.6
## (highest first_run_priority; ties go to "workout", then the lowest id) so tests can install a
## game with a higher priority and watch the first run change, without hard-coding "workout".

const FakeModule := preload("res://tests/app/fakes/fake_module.gd")

var manifests: Dictionary = {}
var instantiated: int = 0


func add_fixture(m: Dictionary) -> void:
	manifests[str(m["id"])] = m


func remove_game(id: String) -> void:
	manifests.erase(id)


func scan(_root: String = GAMES_ROOT) -> void:
	pass


func games() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ids():
		out.append(manifests[id])
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("title", "")) < str(b.get("title", ""))
	)
	return out


func ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in manifests.keys():
		out.append(str(k))
	out.sort()
	return out


func has_game(id: String) -> bool:
	return manifests.has(id)


func manifest(id: String) -> Dictionary:
	return manifests.get(id, {})


func validate_manifest(_m: Dictionary, _path: String = "") -> String:
	return ""


func instantiate(id: String) -> GameModule:
	if not manifests.has(id):
		return null
	instantiated += 1
	return FakeModule.new()


func first_run_game() -> String:
	var best := ""
	var best_p := -2147483648
	for id: String in ids():
		var p := int(manifests[id].get("first_run_priority", 0))
		if best == "" or p > best_p:
			best = id
			best_p = p
		elif p == best_p:
			if id == "workout" or (best != "workout" and id < best):
				best = id
	return best


func resolve_options(id: String, values: Dictionary, per_player: bool = false) -> Dictionary:
	var m := manifest(id)
	var out: Dictionary = {}
	for e: Variant in m.get("player_options" if per_player else "options", []):
		var oid := str((e as Dictionary).get("id", ""))
		out[oid] = values.get(oid, (e as Dictionary).get("default"))
	return out


## The fixture games: workout (priority 0, bots, every option type), siege (-1, a per-rider
## int option), tank (-1, a toggle) and, when asked, fishing (10, the first-run game).
static func workout() -> Dictionary:
	return {
		"id": "workout",
		"title": "Workout",
		"summary": "Group intervals",
		"version": "1.0.0",
		"min_players": 1,
		"max_players": 8,
		"bots": true,
		"presentation": "2d",
		"pixel_base": [640, 360],
		"entry": "res://src/games/workout/workout_game.gd",
		"contents": ["easy_30", "sweet_spot", "e2e"],
		"default_content": "easy_30",
		"e2e_content": "e2e",
		"zero_input_content": "easy_30",
		"first_run_priority": 0,
		"options":
		[
			{"id": "music", "type": "toggle", "default": true},
			{"id": "laps", "type": "int", "default": 2, "min": 1, "max": 4},
			{
				"id": "theme",
				"type": "choice",
				"default": "day",
				"choices":
				[
					{"value": "day", "label": "WORKOUT_THEME_DAY"},
					{"value": "night", "label": "WORKOUT_THEME_NIGHT"}
				]
			},
		],
		"player_options":
		[
			{"id": "offset", "type": "int", "default": 0, "min": -10, "max": 5, "step": 1},
		],
	}


static func siege() -> Dictionary:
	return {
		"id": "siege",
		"title": "Castellum Rotae",
		"summary": "Hold the fort",
		"version": "0.3.0",
		"min_players": 1,
		"max_players": 4,
		"bots": true,
		"presentation": "3d",
		"entry": "res://src/games/siege/siege_game.gd",
		"contents": ["short", "drill"],
		"default_content": "short",
		"e2e_content": "drill",
		"zero_input_content": "short",
		"first_run_priority": -1,
		"options": [],
		"player_options":
		[{"id": "wave_offset", "type": "int", "default": 0, "min": -10, "max": 5, "step": 1}],
	}


static func tank() -> Dictionary:
	return {
		"id": "tank",
		"title": "Diesel Domestiques",
		"summary": "Crew the beast",
		"version": "0.2.0",
		"min_players": 1,
		"max_players": 3,
		"bots": false,
		"presentation": "2d",
		"pixel_base": [640, 360],
		"entry": "res://src/games/tank/tank_game.gd",
		"contents": ["ashfall_road", "drill"],
		"default_content": "ashfall_road",
		"e2e_content": "drill",
		"zero_input_content": "ashfall_road",
		"first_run_priority": -1,
		"options": [{"id": "rotation", "type": "toggle", "default": true}],
		"player_options": [],
		"picker_image": "res://assets/tank/sprites/picker_card.png",
	}


static func fishing() -> Dictionary:
	return {
		"id": "fishing",
		"title": "Turbo Reel",
		"summary": "Reel them in",
		"version": "0.1.0",
		"min_players": 1,
		"max_players": 4,
		"bots": false,
		"presentation": "2d",
		"pixel_base": [640, 360],
		"entry": "res://src/games/fishing/fishing_game.gd",
		"contents": ["free_30", "e2e_2min"],
		"default_content": "free_30",
		"e2e_content": "e2e_2min",
		"zero_input_content": "free_30",
		"first_run_priority": 10,
		"options": [],
		"player_options":
		[
			{"id": "reel_pct", "type": "int", "default": 60, "min": 50, "max": 70, "step": 5},
			{"id": "relaxed_band", "type": "toggle", "default": false},
		],
		"picker_image": "res://src/app/icon.svg",
	}

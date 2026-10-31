extends GutTest
## AudioBank (SPEC_AUDIO 1.5): one audio.json per game, validated at load, every error naming its key path.

const BANK := "res://tests/audio/fixtures/bank_min.json"


func _doc() -> Dictionary:
	return {
		"schema": 1.0,
		"game": "g",
		"sounds":
		{
			"st": {"rate": 22050.0, "ch": 1.0, "locked": true},
			"lp": {"rate": 22050.0, "ch": 1.0, "loop": true},
			"bed": {"rate": 11025.0, "ch": 2.0, "loop": true},
			"hit": {"rate": 22050.0, "ch": 1.0},
		},
		"machines":
		{
			"m":
			{
				"bus": "Machines",
				"events": [{"at": [0.0, 0.5], "sound": "st"}],
				"loops": [{"sound": "lp"}],
			}
		},
		"loops": {"l": {"bus": "Sfx", "layers": [{"sound": "lp"}]}},
		"beds":
		{"b": {"layers": [{"sound": "bed"}], "spots": [{"sound": "hit", "gap_s": [1.0, 2.0]}]}},
		"cues":
		{
			"c":
			{
				"hits": [{"sound": "hit", "bus": "Sfx"}],
				"duck": [{"bus": "Machines", "db": -4.0, "attack_s": 0.01, "release_s": 0.3}],
			}
		},
	}


func _assert_rejected(doc: Dictionary, needle: String) -> void:
	var errors := AudioBank.validate(doc)
	assert_gt(errors.size(), 0, needle)
	assert_string_contains(" | ".join(errors), needle)


func test_good_doc_passes() -> void:
	assert_eq(AudioBank.validate(_doc()), [] as Array[String])


func test_fixture_loads_without_any_wav() -> void:
	var bank := AudioBank.load_bank(BANK)
	assert_not_null(bank)
	assert_eq(bank.game_id, "bank_min")
	assert_eq(bank.dir, "res://tests/audio/fixtures")
	assert_eq(bank.variants("stroke"), 3)
	assert_eq(bank.variants("tick"), 1)
	assert_true(bank.is_locked("stroke"))
	assert_false(bank.is_locked("body"))
	assert_true(bank.machines.has("main"))
	assert_true(bank.beds.has("night"))
	assert_true(bank.cues.has("shot"))
	assert_true(bank.loops.has("drag_scream"))


func test_only_schema_game_and_sounds_are_required() -> void:
	var bank := AudioBank.from_dict({"schema": 1, "game": "_shared", "sounds": {}}, "res://x")
	assert_not_null(bank)
	assert_eq(bank.machines, {})
	assert_eq(int(bank.mix["max_loop_players"]), 24, "mix defaults")


func test_unknown_schema() -> void:
	var doc := _doc()
	doc["schema"] = 2.0
	_assert_rejected(doc, "schema")
	doc.erase("schema")
	_assert_rejected(doc, "schema")


func test_machine_event_sound_missing_or_not_locked() -> void:
	var doc := _doc()
	doc["machines"]["m"]["events"][0]["sound"] = "nope"
	_assert_rejected(doc, "machines.m.events[0].sound")
	doc = _doc()
	doc["machines"]["m"]["events"][0]["sound"] = "hit"
	_assert_rejected(doc, "is not locked")


func test_at_outside_the_revolution() -> void:
	for at: float in [-0.1, 1.0, 1.5]:
		var doc := _doc()
		doc["machines"]["m"]["events"][0]["at"] = [0.0, at]
		_assert_rejected(doc, "machines.m.events[0].at[1]")


func test_rate_and_channels() -> void:
	var doc := _doc()
	doc["sounds"]["hit"]["rate"] = 44100.0
	_assert_rejected(doc, "sounds.hit.rate")
	doc = _doc()
	doc["sounds"]["hit"]["ch"] = 3.0
	_assert_rejected(doc, "sounds.hit.ch")


func test_machine_event_on_a_stereo_sound() -> void:
	var doc := _doc()
	doc["sounds"]["st"]["ch"] = 2.0
	_assert_rejected(doc, "is stereo")


func test_locked_stays_pcm() -> void:
	var doc := _doc()
	doc["sounds"]["st"]["compress"] = "qoa"
	_assert_rejected(doc, "sounds.st.compress")


func test_unknown_bus() -> void:
	var doc := _doc()
	doc["machines"]["m"]["bus"] = "Nope"
	_assert_rejected(doc, "machines.m.bus: unknown bus")
	doc = _doc()
	doc["loops"]["l"]["bus"] = "Nope"
	_assert_rejected(doc, "loops.l.bus")
	doc = _doc()
	doc["cues"]["c"]["hits"][0]["bus"] = "Nope"
	_assert_rejected(doc, "cues.c.hits[0].bus")


## BRIEF 4.6's prompts own Master; a bank never plays on it, and nothing ducks UI or Master.
func test_master_and_ui_stay_clear() -> void:
	var doc := _doc()
	doc["cues"]["c"]["hits"][0]["bus"] = "Master"
	_assert_rejected(doc, "cues.c.hits[0].bus")
	doc = _doc()
	doc["cues"]["c"]["duck"][0]["bus"] = "Master"
	_assert_rejected(doc, "cues.c.duck[0].bus")
	doc = _doc()
	doc["cues"]["c"]["duck"][0]["bus"] = "UI"
	_assert_rejected(doc, "UI is never ducked")


func test_cue_loop_and_spot_name_real_sounds() -> void:
	var doc := _doc()
	doc["cues"]["c"]["hits"][0]["sound"] = "nope"
	_assert_rejected(doc, "cues.c.hits[0].sound")
	doc = _doc()
	doc["loops"]["l"]["layers"][0]["sound"] = "nope"
	_assert_rejected(doc, "loops.l.layers[0].sound")
	doc = _doc()
	doc["beds"]["b"]["spots"][0]["sound"] = "nope"
	_assert_rejected(doc, "beds.b.spots[0].sound")


func test_loop_layer_needs_a_loop_sound() -> void:
	var doc := _doc()
	doc["machines"]["m"]["loops"][0]["sound"] = "hit"
	_assert_rejected(doc, "machines.m.loops[0].sound")
	doc = _doc()
	doc["beds"]["b"]["layers"][0]["sound"] = "hit"
	_assert_rejected(doc, "beds.b.layers[0].sound")


func test_duplicate_ids() -> void:
	var doc := _doc()
	doc["machines"]["m"]["events"][0]["at"] = [0.5, 0.5]
	_assert_rejected(doc, "duplicate id")
	doc = _doc()
	doc["sounds"]["hit"]["variants"] = 2.0
	doc["sounds"]["hit_1"] = {"rate": 22050.0, "ch": 1.0}
	_assert_rejected(doc, "duplicate id: hit_1.wav")
	var text := '{"sounds": {"a": {"x": 1, "x": [1, {"y": 2, "y": 3}]}, "a": {}}, "b": "a"}'
	assert_eq(
		AudioBank.duplicate_keys(text),
		["sounds.a.x", "sounds.a.x.y", "sounds.a"] as Array[String],
		"JSON.parse would keep only the last of them"
	)
	assert_eq(AudioBank.duplicate_keys('{"a": "b\\"", "c": {"a": 1}}'), [] as Array[String])


func test_loop_player_budget() -> void:
	var doc := _doc()
	doc["mix"] = {"max_loop_players": 2.0}
	_assert_rejected(doc, "exceed 2")


func test_load_errors_name_the_path() -> void:
	assert_null(AudioBank.load_bank("res://tests/audio/fixtures/does_not_exist.json"))
	assert_push_error("does_not_exist.json")
	var doc := _doc()
	doc["schema"] = 9.0
	assert_null(AudioBank.from_dict(doc, "res://x"))
	assert_push_error("schema")


func test_set_stream_takes_precedence_and_variants_wrap() -> void:
	var bank := AudioBank.load_bank(BANK)
	var a := AudioStreamWAV.new()
	var b := AudioStreamWAV.new()
	var c := AudioStreamWAV.new()
	bank.set_stream("stroke", 0, a)
	bank.set_stream("stroke", 1, b)
	bank.set_stream("stroke", 2, c)
	assert_same(bank.stream("stroke", 0), a)
	assert_same(bank.stream("stroke", 1), b)
	assert_same(bank.stream("stroke", 2), c)
	assert_same(bank.stream("stroke", 3), a, "a running count round-robins")
	assert_same(bank.stream("stroke", 4), b)


func test_missing_file_warns_once_and_is_null() -> void:
	var bank := AudioBank.load_bank(BANK)
	assert_null(bank.stream("bang"))
	assert_null(bank.stream("bang"))
	assert_push_warning("no sound at res://tests/audio/fixtures/bang.wav")

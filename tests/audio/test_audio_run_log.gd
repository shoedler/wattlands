extends GutTest
## --audio-log: what the players took in a run nothing else can look inside, the exported exe.

const BANK := "res://tests/audio/fixtures/bank_min.json"

var _dir: String = ""


func before_each() -> void:
	_dir = Paths.make_temp_dir("wattlands_run_log")


func after_each() -> void:
	DirAccess.remove_absolute(_dir.path_join("log.json"))
	DirAccess.remove_absolute(_dir)


func _loud_kit() -> GameAudioKit:
	var kit := GameAudioKit.new()
	kit.force_audio = true
	add_child_autofree(kit)
	var bank := AudioBank.load_bank(BANK)
	for id: String in bank.sounds:
		for v in bank.variants(id):
			bank.set_stream(id, v, SfxSynth.tone("sine", 200.0, 1.0))
	assert_true(kit.setup_bank(bank, 1))
	return kit


func _log(kit: GameAudioKit) -> AudioRunLog:
	var node := AudioRunLog.new()
	node.kit = kit
	node.path = _dir.path_join("log.json")
	node.set_process(false)
	return node


func test_it_counts_what_players_took_and_writes_it() -> void:
	var kit := _loud_kit()
	var node := _log(kit)
	add_child_autofree(node)
	# Code-built streams have no resource path: the count is by stem, "" here.
	kit.sound("bang", 0.0, 1.0, AudioBuses.SFX)
	node.poll()
	kit.sound("bang", 0.0, 1.0, AudioBuses.SFX)
	node.poll()
	node.poll()
	assert_eq(int(node.starts[""]["n"]), 2)
	assert_eq(int(node.starts[""]["playing"]), 2)
	assert_eq(int(node.starts[""]["buses"][AudioBuses.SFX]), 2)
	node.write()
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(node.path))
	assert_false(bool(doc["exported"]), "this is no export template")
	assert_false(bool(doc["silent"]))
	assert_eq(int(doc["voiceless"]), 0)
	assert_eq(int(doc["starts"][""]["n"]), 2)


func test_without_the_flag_a_kit_has_none() -> void:
	var kit := _loud_kit()
	assert_null(kit.get_node_or_null("AudioRunLog"))

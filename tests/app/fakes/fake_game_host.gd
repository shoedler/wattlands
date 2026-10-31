extends GameHost
## Test double of GameHost: records the setup config and drives the documented signals.

const FakeModule := preload("res://tests/app/fakes/fake_module.gd")

var config_seen: Dictionary = {}
var setup_error: String = ""
var started: bool = false
var paused_flag: bool = false
var pause_reasons: Array[String] = []
var resumes: int = 0
var ended_reasons: Array[String] = []
var finished_flag: bool = false
var results_out: GameResults = null
var fits: Dictionary = {}
var discards: int = 0


func setup(config: Dictionary) -> String:
	config_seen = config
	if setup_error == "":
		game = FakeModule.new()
		add_child(game)
	return setup_error


func start() -> void:
	started = true
	state = "running"
	state_changed.emit("running")


func pause(reason: String = "user") -> void:
	paused_flag = true
	pause_reasons.append(reason)
	state = "paused"
	state_changed.emit("paused")


func resume() -> void:
	paused_flag = false
	resumes += 1
	state = "running"
	state_changed.emit("running")


func is_paused() -> bool:
	return paused_flag


func is_finished() -> bool:
	return finished_flag


func final_results() -> GameResults:
	return results_out


func fit_paths() -> Dictionary:
	return fits


func discard_own_ride() -> bool:
	discards += 1
	return true


func end_session(reason: String) -> void:
	ended_reasons.append(reason)
	finish_with(results_out if results_out != null else GameResults.new())


## Finish the session with `r` (state "results", session_finished).
func finish_with(r: GameResults) -> void:
	if finished_flag:
		return
	finished_flag = true
	results_out = r
	state = "results"
	state_changed.emit("results")
	session_finished.emit(r)

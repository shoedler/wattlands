extends WlApp
## Test double of the App autoload: goto() moves the state and emits state_changed (the
## documented behaviour the main scene listens to); quit() only records the code.

var history: Array[String] = []
var quit_codes: Array[int] = []


func goto(new_state: String, p_params: Dictionary = {}) -> void:
	state = new_state
	params = p_params
	history.append(new_state)
	state_changed.emit(new_state, p_params)


func quit(exit_code: int = 0) -> void:
	quit_codes.append(exit_code)

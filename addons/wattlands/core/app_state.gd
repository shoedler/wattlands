class_name WlApp
extends Node
## Autoload `App`: the app state machine and command-line entry (BRIEF 3.5, 3.9, 6).
## Owned by platform; public API frozen after W0. The app shell's main scene
## (src/app/main.tscn) listens to state_changed and shows the matching screen.
##
## States: "boot", "title", "first_run", "profile", "settings", "picker", "lobby",
## "session", "results", "quitting".
## Command line (CmdLine): --mock-trainer=<profile> uses a MockTrainer; --host creates a
## room; --join=<code> joins one; --game/--content/--seed choose the session; --autopilot
## sets Autopilot; --run-seconds quits after n seconds of platform time; --report writes a
## JSON report on exit; --profile-dir moves Paths.user_dir(). With --host or --join the app
## skips the menus (headless e2e peers) and starts as soon as the lobby is ready.

signal state_changed(state: String, params: Dictionary)

var state: String = "boot"
## Parameters of the current state (for example {"game_id": "workout"} for the lobby).
var params: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func goto(_new_state: String, _p_params: Dictionary = {}) -> void:
	pass


## True when started with --host or --join (automated or command-line sessions).
func is_scripted() -> bool:
	return false


## Quit cleanly: governor shutdown on every local rider, ride saved, report written.
func quit(_exit_code: int = 0) -> void:
	pass

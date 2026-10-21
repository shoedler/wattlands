class_name WlInputRouter
extends Node
## Autoload `InputRouter` (BRIEF 3.5): keyboard and Xbox controller actions (rebindable,
## saved to Paths.input_cfg_path()), merged with the local rider's pedal gestures for menus
## and sessions. Owned by ui-hud; public API frozen after W0. Runs with
## PROCESS_MODE_ALWAYS.
## Defaults: arrows/WASD move, Enter/Space confirm, Esc back, 1/2 abilities, F item, R swap,
## Q/E shift down/up, P pause, Backspace held 1 s panic; controller: left stick/D-pad move,
## A confirm, B back, X/Y abilities, RB item, LB swap, LT/RT shift down/up, Start pause,
## View+Menu together panic. Panic emits EventBus.panic_requested immediately.
## Pedal UI: `surge` acts as confirm and `coast` as back for menus (pedal-scan), `stop_5s`
## as pause (solo, outside ERG).

signal action(action_name: StringName)
signal gesture(gesture_name: StringName)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Gestures from this rider feed menus and sessions (TrainerService/GameHost attach it).
func attach_rider(_rider: LocalRider) -> void:
	pass


func detach_rider() -> void:
	pass


## Actions since the last call (the GameHost drains it every tick for local_intents).
func take_actions() -> Array[StringName]:
	return []


## Gestures since the last call.
func take_gestures() -> Array[StringName]:
	return []


## True when menus run on pedal-scan (Autopilot or pedal UI on, or no input device used yet).
func pedal_ui_active() -> bool:
	return true


## Inject an action (on-screen buttons, tests).
func inject_action(_name: StringName) -> void:
	pass


## Inject a gesture (tests).
func inject_gesture(_name: StringName) -> void:
	pass


func rebind(_action_name: StringName, _event: InputEvent) -> void:
	pass


func save_bindings() -> bool:
	return false


func load_bindings() -> void:
	pass

extends WlInputRouter
## Test double of InputRouter: injected actions and gestures are emitted at once.

var rebinds: Array = []
var saves: int = 0


func inject_action(action_name: StringName) -> void:
	action.emit(action_name)


func inject_gesture(gesture_name: StringName) -> void:
	gesture.emit(gesture_name)


func rebind(action_name: StringName, event: InputEvent) -> void:
	rebinds.append([action_name, event])


func save_bindings() -> bool:
	saves += 1
	return true

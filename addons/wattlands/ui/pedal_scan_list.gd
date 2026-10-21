class_name PedalScanList
extends VBoxContainer
## A pedal-scan (single-switch scanning) list for menus, game shops and pickers (BRIEF 3.5,
## 3.9). Owned by ui-hud; public API frozen after W0.
## With scanning on, focus cycles through the enabled items every `scan_interval_s`
## (default 1.6 s, the profile setting); `surge` (or confirm) picks the highlighted item and
## `coast` (or back) backs out. Keyboard/controller up/down move focus and stop scanning for
## 10 s. With erg_auto_confirm on (picks shown during ERG phases), the highlighted item is
## picked automatically after two full scan cycles; such picks report auto = true.
## Time advances in _process (PROCESS_MODE_ALWAYS) or through tick(dt) in headless tests.

## index, the item's id, and whether the pick was an ERG auto-confirm.
signal item_chosen(index: int, id: Variant, auto: bool)
## The same pick with its source: "action" (keyboard/controller confirm), "surge" (pedal
## gesture) or "auto" (ERG auto-confirm). Emitted together with item_chosen.
signal item_picked(index: int, id: Variant, via: String)
signal backed_out
signal highlight_changed(index: int)

var scan_interval_s: float = 1.6
var scanning: bool = true
var erg_auto_confirm: bool = false
## In sessions: erg_auto_confirm follows the local rider's trainer mode (on while in ERG).
## Auto-confirm fires after two full cycles in ERG even with scanning off.
var follow_local_mode: bool = false
## Follow InputRouter actions and gestures automatically (off in headless tests).
var listen_to_input: bool = true


## items: [{"id": Variant, "text": String (key or text), "disabled": bool (optional),
## "icon": Texture2D (optional), "detail": String (optional)}].
func set_items(_items: Array) -> void:
	pass


func highlighted() -> int:
	return -1


func set_highlight(_index: int) -> void:
	pass


## Feed a gesture or action by hand (headless tests, game-specific routing).
func feed_gesture(_name: StringName) -> void:
	pass


func feed_action(_name: StringName) -> void:
	pass


## Advance the scan timer (headless tests; _process calls it in real time).
func tick(_dt: float) -> void:
	pass

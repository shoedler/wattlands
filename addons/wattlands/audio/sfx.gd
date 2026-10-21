class_name WlSfx
extends Node
## Autoload `Sfx` (BRIEF 3.9 audio): sound effects from credited CC0 packs if downloaded,
## otherwise synthesized at runtime, plus an optional cadence metronome. Owned by ui-hud;
## public API frozen after W0. Silent (no errors) in headless runs.
## Built-in effect names: "ui_move", "ui_confirm", "ui_back", "toast", "warning", "rescue",
## "phase", "countdown", "lap", "results", "coin", "hit", "boom", "whoosh", "click".
## Games register their own synthesized or loaded streams with register().

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func play(_name: String, _volume_db: float = 0.0, _pitch: float = 1.0) -> void:
	pass


## Add a named effect (an AudioStream, e.g. a game's own synthesized clip).
func register(_name: String, _stream: AudioStream) -> void:
	pass


func has_sound(_name: String) -> bool:
	return false


## Cadence metronome at `rpm` (one click per pedal stroke); rpm <= 0 stops it.
func set_metronome(_rpm: float, _on: bool) -> void:
	pass


## A short synthesized tone/noise clip (games can use it for their own effects).
## kind: "sine", "square", "saw", "noise"; envelope seconds.
func synth(_kind: String, _freq_hz: float, _duration_s: float, _attack_s: float = 0.005, _release_s: float = 0.05, _loop: bool = false) -> AudioStream:
	return null

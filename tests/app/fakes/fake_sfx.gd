extends WlSfx
## Test double of the Sfx autoload: records played effects and metronome calls.

var played: Array[String] = []
var metronome_calls: Array = []


func play(sound_name: String, _volume_db: float = 0.0, _pitch: float = 1.0) -> void:
	played.append(sound_name)


func set_metronome(rpm: float, on: bool) -> void:
	metronome_calls.append([rpm, on])

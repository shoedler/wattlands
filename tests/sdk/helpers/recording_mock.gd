extends MockTrainer
## A real MockTrainer (the W0 "erg" rider at FTP 200) that also records the bands it is given,
## so sdk-runtime tests can prove a band "reached MockTrainer" through its public setters
## instead of reading MockTrainer's private fields (trainer-core owns those and may rename
## them).

var cadence_bands: Array = []
var power_bands: Array = []


func set_cadence_band(lo_rpm: float, hi_rpm: float) -> void:
	cadence_bands.append([lo_rpm, hi_rpm])
	super(lo_rpm, hi_rpm)


func set_power_band(lo_w: float, hi_w: float) -> void:
	power_bands.append([lo_w, hi_w])
	super(lo_w, hi_w)


## The latest band given, [0, 0] when none.
func last_cadence_band() -> Array:
	return cadence_bands[cadence_bands.size() - 1] if not cadence_bands.is_empty() else [0.0, 0.0]


func last_power_band() -> Array:
	return power_bands[power_bands.size() - 1] if not power_bands.is_empty() else [0.0, 0.0]

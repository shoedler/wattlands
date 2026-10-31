class_name LayeredLoop
extends RefCounted
## The pitch and gain of a machine's or a bed's looping layers (SPEC_AUDIO 1.2). Pure: GameAudioKit owns the players.
## Pitch: one-pole toward product(pitch_by), tau layer.slew_s (default 0.25: a real KICKR reports cadence about
## once a second, BRIEF 4.5, so a fast slew would step the pitch each second; strokes carry the rate). A layer that
## was off takes its target pitch at once.
## Gain: opening one-pole tau 0.04; closing linear in dB at 600 dB/s (a one-pole on dB never reaches OFF_DB).
## A layer wants on if params.rpm >= min_rpm (when given) and passes(when). With lead false and "other" false it is off.
const OFF_DB := -60.0
const OPEN_TAU_S := 0.04
const CLOSE_DB_PER_S := 600.0
const SLEW_S := 0.25
var count: int = 0
var pitch: PackedFloat32Array = PackedFloat32Array()  ## current, slewed
var db: PackedFloat32Array = PackedFloat32Array()
var on: PackedByteArray = PackedByteArray()  ## 1 while the layer's player should run; 0 once db <= OFF_DB

var _layers: Array = []


func _init(p_layers: Array) -> void:
	_layers = p_layers
	count = p_layers.size()
	pitch.resize(count)
	pitch.fill(1.0)
	db.resize(count)
	db.fill(OFF_DB)
	on.resize(count)
	on.fill(0)


func update(params: Dictionary, trim_db: float, lead: bool, dt: float) -> void:
	for i in count:
		var layer: Dictionary = _layers[i]
		var want := _wants(layer, params, lead)
		var target := OFF_DB
		if want:
			var level := float(layer.get("db", 0.0))
			target = level + AudioCurve.sum_db(layer.get("db_by", []), params) + trim_db
		if target > OFF_DB:
			_slew_pitch(i, AudioCurve.product(layer.get("pitch_by", []), params), layer, dt)
			on[i] = 1
		_move_db(i, target, dt)


## Every layer closes, whatever the params say: a stopped machine, a paused kit, an instance no longer driven.
func close(dt: float) -> void:
	for i in count:
		_move_db(i, OFF_DB, dt)


func layer(i: int) -> Dictionary:
	return _layers[i]


func all_off() -> bool:
	for i in count:
		if on[i] != 0:
			return false
	return true


func _wants(p_layer: Dictionary, params: Dictionary, lead: bool) -> bool:
	if not lead and not bool(p_layer.get("other", false)):
		return false
	if p_layer.has("min_rpm") and float(params.get("rpm", 0.0)) < float(p_layer["min_rpm"]):
		return false
	return AudioCurve.passes(p_layer.get("when", {}), params)


func _slew_pitch(i: int, target: float, p_layer: Dictionary, dt: float) -> void:
	if on[i] == 0:
		pitch[i] = target
		return
	var tau := float(p_layer.get("slew_s", SLEW_S))
	pitch[i] = target if tau <= 0.0 else lerpf(pitch[i], target, 1.0 - exp(-dt / tau))


func _move_db(i: int, target: float, dt: float) -> void:
	if target > db[i]:
		db[i] = lerpf(db[i], target, 1.0 - exp(-dt / OPEN_TAU_S))
	else:
		db[i] = maxf(target, db[i] - CLOSE_DB_PER_S * dt)
	if db[i] <= OFF_DB:
		db[i] = OFF_DB
		on[i] = 0

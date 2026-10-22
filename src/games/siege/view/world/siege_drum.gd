class_name SiegeDrum
extends RefCounted
## The generator's rolling-drum counter (brief 3 "Generator"): four digit drums and a "W" plate
## show the team's raw watts (the state's 1 s mean), rolling with a 0.4 s ease, clamped at 9999.
## Pure: the generator view feeds it the target watts and its frame time, then reads the digits.
##
##   display_value(12000) == 9999; text_for(1250) == "1250"; text_for(7) == "7"; text_for(0) == "0".

const PLACES := 4
const MAX_VALUE := 9999
const EASE_S := 0.4

## The value on the drums right now (float; the drums roll through the in-between values).
var shown: float = 0.0
var target: int = 0
var _from: float = 0.0
var _t: float = EASE_S


## The whole watts a drum shows for `watts`: rounded, 0 .. 9999.
static func display_value(watts: float) -> int:
	return clampi(roundi(watts), 0, MAX_VALUE)


## What the four drums read for `value`: no leading zeros ("7", "1250"), "0" at zero.
static func text_for(value: int) -> String:
	return str(clampi(value, 0, MAX_VALUE))


## The four digits left to right for `value`, -1 for a blank leading drum (the ones drum is
## never blank).
static func digits_for(value: int) -> Array[int]:
	var v := clampi(value, 0, MAX_VALUE)
	var out: Array[int] = []
	for place in range(PLACES - 1, -1, -1):
		var p := int(pow(10.0, place))
		out.append(-1 if (place > 0 and v < p) else floori(float(v) / float(p)) % 10)
	return out


## Starts an ease to `watts` when the displayed target changes (call every frame; cheap).
func set_target_w(watts: float) -> void:
	var v := display_value(watts)
	if v == target:
		return
	_from = shown
	target = v
	_t = 0.0


## Advances the roll by `dt` seconds with a smoothstep ease over EASE_S.
func step(dt: float) -> void:
	if _t >= EASE_S:
		shown = float(target)
		return
	_t = minf(_t + maxf(dt, 0.0), EASE_S)
	var u := _t / EASE_S
	u = u * u * (3.0 - 2.0 * u)
	shown = lerpf(_from, float(target), u)


## True while the drums are still rolling.
func rolling() -> bool:
	return _t < EASE_S


## Jumps to `watts` at once (the first frame).
func snap_to(watts: float) -> void:
	target = display_value(watts)
	shown = float(target)
	_from = shown
	_t = EASE_S


## One drum's state at the current `shown` value: {"digit": int or -1 for blank, "next": the
## digit rolling in (-1 blank), "roll": 0..1}. `place` 0 is the ones drum. The ones drum rolls
## continuously; higher drums roll only while the drums below wrap (an odometer).
func drum_at(place: int) -> Dictionary:
	var s := clampf(shown, 0.0, float(MAX_VALUE))
	var p := pow(10.0, place)
	var x := s / p
	var base := floori(x)
	var frac := x - floorf(x)
	# An odometer: the ones drum rolls all the time; each higher drum rolls only while the
	# drums below it carry (the last unit before their wrap).
	var roll := frac
	if place > 0:
		roll = clampf(fmod(s, p) - (p - 1.0), 0.0, 1.0)
	var digit := base % 10
	var nxt := (base + 1) % 10
	var cur_blank := place > 0 and base < 1
	var next_blank := place > 0 and (base + 1) < 1
	if float(base + 1) > floorf(float(MAX_VALUE) / p):
		# Clamped at 9999: never roll past it.
		roll = 0.0
	return {
		"digit": -1 if cur_blank else digit,
		"next": -1 if next_blank else nxt,
		"roll": roll,
	}

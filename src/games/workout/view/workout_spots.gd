class_name WorkoutSpots
extends RefCounted
## The landscape's seeded surprises: a flock, a tractor, a balloon. A list fixed by the seed and the
## session's length and chosen by plan time, so every peer sees the same flock at the same moment.
## It has its own RNG and never touches ctx.rng.

const SALT := 0x5EED
const GAP_MIN_S := 35.0
const GAP_MAX_S := 90.0
## Spots start this far left of the screen and cross this far, enough for the widest canvas.
const ENTER_X := -60.0
const CROSS_PX := 1900.0
const FLOCK_Y_MIN := 90.0
const FLOCK_Y_MAX := 200.0
const BALLOON_Y_MIN := 90.0
const BALLOON_Y_MAX := 160.0
const TRACTOR_VX := 6.0
const BALLOON_VX := 2.0
## A balloon goes up only in full day (kit.props.balloon.tod_min_row of 32 rows).
const BALLOON_MIN_P := 16.0 / 31.0


## [{kind, t0, dur, x0, y, vx, n}], by rising t0. `n`: birds of a flock (else 1).
static func build(seed_value: int, total_s: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := SeededRng.make(seed_value ^ SALT)
	var t := SeededRng.range_f(rng, GAP_MIN_S, GAP_MAX_S)
	var tractor_gone := 0.0
	while t < total_s:
		var roll := SeededRng.range_i(rng, 0, 8)
		if roll >= 8 and t / maxf(total_s, 1.0) >= BALLOON_MIN_P:
			var high := SeededRng.range_f(rng, BALLOON_Y_MIN, BALLOON_Y_MAX)
			out.append(_spot("balloon", t, BALLOON_VX, high, 1))
		elif roll >= 6 and t >= tractor_gone:
			# One field, one tractor: the next comes once this one has crossed.
			var spot := _spot("tractor", t, TRACTOR_VX, 0.0, 1)
			tractor_gone = t + float(spot["dur"])
			out.append(spot)
		else:
			var y := SeededRng.range_f(rng, FLOCK_Y_MIN, FLOCK_Y_MAX)
			var v := SeededRng.range_f(rng, 18.0, 30.0)
			out.append(_spot("flock", t, v, y, SeededRng.range_i(rng, 5, 11)))
		t += SeededRng.range_f(rng, GAP_MIN_S, GAP_MAX_S)
	return out


static func _spot(kind: String, t0: float, vx: float, y: float, n: int) -> Dictionary:
	return {
		"kind": kind,
		"t0": t0,
		"dur": CROSS_PX / vx,
		"x0": ENTER_X,
		"y": y,
		"vx": vx,
		"n": n,
	}


## The spots on the way at plan time `t`.
static func active(spots: Array[Dictionary], t: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in spots:
		var t0 := float(s["t0"])
		if t0 > t:
			break
		if t < t0 + float(s["dur"]):
			out.append(s)
	return out

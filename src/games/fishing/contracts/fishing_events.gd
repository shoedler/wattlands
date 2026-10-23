class_name FishingEvents
extends RefCounted
## The event schema (contract v2). FishingRules returns these dictionaries in
## FishingStepOut.events; the module sends each with send_event() (batched, in order, to every
## client) and raises the host's own effects; clients raise theirs in apply_event(). Every number
## is an int on the wire (declared in int_fields()). `l` is the rider's slot index; `sp` a
## FishingConst.SPECIES index; distances and depths in dm.
##
## type           fields
## cast           l, sp (the fish cast at), dx (the wobbler's dx), z (its target depth)
## bite           l, sp (the fish took the wobbler; the hook sets itself)
## hookup         l, sp, n (the rider's fight number, 1-based), sch (1 scheduled fish)
## run            l, k (1-based run number), n (runs in this fight), ms (scheduled length)
## jump           l, k, n, ms, leaps (1-3)
## snap           l
## thrown         l
## replacement    l, sp
## landing        l, sp
## landed         l, sp, grade (FishingConst.GRADE_TROPHY 1 / GRADE_LANDED 0), kg (x10),
##                points, hk (hookup multiplier x10: 10 in Free Roam; workouts 10, 15, 20, 25)
## double_hookup  lanes [slot, ...] (every fight on now, slot order), lvl (2..4; workouts only)
## turn           l, h (the new heading, +1 / -1)
## time_up        (no fields) play time is over: no new bites, fights may finish (<= 5 min)
## trip_over      (no fields) the session ends (everyone heads into the cool-down)

const CAST := "cast"
const BITE := "bite"
const HOOKUP := "hookup"
const RUN := "run"
const JUMP := "jump"
const SNAP := "snap"
const THROWN := "thrown"
const REPLACEMENT := "replacement"
const LANDING := "landing"
const LANDED := "landed"
const DOUBLE_HOOKUP := "double_hookup"
const TURN := "turn"
const TIME_UP := "time_up"
const TRIP_OVER := "trip_over"

const INT_FIELDS := {
	CAST: ["l", "sp", "dx", "z"],
	BITE: ["l", "sp"],
	HOOKUP: ["l", "sp", "n", "sch"],
	RUN: ["l", "k", "n", "ms"],
	JUMP: ["l", "k", "n", "ms", "leaps"],
	SNAP: ["l"],
	THROWN: ["l"],
	REPLACEMENT: ["l", "sp"],
	LANDING: ["l", "sp"],
	LANDED: ["l", "sp", "grade", "kg", "points", "hk"],
	DOUBLE_HOOKUP: ["lanes[]", "lvl"],
	TURN: ["l", "h"],
	TIME_UP: [],
	TRIP_OVER: [],
}


## int_fields() for GameModule: the snapshot's paths plus every event type's.
static func int_fields() -> Dictionary:
	var out := {"snapshot": FishingSnapshotSchema.INT_PATHS.duplicate()}
	for k: String in INT_FIELDS:
		out[k] = (INT_FIELDS[k] as Array).duplicate()
	return out


## A copy of `event` with every declared int field cast with int() (arrays element-wise);
## apply_event calls it on everything it reads.
static func cast_ints(event: Dictionary) -> Dictionary:
	var out := event.duplicate(true)
	for path: String in INT_FIELDS.get(str(event.get("type", "")), []):
		var key := path.trim_suffix("[]")
		if not out.has(key):
			continue
		if path.ends_with("[]") and out[key] is Array:
			out[key] = (out[key] as Array).map(func(v: Variant) -> int: return int(v))
		elif out[key] is float or out[key] is int or out[key] is bool:
			out[key] = int(out[key])
	return out


## "" when `event` has a known type and every declared field, else the problem.
static func check(event: Dictionary) -> String:
	var type := str(event.get("type", ""))
	if not INT_FIELDS.has(type):
		return "unknown type %s" % type
	for path: String in INT_FIELDS[type]:
		if not event.has(path.trim_suffix("[]")):
			return "%s: missing %s" % [type, path.trim_suffix("[]")]
	return ""


static func cast(l: int, sp: int, dx_m: float, depth_m: float) -> Dictionary:
	return {"type": CAST, "l": l, "sp": sp, "dx": roundi(dx_m * 10.0), "z": roundi(depth_m * 10.0)}


static func bite(l: int, sp: int) -> Dictionary:
	return {"type": BITE, "l": l, "sp": sp}


static func hookup(l: int, sp: int, n: int, scheduled: bool) -> Dictionary:
	return {"type": HOOKUP, "l": l, "sp": sp, "n": n, "sch": int(scheduled)}


static func run(l: int, k: int, n: int, dur_s: float) -> Dictionary:
	return {"type": RUN, "l": l, "k": k, "n": n, "ms": roundi(dur_s * 1000.0)}


static func jump(l: int, k: int, n: int, dur_s: float, leaps: int) -> Dictionary:
	return {"type": JUMP, "l": l, "k": k, "n": n, "ms": roundi(dur_s * 1000.0), "leaps": leaps}


static func snap(l: int) -> Dictionary:
	return {"type": SNAP, "l": l}


static func thrown(l: int) -> Dictionary:
	return {"type": THROWN, "l": l}


static func replacement(l: int, sp: int) -> Dictionary:
	return {"type": REPLACEMENT, "l": l, "sp": sp}


static func landing(l: int, sp: int) -> Dictionary:
	return {"type": LANDING, "l": l, "sp": sp}


static func landed(l: int, sp: int, grade: int, kg: float, points: int, hk: float) -> Dictionary:
	return {
		"type": LANDED,
		"l": l,
		"sp": sp,
		"grade": grade,
		"kg": roundi(kg * 10.0),
		"points": points,
		"hk": roundi(hk * 10.0)
	}


static func double_hookup(lanes: Array[int], lvl: int) -> Dictionary:
	return {"type": DOUBLE_HOOKUP, "lanes": lanes.duplicate(), "lvl": lvl}


static func turn(l: int, heading: int) -> Dictionary:
	return {"type": TURN, "l": l, "h": heading}


static func time_up() -> Dictionary:
	return {"type": TIME_UP}


static func trip_over() -> Dictionary:
	return {"type": TRIP_OVER}

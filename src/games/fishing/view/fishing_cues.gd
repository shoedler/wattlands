class_name FishingCues
extends RefCounted
## Presentation cues for effects and audio, from either source:
##  - the module's events: FishingGame emits fx_event(event) on every peer (the view connects
##    and uses from_event());
##  - otherwise edges in the state the view reads (diff()), so a host, a client and SOLO show the
##    same effects whatever the module raises.
## A cue is {"k": CUE_*, "l": slot, ...}: jump {leaps}, landed {grade}, hookup {replacement}.

const CUE_CAST := "cast"
const CUE_BITE := "bite"
const CUE_HOOKUP := "hookup"
const CUE_RUN := "run"
const CUE_JUMP := "jump"
const CUE_SNAP := "snap"
const CUE_THROWN := "thrown"
const CUE_LANDING := "landing"
const CUE_LANDED := "landed"
const CUE_DOUBLE_HOOKUP := "double_hookup"
const CUE_TURN := "turn"
const CUE_TIME_UP := "time_up"
const CUE_TRIP_OVER := "trip_over"

var _seen: bool = false
var _action: PackedInt32Array = PackedInt32Array()
var _landed: PackedInt32Array = PackedInt32Array()
var _replacement: PackedByteArray = PackedByteArray()
var _heading: PackedInt32Array = PackedInt32Array()
var _run: PackedByteArray = PackedByteArray()
var _trip_over: bool = false
var _time_up: bool = false


## The cues for one module event ([] for events with no effect).
static func from_event(raw: Dictionary) -> Array[Dictionary]:
	var e := FishingEvents.cast_ints(raw)
	var l := int(e.get("l", -1))
	var k := ""
	match str(e.get("type", "")):
		FishingEvents.CAST:
			k = CUE_CAST
		FishingEvents.BITE:
			k = CUE_BITE
		FishingEvents.HOOKUP:
			k = CUE_HOOKUP
		FishingEvents.REPLACEMENT:
			return [{"k": CUE_HOOKUP, "l": l, "replacement": true}]
		FishingEvents.LANDING:
			k = CUE_LANDING
		FishingEvents.RUN:
			k = CUE_RUN
		FishingEvents.JUMP:
			return [{"k": CUE_JUMP, "l": l, "leaps": clampi(int(e.get("leaps", 2)), 1, 3)}]
		FishingEvents.SNAP:
			k = CUE_SNAP
		FishingEvents.THROWN:
			k = CUE_THROWN
		FishingEvents.LANDED:
			return [{"k": CUE_LANDED, "l": l, "grade": int(e.get("grade", 0))}]
		FishingEvents.DOUBLE_HOOKUP:
			k = CUE_DOUBLE_HOOKUP
		FishingEvents.TURN:
			k = CUE_TURN
		FishingEvents.TIME_UP:
			k = CUE_TIME_UP
		FishingEvents.TRIP_OVER:
			k = CUE_TRIP_OVER
	if k == "":
		return []
	return [{"k": k, "l": l}]


## One frame's cues, a call said once: a Landing that finds its fish off the line hooks the replacement
## in the same step, and the sprint's call speaks for both.
static func merged(cues: Array[Dictionary]) -> Array[Dictionary]:
	var landing: Array[int] = []
	for c in cues:
		if c.get("k") == CUE_LANDING:
			landing.append(int(c.get("l", -1)))
	if landing.is_empty():
		return cues
	var out: Array[Dictionary] = []
	for c in cues:
		if not (c.get("replacement", false) and landing.has(int(c.get("l", -1)))):
			out.append(c)
	return out


## The cues the state shows since the last call (none on the first call, which only learns).
func diff(state: FishingState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := state.riders.size()
	if not _seen or _action.size() != n:
		_learn(state)
		return out
	for r in state.riders:
		var i := r.slot
		if i < 0 or i >= n:
			continue
		var was := _action[i]
		if r.action != was:
			if r.action == FishingConst.A_CAST:
				out.append({"k": CUE_CAST, "l": i})
			elif r.action == FishingConst.A_FIGHT and was != FishingConst.A_LAND:
				out.append({"k": CUE_HOOKUP, "l": i})
			elif r.action == FishingConst.A_LAND and r.fish.sp >= 0:
				out.append({"k": CUE_LANDING, "l": i})
		if r.fish.replacement and _replacement[i] == 0 and r.action == FishingConst.A_FIGHT:
			out.append({"k": CUE_HOOKUP, "l": i, "replacement": true})
		if r.fish.run_active and _run[i] == 0 and r.action == FishingConst.A_FIGHT:
			out.append({"k": CUE_RUN, "l": i})
		if r.fish_landed > _landed[i]:
			out.append({"k": CUE_LANDED, "l": i, "grade": 0})
		if r.heading != _heading[i]:
			out.append({"k": CUE_TURN, "l": i})
	if state.time_up and not _time_up:
		out.append({"k": CUE_TIME_UP, "l": -1})
	if state.trip_over and not _trip_over:
		out.append({"k": CUE_TRIP_OVER, "l": -1})
	_learn(state)
	return out


func reset() -> void:
	_seen = false


func _learn(state: FishingState) -> void:
	var n := state.riders.size()
	_action.resize(n)
	_landed.resize(n)
	_replacement.resize(n)
	_heading.resize(n)
	_run.resize(n)
	for r in state.riders:
		if r.slot < 0 or r.slot >= n:
			continue
		_action[r.slot] = r.action
		_landed[r.slot] = r.fish_landed
		_replacement[r.slot] = 1 if r.fish.replacement else 0
		_heading[r.slot] = r.heading
		_run[r.slot] = 1 if r.fish.run_active else 0
	_time_up = state.time_up
	_trip_over = state.trip_over
	_seen = true

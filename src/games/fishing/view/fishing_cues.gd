class_name FishingCues
extends RefCounted
## Presentation cues for effects and audio, from either source:
##  - the module's events: FishingGame emits fx_event(event) on every peer (when it has that
##    signal, the view connects and uses from_event());
##  - otherwise edges in the state the view reads (diff()), so a host, a client and SOLO show the
##    same effects whatever the module raises.
## A cue is {"k": CUE_*, "l": lane, ...}: cast {d (m)}, jump {leaps}, landed {grade},
## double_hookup {lanes: [lane, ...]}. diff() keeps a few numbers per lane between calls and
## allocates only when something happened.

const CUE_CAST := "cast"
const CUE_BITE := "bite"
const CUE_HOOKUP := "hookup"
const CUE_MISS := "miss"
const CUE_RUN := "run"
const CUE_JUMP := "jump"
const CUE_SNAP := "snap"
const CUE_THROWN := "thrown"
const CUE_LANDED := "landed"
const CUE_DOUBLE_HOOKUP := "double_hookup"
const CUE_FRENZY := "frenzy"
const CUE_TRIP_OVER := "trip_over"
const DEFAULT_LEAPS := 3

## Species index -> true when its runs are jumps (marlin); set from content.
var jump_species: Dictionary = {}

var _seen: bool = false
var _state: PackedInt32Array = PackedInt32Array()
var _run: PackedByteArray = PackedByteArray()
var _off: PackedByteArray = PackedByteArray()
var _landed: PackedInt32Array = PackedInt32Array()
var _strain: PackedFloat32Array = PackedFloat32Array()
var _slack: PackedFloat32Array = PackedFloat32Array()
var _frenzy: PackedByteArray = PackedByteArray()
var _hookup: int = 0
var _trip_over: bool = false


## jump_species from FishingContent (species ids -> FishingSpeciesDef).
func use_content(content: FishingContent) -> void:
	jump_species.clear()
	if content == null:
		return
	for id: String in content.species:
		var def: FishingSpeciesDef = content.species[id]
		if def.run_kind == FishingSpeciesDef.RUN_JUMP:
			jump_species[FishingConst.species_index(id)] = true


func is_jump_species(sp: int) -> bool:
	return jump_species.has(sp)


## The cues for one module event ([] for events with no effect).
func from_event(raw: Dictionary) -> Array[Dictionary]:
	var e := FishingEvents.cast_ints(raw)
	var out: Array[Dictionary] = []
	var l := int(e.get("l", -1))
	match str(e.get("type", "")):
		FishingEvents.CAST:
			out.append({"k": CUE_CAST, "l": l, "d": float(e.get("d", 0)) / 10.0})
		FishingEvents.BITE:
			out.append({"k": CUE_BITE, "l": l})
		FishingEvents.HOOKUP:
			out.append({"k": CUE_HOOKUP, "l": l})
		FishingEvents.STRIKE_MISS:
			out.append({"k": CUE_MISS, "l": l})
		FishingEvents.RUN:
			out.append({"k": CUE_RUN, "l": l})
		FishingEvents.JUMP:
			out.append({"k": CUE_JUMP, "l": l, "leaps": clampi(int(e.get("leaps", 2)), 2, 3)})
		FishingEvents.SNAP:
			out.append({"k": CUE_SNAP, "l": l})
		FishingEvents.THROWN:
			out.append({"k": CUE_THROWN, "l": l})
		FishingEvents.LANDED:
			out.append({"k": CUE_LANDED, "l": l, "grade": int(e.get("grade", 0))})
		FishingEvents.DOUBLE_HOOKUP:
			var lanes: Array = e.get("lanes", [])
			out.append({"k": CUE_DOUBLE_HOOKUP, "l": -1, "lanes": lanes.duplicate()})
		FishingEvents.FRENZY:
			out.append({"k": CUE_FRENZY, "l": l})
		FishingEvents.TRIP_OVER:
			out.append({"k": CUE_TRIP_OVER, "l": -1})
	return out


## The cues the state shows since the last call (none on the first call, which only learns).
func diff(state: FishingState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := state.lanes.size()
	if not _seen or _state.size() != n:
		_learn(state)
		return out
	for l in state.lanes:
		var i := l.slot
		if i < 0 or i >= n:
			continue
		var was := _state[i]
		var now := l.state
		if now != was:
			_state_edge(out, l, was, now)
		var run := l.fish.run_active
		if run and _run[i] == 0 and l.state == FishingConst.ST_FIGHT:
			if is_jump_species(l.fish.sp):
				out.append({"k": CUE_JUMP, "l": i, "leaps": DEFAULT_LEAPS})
			else:
				out.append({"k": CUE_RUN, "l": i})
		var off := l.fish.off_line
		if off and _off[i] == 0:
			var snap := _strain[i] >= _slack[i]
			out.append({"k": CUE_SNAP if snap else CUE_THROWN, "l": i})
		if l.fish_landed > _landed[i]:
			out.append({"k": CUE_LANDED, "l": i, "grade": _newest_grade(state, i)})
		var frenzy := l.frenzy_until_t > state.t
		if frenzy and _frenzy[i] == 0:
			out.append({"k": CUE_FRENZY, "l": i})
		_state[i] = now
		_run[i] = 1 if run else 0
		_off[i] = 1 if off else 0
		_landed[i] = l.fish_landed
		_strain[i] = l.strain
		_slack[i] = l.slack
		_frenzy[i] = 1 if frenzy else 0
	if state.hookup_level >= 2 and state.hookup_level > _hookup:
		var lanes: Array = []
		for l in state.lanes:
			if l.in_fight():
				lanes.append(l.slot)
		out.append({"k": CUE_DOUBLE_HOOKUP, "l": -1, "lanes": lanes})
	_hookup = state.hookup_level
	if state.trip_over and not _trip_over:
		out.append({"k": CUE_TRIP_OVER, "l": -1})
	_trip_over = state.trip_over
	return out


func reset() -> void:
	_seen = false


func _state_edge(out: Array[Dictionary], l: FishingLaneState, was: int, now: int) -> void:
	var i := l.slot
	if now == FishingConst.ST_REEL and was == FishingConst.ST_CAST:
		out.append({"k": CUE_CAST, "l": i, "d": l.lure_d})
	elif now == FishingConst.ST_STRIKE:
		out.append({"k": CUE_BITE, "l": i})
	elif now == FishingConst.ST_FIGHT and was != FishingConst.ST_LANDING:
		out.append({"k": CUE_HOOKUP, "l": i})
	elif was == FishingConst.ST_STRIKE:
		out.append({"k": CUE_MISS, "l": i})


func _learn(state: FishingState) -> void:
	var n := state.lanes.size()
	_state.resize(n)
	_run.resize(n)
	_off.resize(n)
	_landed.resize(n)
	_strain.resize(n)
	_slack.resize(n)
	_frenzy.resize(n)
	for l in state.lanes:
		var i := l.slot
		if i < 0 or i >= n:
			continue
		_state[i] = l.state
		_run[i] = 1 if l.fish.run_active else 0
		_off[i] = 1 if l.fish.off_line else 0
		_landed[i] = l.fish_landed
		_strain[i] = l.strain
		_slack[i] = l.slack
		_frenzy[i] = 1 if l.frenzy_until_t > state.t else 0
	_hookup = state.hookup_level
	_trip_over = state.trip_over
	_seen = true


## The grade of lane `i`'s newest catch on the board (0 Landed when it has none).
static func _newest_grade(state: FishingState, i: int) -> int:
	var k := state.catches.size() / 3 - 1
	while k >= 0:
		if state.catches[3 * k] == i:
			return state.catches[3 * k + 2]
		k -= 1
	return FishingConst.GRADE_LANDED

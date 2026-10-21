class_name PhaseTracker
extends RefCounted
## Per-rider plan phase tracking on the authority (HOST or SOLO; BRIEF 3.6). The GameHost
## owns one. Times count whole game ticks (Wl.SIM_DT, game time stops while paused), so
## phase ends land on ticks and runs are deterministic.
##
## A phase ends by `duration` (fixed phases), `max_s` (open-ended phases), `end_phase`
## (requested during a tick; applied at the end of that tick) or `finished` (the game ended:
## every rider not yet in the cool-down jumps to it, skipping the rest of its plan). The
## cool-down's end marks the rider done. Phase N's first frame shows elapsed 0; a phase of
## d seconds covers round(d / 0.05) frames.
##
## The tracker also follows each rider's effective trainer mode (the phase mode, or SIM
## during a directive SIM block) and the game tick of its latest ERG<->SIM switch, which
## the DirectiveRouter's 30 s spacing rule reads (BRIEF 4.5). A replanned rider swaps to its
## pending plan at its next phase change (the phases up to the current one are identical).

const DT := Wl.SIM_DT
## "No switch yet": far enough back that every spacing check passes.
const NO_SWITCH := -1000000000


class Rider:
	extends RefCounted
	var peer: int = 0
	var plan: EffortPlan = null
	var index: int = -1
	var elapsed_ticks: int = 0
	## Game ticks spent in the phases before the current one.
	var plan_ticks: int = 0
	var prev_ended_by: String = ""
	var pending_end: bool = false
	var pending_plan: EffortPlan = null
	var done: bool = false
	## [{index, kind, mode, label, start, end, ended_by}] in game seconds (end -1 while open).
	var history: Array = []
	## Game tick at which the current directive SIM block expires (-1: none).
	var block_end_tick: int = -1
	var block_phase: int = -1
	var last_switch_tick: int = NO_SWITCH
	var mode_now: String = ""


var _riders: Dictionary = {}
var _order: Array[int] = []
var _finishing: bool = false
var _started: bool = false


## Add a rider with its finalized plan (cool-down appended). Order of calls = slot order.
func add_rider(peer: int, plan: EffortPlan) -> void:
	var r := Rider.new()
	r.peer = peer
	r.plan = plan
	_riders[peer] = r
	if not _order.has(peer):
		_order.append(peer)


func peers() -> Array[int]:
	return _order.duplicate()


func has(peer: int) -> bool:
	return _riders.has(peer)


func is_started() -> bool:
	return _started


## Enter phase 0 for every rider. Returns the changes [{peer, index, ended_by, plan_changed}].
func start() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_started = true
	for peer in _order:
		var r: Rider = _riders[peer]
		if r.plan == null or r.plan.phases.is_empty():
			continue
		_enter(r, 0, Wl.ENDED_START, 0)
		r.mode_now = r.plan.phase(0).mode
		out.append({"peer": peer, "index": 0, "ended_by": Wl.ENDED_START, "plan_changed": false})
	return out


func plan_of(peer: int) -> EffortPlan:
	var r: Rider = _riders.get(peer)
	return r.plan if r != null else null


func index_of(peer: int) -> int:
	var r: Rider = _riders.get(peer)
	return r.index if r != null else -1


## The rider's current PlanPhase (null before the start or for an unknown peer).
func phase_of(peer: int) -> PlanPhase:
	var r: Rider = _riders.get(peer)
	if r == null or r.index < 0:
		return null
	return r.plan.phase(r.index)


func elapsed_s(peer: int) -> float:
	var r: Rider = _riders.get(peer)
	return r.elapsed_ticks * DT if r != null else 0.0


func is_cooldown(peer: int) -> bool:
	var p := phase_of(peer)
	return p != null and p.kind == Wl.COOLDOWN


func is_done(peer: int) -> bool:
	var r: Rider = _riders.get(peer)
	return r != null and r.done


## True once every rider finished its cool-down.
func all_done() -> bool:
	if _order.is_empty():
		return false
	for peer in _order:
		if not (_riders[peer] as Rider).done:
			return false
	return true


## True once every rider is in its cool-down (or done).
func all_in_cooldown() -> bool:
	if _order.is_empty():
		return false
	for peer in _order:
		var r: Rider = _riders[peer]
		if not r.done and not is_cooldown(peer):
			return false
	return true


## The PhaseState a game sees in frame.phase[peer].
func state(peer: int) -> PhaseState:
	var r: Rider = _riders.get(peer)
	if r == null or r.index < 0:
		return PhaseState.new()
	return make_state(r.plan, r.index, r.elapsed_ticks, r.plan_ticks, r.prev_ended_by, r.done)


## A PhaseState for phase `index` of `plan` after `elapsed_ticks` (clients build their own
## rider's state with it). A done rider shows its cool-down at its end.
static func make_state(plan: EffortPlan, index: int, elapsed_ticks: int, plan_ticks: int = 0, prev_ended_by: String = "", done: bool = false) -> PhaseState:
	var s := PhaseState.new()
	if plan == null or plan.phase(index) == null:
		return s
	var p := plan.phase(index)
	var elapsed := elapsed_ticks * DT
	var limit := p.max_s if p.open_ended else p.duration_s
	if done:
		elapsed = limit
	s.index = index
	s.kind = p.kind
	s.mode = p.mode
	s.elapsed_s = elapsed
	s.duration_s = p.duration_s
	s.open_ended = p.open_ended
	s.min_s = p.min_s
	s.max_s = p.max_s
	s.label = p.label
	s.planned_pct = p.planned_pct_at(elapsed) if p.mode == Wl.ERG else 0.0
	s.remaining_s = maxf(limit - elapsed, 0.0)
	s.count = plan.size()
	s.plan_elapsed_s = (plan_ticks + elapsed_ticks) * DT
	s.prev_ended_by = prev_ended_by
	return s


## Ask to end `peer`'s open-ended phase at the end of the current tick. Returns "" or the
## refusal reason (Wl.REFUSE_*).
func request_end(peer: int) -> String:
	var r: Rider = _riders.get(peer)
	if r == null:
		return Wl.REFUSE_UNKNOWN_PEER
	if r.index < 0:
		return Wl.REFUSE_NO_PHASE
	var p := r.plan.phase(r.index)
	if r.done or p.kind == Wl.COOLDOWN:
		return Wl.REFUSE_COOLDOWN
	if not p.open_ended:
		return Wl.REFUSE_NOT_OPEN_ENDED
	if r.elapsed_ticks * DT < p.min_s - 1e-6:
		return Wl.REFUSE_MIN_S
	r.pending_end = true
	return ""


## Swap to `plan` (finalized; same phases up to the current one) at the next phase change.
func set_pending_plan(peer: int, plan: EffortPlan) -> void:
	var r: Rider = _riders.get(peer)
	if r != null:
		r.pending_plan = plan


func has_pending_plan(peer: int) -> bool:
	var r: Rider = _riders.get(peer)
	return r != null and r.pending_plan != null


## The game finished: every rider not in the cool-down moves to it at the end of this tick.
func finish_all() -> void:
	_finishing = true


## Advance every rider by the tick just simulated (`game_tick`, 0-based) and apply phase
## ends. Returns the changes [{peer, index, ended_by, plan_changed}] in slot order.
func advance(game_tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t_next := (game_tick + 1) * DT
	for peer in _order:
		var r: Rider = _riders[peer]
		if r.index < 0 or r.done:
			r.pending_end = false
			continue
		r.elapsed_ticks += 1
		var p := r.plan.phase(r.index)
		var ended_by := ""
		if _finishing and p.kind != Wl.COOLDOWN:
			ended_by = Wl.ENDED_FINISHED
		elif r.pending_end:
			ended_by = Wl.ENDED_END_PHASE
		elif p.open_ended and r.elapsed_ticks >= ticks(p.max_s):
			ended_by = Wl.ENDED_MAX_S
		elif not p.open_ended and r.elapsed_ticks >= ticks(p.duration_s):
			ended_by = Wl.ENDED_DURATION
		r.pending_end = false
		if ended_by == "":
			continue
		_close(r, t_next, ended_by)
		if p.kind == Wl.COOLDOWN:
			r.done = true
			continue
		var plan_changed := false
		if r.pending_plan != null:
			r.plan = r.pending_plan
			r.pending_plan = null
			plan_changed = true
		var next := r.index + 1
		if ended_by == Wl.ENDED_FINISHED:
			next = r.plan.cooldown_index() if r.plan.cooldown_index() >= 0 else r.plan.size() - 1
		next = clampi(next, 0, r.plan.size() - 1)
		r.plan_ticks += r.elapsed_ticks
		_enter(r, next, ended_by, game_tick + 1)
		out.append({"peer": peer, "index": next, "ended_by": ended_by, "plan_changed": plan_changed})
	_finishing = false
	return out


## Phase history per rider: [{index, kind, mode, label, start, end, ended_by}] (game s).
func history(peer: int) -> Array:
	var r: Rider = _riders.get(peer)
	return r.history.duplicate(true) if r != null else []


# --- trainer mode and SIM blocks (spacing, BRIEF 4.5) --------------------------------


## A directive SIM block of `block_ticks` starts at `game_tick` (a switch now).
func open_block(peer: int, game_tick: int, block_ticks: int) -> void:
	var r: Rider = _riders.get(peer)
	if r == null:
		return
	r.block_end_tick = game_tick + maxi(block_ticks, 1)
	r.block_phase = r.index
	if r.mode_now != Wl.SIM:
		r.mode_now = Wl.SIM
		r.last_switch_tick = game_tick


## A mode "ERG" request ended the block early (the block's exit switch).
func close_block(peer: int, game_tick: int) -> void:
	var r: Rider = _riders.get(peer)
	if r == null or r.block_end_tick < 0:
		return
	r.block_end_tick = -1
	r.block_phase = -1
	var p := r.plan.phase(r.index)
	if p != null and r.mode_now != p.mode:
		r.mode_now = p.mode
		r.last_switch_tick = game_tick


func block_active(peer: int, game_tick: int) -> bool:
	var r: Rider = _riders.get(peer)
	return r != null and r.block_end_tick > game_tick and r.block_phase == r.index


## SIM during a directive SIM block, else the current phase's mode ("" before the start).
func effective_mode(peer: int, game_tick: int) -> String:
	if block_active(peer, game_tick):
		return Wl.SIM
	var p := phase_of(peer)
	return p.mode if p != null else ""


## Record switches for the tick about to be simulated (call after advance()).
func update_modes(next_tick: int) -> void:
	for peer in _order:
		var r: Rider = _riders[peer]
		if r.index < 0:
			continue
		if r.block_end_tick >= 0 and (r.block_end_tick <= next_tick or r.block_phase != r.index):
			r.block_end_tick = -1
			r.block_phase = -1
		var m := effective_mode(peer, next_tick)
		if r.mode_now == "":
			r.mode_now = m
		elif m != r.mode_now:
			r.mode_now = m
			r.last_switch_tick = next_tick


func last_switch_tick(peer: int) -> int:
	var r: Rider = _riders.get(peer)
	return r.last_switch_tick if r != null else NO_SWITCH


## Game seconds since the rider's latest ERG<->SIM switch (huge if none yet).
func seconds_since_switch(peer: int, game_tick: int) -> float:
	return (game_tick - last_switch_tick(peer)) * DT


## Whole ticks for `seconds` (directive and phase times round to ticks).
static func ticks(seconds: float) -> int:
	return int(roundf(seconds / DT))


func _enter(r: Rider, index: int, ended_by: String, start_tick: int) -> void:
	r.index = index
	r.elapsed_ticks = 0
	r.prev_ended_by = ended_by if ended_by != Wl.ENDED_START else ""
	r.pending_end = false
	r.block_end_tick = -1
	r.block_phase = -1
	var p := r.plan.phase(index)
	r.history.append({
		"index": index, "kind": p.kind, "mode": p.mode, "label": p.label,
		"start": start_tick * DT, "end": -1.0, "ended_by": "",
	})


func _close(r: Rider, t: float, ended_by: String) -> void:
	if r.history.is_empty():
		return
	var h: Dictionary = r.history[r.history.size() - 1]
	h["end"] = t
	h["ended_by"] = ended_by

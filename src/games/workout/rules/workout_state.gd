class_name WorkoutState
extends RefCounted
## The whole Workout session state on one peer: the shared timeline, the course, the lead
## phase and every rider. The host advances it with WorkoutRules.step(); clients rebuild it
## from snapshots (WorkoutSnapshot) and predict their own rider. The view only reads it.

var tick: int = 0
## Plan seconds of the lead rider (everyone rides the same timeline).
var plan_t: float = 0.0
## The lead phase index (-1 before the first step).
var phase_index: int = -1
## The phases every rider rides, the platform's cool-down included as the last entry.
var phases: Array[PlanPhase] = []
var course: WorkoutCourse = null
## [lo, hi] % FTP of SIM WORK phases (Rolling road).
var band_pct: Array = [76.0, 105.0]
## peer -> WorkoutRiderState
var riders: Dictionary = {}
## Peers in slot order.
var order: Array[int] = []
## Phase indices whose sprint countdown toast went out (host).
var sprint_warned: Dictionary = {}
## Clients: the latest interval_end and sprint events (for the view).
var last_interval: Dictionary = {}
var last_sprint: Dictionary = {}


static func create(session: WorkoutSession, players: Array[PlayerSlot]) -> WorkoutState:
	var s := WorkoutState.new()
	if session != null:
		s.set_timeline(session.timeline())
		s.course = session.course
		s.band_pct = session.band_pct.duplicate()
	var sorted: Array[PlayerSlot] = []
	sorted.assign(players)
	sorted.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.slot_index < b.slot_index)
	for slot in sorted:
		s.riders[slot.peer_id] = WorkoutRiderState.from_slot(slot)
		s.order.append(slot.peer_id)
	return s


func set_timeline(p_phases: Array[PlanPhase]) -> void:
	phases = p_phases


func rider(peer: int) -> WorkoutRiderState:
	return riders.get(peer, null)


func phase(index: int) -> PlanPhase:
	if index < 0 or index >= phases.size():
		return null
	return phases[index]


## Plan time (s) at which phase `index` starts.
func phase_start_s(index: int) -> float:
	var t := 0.0
	for i in mini(index, phases.size()):
		t += phases[i].duration_s
	return t


## Seconds of the whole timeline (cool-down included).
func total_s() -> float:
	return phase_start_s(phases.size())


## True for a SIM phase that follows the course (Rolling road).
func is_course_phase(index: int) -> bool:
	var p := phase(index)
	return p != null and p.mode == Wl.SIM and p.grade_source == Wl.GRADE_COURSE

class_name TankSegmentState
extends TankRecord
## Where the crew is in the mission (G0 contract): the segment the group's phase points at, its
## objective and the hold before min_s. The rules write it from TankInputs.phase; the director
## reads objective_done and calls end_phase for every rider in one step once min_s has passed
## (ADR "Who calls end_phase").

## TankIds.SEG_* (the snapshot carries its code).
var seg: String = TankIds.SEG_NONE
## [snap] Stage 1..3, 4 for the boss, 0 for the hangar and the roll-out.
var stage: int = 0
## [snap] The plan phase index (the group's: the lowest any rider is in); -1 before the start.
var phase_index: int = -1
## The mission segment index (== phase_index while in the plan; -1 in the cool-down).
var segment_index: int = -1
var kind: String = ""
## [snap] Seconds into the phase (the group's).
var elapsed_s: float = 0.0
var min_s: float = 0.0
var max_s: float = 0.0
var open_ended: bool = false
## Game seconds since the plan started (abilities and haptics are off below 300 s).
var plan_elapsed_s: float = 0.0
## [snap] The segment's objective is met (Advance: the halt line reached; gun line: every gun
## down; boss: the Behemoth dead; fixed phases: never).
var objective_done: bool = false
## [snap] The objective is met but min_s has not passed: the tank holds ("Regroup").
var regroup: bool = false
## [snap] The previous phase ended at max_s (PhaseState.prev_ended_by == "max_s").
var overrun: bool = false
## The Advance's length in game metres (0 elsewhere).
var length_m: float = 0.0
## The next encounter of the Advance to trigger (index into the mission segment's list).
var next_encounter: int = 0
## v4: the next entry of the segment's "near" list (by elapsed_s).
var next_near: int = 0

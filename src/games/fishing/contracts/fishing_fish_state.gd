class_name FishingFishState
extends FishingRecord
## The fish on one rider's line (contract v2). FishingRules owns every change; the snapshot
## carries species, dx, depth and S; the view draws from those.

var sp: int = FishingConst.SP_NONE
## Index of the FishingPlanSlot this fish belongs to (-1 none).
var slot: int = -1
## Stamina S, 1 at hook-set, 0 spent.
var s: float = 1.0
## Distance behind the stern (m) and relative depth z (0 the surface .. 1 the hook depth).
var d: float = 0.0
var z: float = 0.0
var d_max: float = 0.0
## The depth the fish was hooked at (m); depth_m() = z x hook_depth_m.
var hook_depth_m: float = 0.0
## Bite strength (0..1).
var strength: float = 0.0
## A same-species replacement after a snap or a thrown hook: x 0.75 kg, never a trophy.
var replacement: bool = false
## Scheduled fish (Threshold, e2e): never a trophy.
var scheduled: bool = false
## Runs (or jumps) fired so far, 0..n; the next fires at S = 1 - (fired + 1) / (n + 1).
var runs_fired: int = 0
## True from a run's first ramp step to its scheduled end.
var run_active: bool = false
var run_end_t: float = 0.0
var last_jump_t: float = -1000.0
var hooked_t: float = 0.0
var replace_at_t: float = -1.0
## True while no fish is on the line between a loss and its replacement.
var off_line: bool = false
var kg: float = 0.0


func depth_m() -> float:
	return z * hook_depth_m

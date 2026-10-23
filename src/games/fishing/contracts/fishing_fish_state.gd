class_name FishingFishState
extends FishingRecord
## The fish on one rider's line (brief 2.4 "Fight state"; G0 contract). FishingRules owns every
## change; the snapshot carries species, d, z and S; the view draws from those.

var sp: int = FishingConst.SP_NONE
## Index of the FishingPlanSlot this fish belongs to (-1 none).
var slot: int = -1
## Stamina S, 1 at hook-set, 0 spent.
var s: float = 1.0
## Distance from the rod tip (m) and depth (0 surface, 1 reef).
var d: float = 0.0
var z: float = 0.0
var d_max: float = 0.0
## Spot strength at the bite (0..1); kg = slot kg x (1 + 0.15 x strength), x 0.75 replacement.
var strength: float = 0.0
## A same-species replacement after a snap or a thrown hook: x 0.75 kg, never a trophy.
var replacement: bool = false
## Scheduled fish (Threshold, e2e): never a trophy.
var scheduled: bool = false
## Runs (or jumps) fired so far, 0..n; the next fires at S = 1 - (fired + 1) / (n + 1).
var runs_fired: int = 0
## True from a run's first ramp step to its scheduled end.
var run_active: bool = false
## Game time of the active run's scheduled end.
var run_end_t: float = 0.0
## Game time the last jump started (marlin spacing).
var last_jump_t: float = -1000.0
## Game time of the hook-set and of a pending replacement (-1 none).
var hooked_t: float = 0.0
var replace_at_t: float = -1.0
## True while no fish is on the line between a loss and its replacement.
var off_line: bool = false
## This fish's weight: slot kg x (1 + 0.15 x strength), x 0.75 for a replacement (fish-rules,
## additive).
var kg: float = 0.0

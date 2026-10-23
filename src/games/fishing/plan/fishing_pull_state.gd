class_name FishingPullState
extends FishingRecord
## One lane's pull-scheduler state (brief 2.3 directives). G0 stub: fish-plan owns this file and
## FishingPullScheduler, and may add fields; FishingLaneState holds one per lane and FishingRules
## passes it to the scheduler every tick of a Fight.

## The Fight's base pull and the target last requested (% FTP).
var base_pct: float = 0.0
var target_pct: float = 0.0
## Game time of the next pull change (the clock stops during runs and staggers).
var next_change_t: float = 0.0
## Ramp steps still to send, flat: [due_t, target_pct, duration_s, ...].
var queue: Array[float] = []
## A run or jump: active from its first ramp step to run_end_t.
var run_active: bool = false
var run_end_t: float = 0.0
## The pull-change clock is stopped until this game time (run end, or stagger end + 10 s).
var paused_until_t: float = 0.0
var staggered: bool = false
## Seconds above 105 % (by the requested target) in this run and in this fight.
var above_105_run_s: float = 0.0
var above_105_fight_s: float = 0.0

class_name FishingPullState
extends FishingRecord
## One lane's pull-scheduler state (brief 2.3 "Load changes"). FishingLaneState holds one per lane;
## FishingRules seeds it once with FishingPullScheduler.init_lane() and passes it, with `rng`, to
## the scheduler every tick of a Fight. fish-plan owns this file and FishingPullScheduler.
##
## The scheduler keeps a model of the governor's ERG target channel for this lane (`target_pct`,
## `expiry_t`): a request replaces the channel; a request with duration_s > 0 expires back to the
## phase's planned target, which is the Fight's base pull. Rescue and AFK never change the channel
## (SDK 8), so the model holds through a stagger.

## The Fight's base pull (% FTP): the phase's planned target, where an expired run lands.
var base_pct: float = 0.0
## The governor's ERG channel as this lane last set it (% FTP), and when it expires back to
## base_pct (0 = held until replaced: a pull change).
var target_pct: float = 0.0
var expiry_t: float = 0.0
## Game time of the next pull change (valid while the clock runs).
var next_change_t: float = 0.0
## True after a pause (run, stagger, the 10 s after a stagger): the next running tick draws a
## fresh 8-16 s interval from that tick.
var clock_fresh: bool = false
## Ramp steps still to send, flat: [due_t, target_pct, run (1.0) or pull (0.0), ...]. A run step's
## duration_s is computed when it is sent: the seconds left to run_end_t.
var queue: Array[float] = []
## A run or jump: active from start_run() to run_end_t. FishingRules reads run_active and
## run_end_t for the fish's run state.
var run_active: bool = false
var run_end_t: float = 0.0
## The active (or last) run: its index k, start time and peak after every cap (% FTP).
var run_k: int = -1
var run_start_t: float = -1.0e9
var run_peak_pct: float = 0.0
## Start of the previous run or jump (marlin jumps start >= run_min_gap_s apart).
var last_run_start_t: float = -1.0e9
## The pull-change clock is stopped until this game time (stagger end + 10 s).
var paused_until_t: float = 0.0
## A rescue or AFK is on: no request at all.
var staggered: bool = false
## Game time of the last directive sent (at most 2 writes a second: >= 0.5 s apart).
var last_send_t: float = -1.0e9
## Seconds above 105 % reserved by this run and by this fight: a run whose peak is above 105 %
## reserves its whole length, ramps included (<= 30 s per run, <= 90 s per fight).
var above_105_run_s: float = 0.0
var above_105_fight_s: float = 0.0
## Runs started and runs skipped (start_run() while staggered) in this fight.
var runs_started: int = 0
var runs_skipped: int = 0
## Directives sent in this fight (debugging and tests).
var sent: int = 0

## The lane's pull stream: FishingRandom.derive(ctx.seed, slot index, STREAM_PULL). Not saved by
## to_dict() (an Object).
var rng: FishingRandom = FishingRandom.new()

## The Array step() returns, reused every tick (no allocation per tick).
var _out: Array = []

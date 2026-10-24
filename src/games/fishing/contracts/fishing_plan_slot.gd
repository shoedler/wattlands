class_name FishingPlanSlot
extends FishingRecord
## One fight of one rider (contract v2). Workouts pre-roll them at configure time from ctx.seed
## and the slot index (Base) or the trip's schedule (Threshold, e2e); Free Roam builds one at
## each bite from the hooked fish (FishingPreroll.roam_slot). FishingPlanBuilder turns each into
## a Fight and a Landing phase; FishingRules and FishingPullScheduler read them during the fight.

## 0-based position in the rider's slot list; the Fight phase label uses index + 1.
var index: int = 0
var species: String = ""
## FishingConst.SPECIES index of `species`.
var sp: int = FishingConst.SP_NONE
## The plan-time draw w in [0, 1].
var w: float = 0.0
## Base pull in % FTP: lo + w x (hi - lo), after the trip's top_pct cap.
var base_pct: float = 0.0
## a: pull changes move the target by up to +-change_pct % of the base pull.
var change_pct: float = 0.0
## T_nom = lo + 0.8 x w x (hi - lo) (scheduled trips: the schedule's value).
var t_nom_s: float = 0.0
## The Fight phase's open-ended bounds: min_s = floor(0.8 x T_nom), max_s = the species' max_s.
var min_s: float = 0.0
var max_s: float = 0.0
## The Fight phase's range_pct.
var range_lo: float = 0.0
var range_hi: float = 0.0
## FishingSpeciesDef.RUN_NONE / RUN_RUN / RUN_JUMP.
var run_kind: String = FishingSpeciesDef.RUN_NONE
## Pre-rolled runs (or jumps) in firing order, flat: [dur_s, peak_pct, dur_s, peak_pct, ...].
## Run k (1-based) of n fires when stamina falls to 1 - k / (n + 1) (FishingRules).
var runs: Array[float] = []
## Leaps per jump, in the same order (jumps only; [] otherwise).
var leaps: Array[int] = []
## Band shift during a run (rpm).
var run_band_shift: float = 0.0
## Minimum seconds between jump starts (90 for jumpers; 0 otherwise).
var run_min_gap_s: float = 0.0
## Tension and lure band offset from the preferred cadence (rpm).
var band_offset: float = 0.0
## The fish's drawn weight before strength and replacement factors.
var kg: float = 0.0
## Scheduled fish (Threshold, e2e): hook themselves, never a trophy.
var scheduled: bool = false
## Fixed Reel before this fight (scheduled trips); 0 = an open-ended Reel (Base) or none.
var reel_s: float = 0.0
## Pull changes may hold the target above 105 % (base pull above 105 % in a phase of <= 300 s:
## the giant grouper); otherwise pull changes stay <= 105 % and only runs pass it.
var hold_above_105: bool = false
## The fish's depth at the bite (m; workouts: the trolled lure's depth).
var depth_m: float = 0.0
## The farthest the fish swims from the boat in the fight (m; the species' d_max).
var d_max: float = 0.0


func run_count() -> int:
	return runs.size() / 2


## Duration of run k (0-based).
func run_dur_s(k: int) -> float:
	return runs[2 * k]


## Peak of run k (0-based) in % FTP.
func run_peak_pct(k: int) -> float:
	return runs[2 * k + 1]


## The fight's worst-case budget cost: T_nom + 30 s (brief 2.3 pre-roll and last call).
func budget_s() -> float:
	return t_nom_s + FishingConst.SLOT_GAP_S

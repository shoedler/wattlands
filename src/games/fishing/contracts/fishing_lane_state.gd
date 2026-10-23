class_name FishingLaneState
extends FishingRecord
## One rider's lane: boat, lure, fish, meters and stats (brief 2.2, 2.4; G0 contract).
## FishingRules owns every change on the host; clients overwrite what the snapshot carries
## (FishingSnapshotSchema) and predict only cadence_ema for their own lane. Fields may be added
## (additively, through the lead); none is renamed or removed.

# --- Identity ------------------------------------------------------------------------------
var slot: int = 0
var peer: int = 0
var is_bot: bool = false
var ftp: float = 200.0
var preferred_rpm: float = 90.0
var relaxed_band: bool = false
var reel_pct: int = FishingConst.REEL_PCT_DEFAULT
var haptics_on: bool = true

# --- Phase and state ---------------------------------------------------------------------
var state: int = FishingConst.ST_RIDE_OUT
var phase_index: int = 0
var phase_kind: String = ""
## Seconds in the current lane state (strike prompt, cast flight, landing clock, ...).
var state_t: float = 0.0
## The rider's pre-rolled fights; next_slot is the next one to bite (== slots.size(): none left).
var slots: Array[FishingPlanSlot] = []
var next_slot: int = 0
## The slot whose fish is on the line (-1 none).
var fight_slot: int = -1

# --- Inputs, smoothed ----------------------------------------------------------------------
var power_w: float = 0.0
var cadence_ema: float = 0.0
var cadence_stale: bool = false
var applied_target_w: float = 0.0
var rescue: bool = false
var afk: bool = false
## Telemetry older than 3 s (a dropped client): AFK whether or not on_afk fired.
var stale: bool = false
## Game time play resumes after a rescue or AFK (play resumes 10 s after it ends; 0 = none).
var resume_t: float = 0.0
## True from a rescue's or AFK's start until resume_t.
var staggered: bool = false

# --- Zero input (2.5) ----------------------------------------------------------------------
## Autopilot on (slot flag; bots).
var autopilot: bool = false
## No deliberate Fishing intent yet: plays as Autopilot for picks, casts and strikes.
var fallback: bool = true

# --- Bands -------------------------------------------------------------------------------
## The tension band now (slides at <= 3 rpm/s toward its target).
var band_center: float = 0.0
var band_lo: float = 0.0
var band_hi: float = 0.0
## The band last published with cadence_band (rounded ints; 0, 0 = cleared).
var pub_lo: int = 0
var pub_hi: int = 0

# --- Spots and reel ------------------------------------------------------------------------
## Hints while picking, flat: [type, distance_m, strength, type, distance_m, strength, ...].
var hints: Array[float] = []
## The highlighted hint (pedal-scan or left/right), -1 none.
var selected: int = -1
var scan_t: float = 0.0
var scan_pause_t: float = 0.0
## Seconds picking without a pick (auto-confirm after two scan cycles).
var pick_t: float = 0.0
## The cast spot's type and strength (the spot sets how fast the fish bites and how heavy).
var spot_type: int = -1
var spot_strength: float = 0.0
var lure_d: float = 0.0
## Seconds in the current Reel phase (R_min counts from its start).
var reel_t: float = 0.0
var r_min_s: float = FishingConst.R_MIN_S
## Game time of a re-bite after a miss (-1 none) and of a frenzy's end (0 none).
var rebite_t: float = -1.0
var frenzy_until_t: float = 0.0

# --- Fight -------------------------------------------------------------------------------
var fish: FishingFishState = FishingFishState.new()
var strain: float = 0.0
var slack: float = 0.0
var fight_t: float = 0.0
## Game time the current fight started (hookup overlap) and its overlap peak so far.
var fight_start_t: float = -1.0
var hookup_count: int = 1
## Fight seconds used so far (the 40 % / 25 % cap counts T_nom + 30 s per started slot).
var fight_budget_used_s: float = 0.0
## Actual length of the previous fight, Landing included (R_min = k x this).
var last_fight_len_s: float = 0.0

# --- Landing -----------------------------------------------------------------------------
var landing_t: float = 0.0
var gaff: float = 0.0
## Game time into the sprint the last-run haptic is due (seeded 3-6 s), and whether it went.
var haptic_at_s: float = 0.0
var haptic_sent: bool = false

# --- Scheduler -----------------------------------------------------------------------------
var pull: FishingPullState = FishingPullState.new()

# --- Look --------------------------------------------------------------------------------
## Equipped cosmetics as indexes into each kind of cosmetics.json (0 = the default look):
## [line, canopy, trim, pennant].
var cosmetics: Array[int] = [0, 0, 0, 0]
## Species records from the rider's summary intent: species id -> kg.
var records: Dictionary = {}
var summary_xp: int = 0

# --- Stats (2.8) ----------------------------------------------------------------------------
var points: int = 0
var fish_landed: int = 0
var trophies: int = 0
var lost_lines: int = 0
var fights_started: int = 0
var band_s: float = 0.0  ## seconds in the tension band during fights
var fight_total_s: float = 0.0  ## seconds in fights
var biggest_kg: float = 0.0
var biggest_sp: int = FishingConst.SP_NONE
var longest_fight_s: float = 0.0
var new_records: int = 0
## Catch log of this session: [{sp, kg, grade, fight_s, points}].
var catches: Array = []

# --- Randomness --------------------------------------------------------------------------
var rng: FishingRandom = FishingRandom.new()

# --- Rules bookkeeping (fish-rules, additive) ----------------------------------------------
## The pull scheduler's stream, (seed, slot, STREAM_PULL), passed to begin() and step().
var pull_rng: FishingRandom = FishingRandom.new()
## The cadence EMA has taken its first sample (it starts at the first value, not at 0).
var ema_ready: bool = false
## A rescue, AFK or stale telemetry is on right now (staggered also covers the 10 s after).
var stagger_on: bool = false
## Effective rescue now: the module's on_rescue flag or the telemetry's (haptic rule).
var rescue_now: bool = false
## The hook is set in this Reel (end_phase requested or, in scheduled trips, the fish hooked
## itself); the Fight starts with the next phase.
var hook_set: bool = false
## end_phase was requested in the current phase (it is sent once).
var end_sent: bool = false
## The scheduled bite of this Reel came.
var sched_bit: bool = false
## Ride-out tips shown so far.
var tip_n: int = 0
## Cadence (EMA) inside the current published tension band (fights) or lure band (reels).
var in_band: bool = false
## Seconds this fight overlapped >= n fights (index n = 2..4).
var overlap_s: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
## The Landing's catch was scored.
var resolved: bool = false
## The first summary intent was stored (later ones are ignored).
var summary_received: bool = false
## Species (FishingConst.SPECIES indexes) whose record this session beat (new_records counts them).
var record_species: Array[int] = []


## True while the lane plays the fish for the rider (Autopilot or the zero-input fallback).
func auto_plays() -> bool:
	return autopilot or fallback or is_bot


func hint_count() -> int:
	return hints.size() / 3


func in_fight() -> bool:
	return state == FishingConst.ST_FIGHT or state == FishingConst.ST_LANDING

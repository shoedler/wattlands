class_name FishingRiderState
extends FishingRecord
## One rider: boat, menu, lure, fish, meters and stats (contract v2). FishingRules owns every
## change on the host; clients overwrite what the snapshot carries (FishingSnapshotSchema) and
## predict only cadence_ema for their own rider. The view reads these fields (host and clients).

# --- Identity ------------------------------------------------------------------------------
var slot: int = 0
var peer: int = 0
var is_bot: bool = false
var ftp: float = 200.0
var preferred_rpm: float = 90.0
var relaxed_band: bool = false
var reel_pct: int = FishingConst.REEL_PCT_DEFAULT
var haptics_on: bool = true
## Autopilot on (slot flag; bots): the rules make this rider's choices.
var autopilot: bool = false
## PlayerSlot.pedal_nav: the menu scans, a surge confirms and the menu auto-confirms.
var pedal_nav: bool = false
## Bot strategy (FishingBot.STRATEGIES index), -1 for humans and in workouts.
var strategy: int = -1

# --- Boat (FishingBoat) ----------------------------------------------------------------------
## Position along the map (m, 0 = the dock) and signed speed (m/s, + = seaward).
var x_m: float = 0.0
var v_mps: float = 0.0
## +1 out to sea, -1 toward the dock (the bow's direction).
var heading: int = 1
## Signed pitch (degrees, + bow up, - bow down while braking) and its rate (deg/s), heave (m,
## + the hull rides higher) and its rate (m/s): FishingBoat's rigid body on the water.
var pitch_deg: float = 0.0
var pitch_rate: float = 0.0
var heave_m: float = 0.0
var heave_rate: float = 0.0
## Planing level 0..1 (displacement .. fully on the plane) and the planing latch (hysteresis:
## set above FishingConst.PLANE_ON_MPS, cleared under PLANE_OFF_MPS).
var plane: float = 0.0
var planing: bool = false
## The prop's depth below the surface at the transom (m), always >= FishingConst.PROP_MIN_M.
var prop_depth_m: float = FishingConst.PROP_REST_M
## Line tension (N, 0 with no fish on): FishingBoat tows the boat along the line with it.
var tow_n: float = 0.0
## Braking intensity (0..1) and wake intensity (0..1).
var brake: float = 0.0
var wake: float = 0.0
## Effective power now (Telemetry.p_eff_w) and the last step's acceleration (m/s^2, signed).
var p_eff_w: float = 0.0
var accel: float = 0.0
## The farthest x reached this session (results: furthest out).
var furthest_x_m: float = 0.0

# --- Action ----------------------------------------------------------------------------------
## FishingConst.A_DRIVE .. A_HOME.
var action: int = FishingConst.A_DRIVE
## Seconds in the current action.
var state_t: float = 0.0
var phase_index: int = -1
var phase_kind: String = ""

# --- Menu (Free Roam) ----------------------------------------------------------------------
## The menu entries (FishingSnapshotSchema.R_MENU) and the highlighted one (-1 none).
var menu: Array[int] = []
var selected: int = -1
var scan_t: float = 0.0
var scan_pause_t: float = 0.0
## Seconds in the menu without a pick, and seconds pedaling hard in it (drive on).
var menu_t: float = 0.0
var drive_on_t: float = 0.0
## The fish on offer here, flat: [species, dx_m, depth_m, w, ...] (w: size 0..1).
var hints: Array[float] = []
## The x where the hints were drawn (-INF: none yet).
var hints_x: float = -INF
## Autopilot and bots: stop at this x (NAN: no stop planned).
var stop_x: float = NAN
## The menu opened right after a catch (Autopilot may move on).
var just_landed: bool = false

# --- Lure ------------------------------------------------------------------------------------
## The species fished for (A_CAST, A_WAIT; -1 none) and the cast hint's size w.
var target_sp: int = FishingConst.SP_NONE
var target_w: float = 0.0
## The wobbler: dx from the boat and depth (m); it dives to lure_target_depth in cast_s.
var lure_dx: float = 0.0
var lure_depth: float = 0.0
var lure_target_depth: float = 0.0
var cast_s: float = 0.0
## Seconds at depth waiting (Free Roam) or in the current Reel phase (workouts; R_min counts
## from its start).
var wait_t: float = 0.0
## The jig (Free Roam): the cast hint's signed dx the lure is retrieved from, seconds into the
## retrieve, and the recast flag (a recast keeps wait_t).
var jig_dx0: float = 0.0
var jig_t: float = 0.0
var recasting: bool = false
var r_min_s: float = FishingConst.R_MIN_S

# --- Fights (both modes) ---------------------------------------------------------------------
## The rider's fights: pre-rolled (workouts) or built at each bite (Free Roam: appended).
## next_slot is the next one to start (== slots.size(): none left); fight_slot the one on.
var slots: Array[FishingPlanSlot] = []
var next_slot: int = 0
var fight_slot: int = -1
var fish: FishingFishState = FishingFishState.new()
var strain: float = 0.0
var slack: float = 0.0
var fight_t: float = 0.0
var fight_start_t: float = -1.0
## Workouts: fights overlapping this one (its own included) for 10 s, 1..4.
var hookup_count: int = 1
var overlap_s: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
## Workouts: fight seconds used (the fight budget) and the previous fight's length.
var fight_budget_used_s: float = 0.0
var last_fight_len_s: float = 0.0
## Free Roam: seconds above 105 % the plan has accrued since its last reset (PlanValidator's
## rule: open-ended phases at max_s); a fight that would pass 300 s caps at 105 %.
var acc105_s: float = 0.0
## The hook is set: the Fight starts with the next phase (end_phase sent, or scheduled).
var hook_set: bool = false
var end_sent: bool = false
var sched_bit: bool = false
var landing_t: float = 0.0
var gaff: float = 0.0
var haptic_at_s: float = 0.0
var haptic_sent: bool = false
## A big fish's surge cue (F_SURGE) is on until this time (s; -1 none); `surging` is the flag
## (clients get it from the snapshot).
var surge_end_t: float = -1.0
var surging: bool = false
## Reel-in progress 0..1 (reel_progress(), R_REEL).
var reel: float = 0.0
## The Landing's catch was scored.
var resolved: bool = false
var pull: FishingPullState = FishingPullState.new()

# --- Inputs, smoothed ----------------------------------------------------------------------
var power_w: float = 0.0
var cadence_ema: float = 0.0
var ema_ready: bool = false
var cadence_stale: bool = false
var applied_target_w: float = 0.0
var rescue: bool = false
var afk: bool = false
var paused: bool = false
## The telemetry's own AFK flag this tick (afk is the module's on_afk).
var afk_tm: bool = false
## Telemetry older than 3 s (a dropped client): AFK whether or not on_afk fired.
var stale: bool = false
var rescue_now: bool = false
## A rescue, AFK, pause or stale telemetry is on (stagger_on); staggered also covers the 10 s
## after it ends (resume_t).
var stagger_on: bool = false
var staggered: bool = false
var resume_t: float = 0.0

# --- Bands and trainer -----------------------------------------------------------------------
var band_center: float = 0.0
var band_lo: float = 0.0
var band_hi: float = 0.0
## The band last published with cadence_band (rounded ints; 0, 0 = cleared).
var pub_lo: int = 0
var pub_hi: int = 0
var in_band: bool = false
## The course grade last sent (NAN: none yet) and the tick it went out.
var grade_sent: float = NAN
var grade_tick: int = -1000
## Bots: the power band centre last published (W; a bot rides it in SIM), -1 none.
var pub_pw: int = -1

# --- Look and records ----------------------------------------------------------------------
## Equipped cosmetics as indexes into each kind of cosmetics.json: [line, canopy, trim, pennant].
var cosmetics: Array[int] = [0, 0, 0, 0]
## Species records from the rider's summary intent: species id -> kg.
var records: Dictionary = {}
var summary_xp: int = 0
var summary_received: bool = false
## Species whose record this session beat.
var record_species: Array[int] = []

# --- Stats ------------------------------------------------------------------------------------
var points: int = 0
var fish_landed: int = 0
var trophies: int = 0
var lost_lines: int = 0
var fights_started: int = 0
var band_s: float = 0.0
var fight_total_s: float = 0.0
var biggest_kg: float = 0.0
var biggest_sp: int = FishingConst.SP_NONE
var longest_fight_s: float = 0.0
var new_records: int = 0
## Catch log of this session: [{sp, kg, grade, fight_s, points}].
var catches: Array = []
## Warm-up tips shown so far.
var tip_n: int = 0

# --- Randomness ------------------------------------------------------------------------------
var rng: FishingRandom = FishingRandom.new()
var pull_rng: FishingRandom = FishingRandom.new()


## AFK by any source: on_afk, the telemetry, or stale telemetry (a dropped client).
func is_afk() -> bool:
	return afk or afk_tm or stale


## True while the rules make this rider's choices (Autopilot on, or a bot).
func auto_plays() -> bool:
	return autopilot or is_bot


func hint_count() -> int:
	return hints.size() / 4


func in_fight() -> bool:
	return action == FishingConst.A_FIGHT or action == FishingConst.A_LAND


## The fish on the line's dx from the boat (behind the stern).
func fish_dx() -> float:
	return -float(heading) * fish.d


## Reel-in progress 0..1 in a fight or landing: 1 - line / full line (hypot(d_max, hook
## depth)), consistent with line_m(); 0 with no fish on. The host's rules store it in `reel`
## each step (clients get `reel` from R_REEL: they do not know d_max).
func reel_progress() -> float:
	if not in_fight() or fish.sp < 0:
		return 0.0
	var full := Vector2(maxf(fish.d_max, fish.d), fish.hook_depth_m).length()
	if full <= 0.0:
		return 1.0
	return clampf(1.0 - line_m() / full, 0.0, 1.0)


## Line paid out (m): to the fish in a fight or landing, to the wobbler otherwise.
func line_m() -> float:
	if in_fight() and fish.sp >= 0:
		return Vector2(fish.d, fish.depth_m()).length()
	if action == FishingConst.A_CAST or action == FishingConst.A_WAIT:
		return Vector2(lure_dx, lure_depth).length()
	return 0.0

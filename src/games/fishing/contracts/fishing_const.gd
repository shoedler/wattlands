class_name FishingConst
extends RefCounted
## Every number of Turbo Reel's rules, in one place (brief docs/games/fishing.md 2.3-2.8;
## G0 contract, changed only through the lead). Rules, plans, tests and the view read these names
## instead of repeating literals. Times are game seconds, cadences rpm, distances metres,
## percentages % of the rider's own FTP.

# --- Lane states (FishingLaneState.state; the snapshot carries the int) ---------------------
const ST_RIDE_OUT := 0  ## WARMUP phase: motoring out, practice band, no bites
const ST_PICK := 1  ## Reel phase: choosing among the hints (pedal-scan or left/right)
const ST_CAST := 2  ## the lure is flying to the spot (CAST_S); hazard 0
const ST_REEL := 3  ## the lure is coming in; bites can come
const ST_STRIKE := 4  ## a fish bit: the 4 s strike prompt
const ST_FIGHT := 5  ## Fight phase: tension band, meters, tiring
const ST_LANDING := 6  ## Landing phase (SIM flat): gaff sprint, then easy spin
const ST_IDLE := 7  ## Reel phase with no fish to come: last call, slots used up, fishing over
const ST_HOME := 8  ## cool-down: motoring home
const STATE_NAMES := [
	"ride_out", "pick", "cast", "reel", "strike", "fight", "landing", "idle", "home"
]

# --- Species (wire ids; index = position) -----------------------------------------------
const SPECIES := ["mackerel", "mahi", "tuna", "marlin"]
const SP_NONE := -1

# --- Spot types (wire ids; index = position) ---------------------------------------------
const SPOTS := ["bird_pile", "current_seam", "reef_edge", "drop_off"]
const SPOT_BIRD_PILE := 0
const SPOT_CURRENT_SEAM := 1
const SPOT_REEF_EDGE := 2
const SPOT_DROP_OFF := 3
const HINTS_PER_CAST := 3
const SPOT_D_MIN := 40.0
const SPOT_D_MAX := 80.0
const STRENGTH_JITTER_LO := 0.7  ## strength = affinity x U[0.7, 1.0]
const STRENGTH_STEPS := 4  ## 1-4 gulls, 1-4 marks, or a longer seam

# --- Trip kinds (FishingTripDef.kind) ----------------------------------------------------
const TRIP_FREE := "free"
const TRIP_BASE := "base"
const TRIP_THRESHOLD := "threshold"
const TRIP_E2E := "e2e"

# --- Plan (2.3) ----------------------------------------------------------------------------
const RIDE_OUT_S := 300.0
const RIDE_OUT_PCT := 50.0
const RIDE_OUT_RAMP_TO := 65.0
const REEL_PCT_DEFAULT := 60
const REEL_PCT_MIN := 50
const REEL_PCT_MAX := 70
const REEL_MIN_S := 120.0  ## open-ended Reel min_s (= the earliest bite)
const REEL_NOMINAL_S := 240.0  ## open-ended Reel duration_s, for the timeline only
const FIGHT_MIN_FRAC := 0.8  ## Fight min_s = floor(0.8 x T_nom)
const T_NOM_W_FRAC := 0.8  ## T_nom = lo + 0.8 x w x (hi - lo)
const LANDING_S := 30.0
const GAFF_S := 15.0
const SLOT_GAP_S := 30.0  ## each fight slot costs T_nom + 30 s of the fight budget
const LAST_CALL_OVERRUN_S := 300.0  ## a fight must end <= 5 min after fishing ends
const JUMP_SPACING_S := 115.0  ## jumps = min(rolled, floor(T_nom / 115 s))
const SELF_CAP_PCT := 110.0  ## nothing above 110 %, ever
const LONG_PHASE_CAP_PCT := 105.0  ## BRIEF 4.6.1: phases longer than 300 s (open-ended: max_s)
const MARLIN_JUMP_PCT := 104.0  ## a point of margin under the 105 % cap
const BASE_TOP_PCT := 100.0  ## base_60: nothing above 100 %

# --- Pull scheduler (2.3) -------------------------------------------------------------------
const PULL_CHANGE_MIN_S := 8.0
const PULL_CHANGE_MAX_S := 16.0
const RAMP_S := 3.0
const RAMP_STEPS := 6
const RAMP_STEP_S := 0.5  ## BRIEF 4.5: at most 2 writes a second
const RAMP_MAX_W_PER_S := 25.0  ## under the governor's 30 W/s slew
const RUN_MAX_ABOVE_105_S := 30.0
const FIGHT_MAX_ABOVE_105_S := 90.0
const PULL_RESUME_AFTER_STAGGER_S := 10.0

# --- Cadence and bands (2.4) ---------------------------------------------------------------
const CADENCE_TAU_S := 1.0  ## EMA time constant for band tests
const STALE_S := 3.0  ## stale cadence freezes the meters; stale telemetry makes the lane AFK
const PRACTICE_HALF := 8.0  ## ride-out practice band: preferred +- 8
const LURE_HALF := 8.0  ## lure band: preferred + species offset +- 8
const BAND_WIDTH := 16.0
const BAND_WIDTH_RELAXED := 22.0
const BAND_LOW_HALF := 8.0  ## low edge = max(65, center - 8); high = low + width
const BAND_LOW_MIN := 65.0  ## above BRIEF 4.6.3's 45 rpm rescue trigger
const BAND_STAMINA_RPM := 10.0  ## center - 10 x (1 - S)
const BAND_SLIDE_RPM_S := 3.0

# --- Reel and bites (2.4) -------------------------------------------------------------------
const CAST_S := 1.5
const LURE_MPS := 0.35  ## x cadence / 90
const LURE_REF_RPM := 90.0
const RECAST_D := 5.0
const HAZARD_BASE := 0.35
const HAZARD_STRENGTH := 0.65
const HAZARD_DIV_S := 90.0
const HAZARD_OUT_OF_BAND := 0.25
const R_MIN_S := 120.0
const FORCED_BITE_AFTER_S := 240.0  ## a bite is forced at R_min + 240 s
const FRENZY_S := 60.0
const FRENZY_MULT := 2.0
const SCHEDULED_BITE_LEAD_S := 4.0
const STRIKE_WINDOW_S := 4.0
const AUTOPILOT_STRIKE_S := 0.5
const REBITE_MIN_S := 20.0
const REBITE_MAX_S := 40.0
const SCAN_INTERVAL_S := 1.6  ## the pedal-scan highlight step (PedalScanList's default)
const SCAN_PAUSE_S := 10.0  ## left/right pause the scan
const AUTO_CONFIRM_CYCLES := 2  ## a pick auto-confirms after two full scan cycles

# --- Fight (2.4) ---------------------------------------------------------------------------
const D_NEAR := 10.0  ## d moves toward 10 + (d_max - 10) x S
const D_OUT_MPS := 4.0
const D_IN_MPS := 2.0
const Z_BASE := 0.25  ## z moves toward 0.25 + 0.75 x S, or 1 on a run
const METER_FILL_S := 6.0  ## strain or slack fills at 1/6 per second
const METER_DRAIN_S := 12.0  ## the other drains at 1/12 per second
const TIRE_MAX_RATIO := 1.2  ## dS/dt = -min(1.2, P / applied target) / T_nom in band
const RECOVER_RATE := 0.25  ## +0.25 / T_nom out of band
const REPLACEMENT_DELAY_S := 5.0
const REPLACEMENT_KG := 0.75
const STAGGER_RESUME_S := 10.0  ## play resumes 10 s after rescue or AFK ends
const SWIM_OUT_MPS := 1.0

# --- Landing (2.4, 2.7) ---------------------------------------------------------------------
const GAFF_CP_FRAC := 0.4  ## fill = integral max(0, P - CP) dt / (0.4 x CP x 15 s)
const SPRINT_FTP_FRAC := 1.2  ## counted only while P >= 1.2 x FTP (BRIEF 3.5)
const HAPTIC_PCT := 3.0
const HAPTIC_S := 5.0
const HAPTIC_AT_MIN_S := 3.0
const HAPTIC_AT_MAX_S := 6.0
const HAPTIC_PLAN_MIN_S := 300.0  ## never in the first 300 s of the plan

# --- Points, grades, XP (2.4, 2.8) ---------------------------------------------------------
const POINTS_PER_SQRT_KG := 20.0
const GRADE_TROPHY := 1  ## landed event `grade`: 1 trophy, 0 landed
const GRADE_LANDED := 0
const TROPHY_MULT := 1.5
const KG_STRENGTH := 0.15  ## kg = drawn x (1 + 0.15 x strength)
const HOOKUP_OVERLAP_S := 10.0
const HOOKUP_MULT := [1.0, 1.0, 1.5, 2.0, 2.5]  ## by fights overlapping (index = count)
const TEAM_GRADES := [[1.25, "S"], [1.0, "A"], [0.8, "B"], [0.6, "C"]]
const XP_PER_KJ := 1.0
const XP_PER_FISH := 10
const XP_PER_TROPHY := 25
const XP_PER_RECORD := 50
const XP_PER_UNLOCK := 500
const CATCH_BOARD := 5  ## the last 5 catches

# --- Ride out ----------------------------------------------------------------------------
const TIP_EVERY_S := 45.0

# --- Network ------------------------------------------------------------------------------
const SNAPSHOT_MAX_BYTES := 2048
const INTENTS_PER_S := 5  ## host-side rate limit per peer

# --- Layout (3.2), art pixels at pixel_base [640, 360] -----------------------------------
const PIXEL_W := 640
const PIXEL_H := 360
const DECK_H := 24
const PLAY_H := 336
const SURFACE_H := 4
const BOAT_X0 := 8
const BOAT_X1 := 88
const ROD_TIP_X := 88
const FISH_X0 := 96
const FISH_SPAN := 324  ## mouth x = 96 + (d / d_max) x (324 - fish width): left of x 420
const HINT_X0 := 96
const HINT_SPAN := 300  ## hint x = 96 + (d / 80 m) x 300
const HINT_D_REF := 80.0
const HUD_X := 427
const HUD_W := 213
const PANIC_X := 503  ## the app's PANIC button owns art x >= 503 and y >= 316
const PANIC_Y := 316


static func species_index(id: String) -> int:
	return SPECIES.find(id)


static func spot_index(id: String) -> int:
	return SPOTS.find(id)


## Hookup multiplier for `count` overlapping fights (the fish's own included).
static func hookup_mult(count: int) -> float:
	return float(HOOKUP_MULT[clampi(count, 0, HOOKUP_MULT.size() - 1)])


## Team grade letter for points / expected points (no started fish: "D").
static func team_grade(fraction: float, any_fish: bool) -> String:
	if not any_fish:
		return "D"
	for g: Array in TEAM_GRADES:
		if fraction >= float(g[0]):
			return str(g[1])
	return "D"

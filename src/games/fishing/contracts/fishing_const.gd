class_name FishingConst
extends RefCounted
## Every number of Turbo Reel's rules in one place (contract v2). Rules, plans, tests and the
## view read these names instead of repeating literals. Times are game seconds, cadences rpm,
## distances metres, speeds m/s, percentages % of the rider's own FTP. "FTP-equivalent" is the
## effective power P_eff (Telemetry.p_eff_w, the session's scaling mode) against P_EFF_REF_W:
## 250 W of P_eff is 100 % in every mode (FAIR_FTP maps each rider's FTP onto 250 W).

# --- Rider actions (FishingRiderState.action; the snapshot's R_ACTION) ----------------------
const A_DRIVE := 0  ## prop engaged: P_eff drives the boat
const A_DRIFT := 1  ## prop free (P_eff under DRIFT_P_FRAC, or Autopilot stopping): slowing down
const A_MENU := 2  ## stopped: the light menu (cast at a hint, drive on, turn around)
const A_CAST := 3  ## the wobbler dives to the picked fish (cast_s); no bites yet
const A_WAIT := 4  ## lure at depth, waiting for the bite (workouts: trolling while driving)
const A_FIGHT := 5  ## the Fight phase (ERG): tension band, strain/slack, runs
const A_LAND := 6  ## the Landing phase (SIM 30 s): gaff sprint, then easy spin
const A_HOME := 7  ## the cool-down: heading home
## Display-only actions (the minimap and leaderboard icons): FishingSnapshotSchema.display_action
## returns these when the row's F_PAUSED or F_AFK flag is set; the rules never store them.
const A_PAUSED := 8
const A_AFK := 9
const ACTION_NAMES := [
	"drive", "drift", "menu", "cast", "wait", "fight", "land", "home", "paused", "afk"
]

# --- Menu items (R_MENU entries; 0..HINTS_PER_STOP - 1 cast at that hint) ------------------
const M_DRIVE_ON := 10
const M_TURN := 11

# --- Species (wire ids; index = position) -----------------------------------------------
const SPECIES := [
	"mackerel",
	"sea_bream",
	"snapper",
	"mahi",
	"tuna",
	"wahoo",
	"swordfish",
	"marlin",
	"grouper",
	"oarfish",
]
const SP_NONE := -1

# --- Trip kinds (FishingTripDef.kind) ----------------------------------------------------
const TRIP_ROAM := "roam"  ## Free Roam: the fixed map, fights built on the fly, competitive
const TRIP_BASE := "base"  ## workout: pre-rolled open-ended Reels and Fights
const TRIP_THRESHOLD := "threshold"  ## workout: one shared fixed schedule
const TRIP_E2E := "e2e"  ## the 2-minute end-to-end workout

# --- Boat physics (FishingBoat; 0.05 s steps) -----------------------------------------------
const P_EFF_REF_W := 250.0  ## 100 % FTP-equivalent
const BOAT_MASS_KG := 400.0
const THRUST_V0 := 1.0  ## thrust = P_eff / max(|v|, V0) N
const DRAG_QUAD := 1.6  ## N per (m/s)^2: 250 W holds 5 m/s, crossing 9 km in 30 min
const DRAG_LIN := 2.0  ## N per m/s
const DRIFT_DRAG_LIN := 80.0  ## with the prop free the hull brakes hard: ~5 s time constant
const DRIFT_P_FRAC := 0.2  ## under 20 % FTP-equivalent the prop disengages
const STOP_SPEED := 0.3  ## a drifting boat counts as stopped below this
const DRIVE_ON_P_FRAC := 0.8  ## pedaling >= 80 % for DRIVE_ON_S in the menu drives on
const DRIVE_ON_S := 2.0
const SPRINT_P_FRAC := 1.05  ## the sprint flag (wake icon): P_eff > 105 % FTP-equivalent
const PITCH_PER_THROTTLE := 2.5  ## degrees of bow lift per 100 % throttle
const PITCH_PER_ACCEL := 20.0  ## degrees per m/s^2 of forward acceleration
const PITCH_MAX_DEG := 14.0
const PITCH_TAU_S := 0.6
const WAKE_SPEED := 0.6  ## wake = 0.6 x |v| / WAKE_V_FULL + 0.4 x throttle (0..1)
const WAKE_V_FULL := 7.0

# --- Trainer load while driving (SIM, grade_source "game") ------------------------------------
const GRADE_BASE_PCT := 0.5  ## water drag: 0.5 % + 0.08 x v^2, at most 3 %
const GRADE_PER_V2 := 0.08
const GRADE_MAX_PCT := 3.0  ## inside the governor's warm-up range (-2 .. +3 %)
const GRADE_STEP_PCT := 0.1  ## a new grade goes out when it moved this much
const GRADE_EVERY_TICKS := 10  ## and at most twice a second

# --- Free Roam session ---------------------------------------------------------------------
const WARMUP_S := 300.0  ## the fixed drive-out phase: no ERG, no bites (BRIEF 4.6.8)
const ROAM_MIN_S := 5.0  ## a Roam phase's min_s (bites wait for it)
const OVERTIME_S := 300.0  ## a fight on at time-up may run 5 more minutes
const ROAM_MARGIN_S := 60.0  ## a Roam phase's max_s outlasts the session by this much
const HINTS_PER_STOP := 3
const HINT_DX_MIN := 8.0  ## a hint sits 8-40 m from the boat (either side)
const HINT_DX_MAX := 40.0
const HINT_REFRESH_M := 60.0  ## stopping this far from the last hints draws new ones
const FLOOR_GAP_LO := 3.0  ## near_floor fish hold 3-10 m above the floor
const FLOOR_GAP_HI := 10.0
const ABYSS_DEPTH_M := 400.0  ## near_floor fish where there is no floor: this deep
const CAST_BASE_S := 1.5  ## cast_s = 1.5 s + depth / 60 m/s, at most 8 s
const LURE_SINK_MPS := 60.0
const CAST_MAX_S := 8.0
const ROAM_BITE_MEAN_S := 25.0  ## hazard 1 / 25 s in the lure band, a quarter outside
const ROAM_BITE_MIN_S := 5.0  ## no bite in the first 5 s at depth
const ROAM_FORCED_BITE_S := 90.0  ## a bite is forced after 90 s at depth

# --- Plan (workouts and the fights) ---------------------------------------------------------
const RIDE_OUT_S := 300.0
const RIDE_OUT_PCT := 50.0
const RIDE_OUT_RAMP_TO := 65.0
const REEL_PCT_DEFAULT := 60
const REEL_PCT_MIN := 50
const REEL_PCT_MAX := 70
const REEL_MIN_S := 120.0  ## open-ended Reel min_s (= the earliest bite)
const REEL_NOMINAL_S := 240.0  ## open-ended Reel duration_s, for the timeline only
const FIGHT_MIN_FRAC := 0.8  ## Fight min_s = floor(0.8 x T_nom)
const FIGHT_MIN_S := 30.0  ## every Fight's min_s is at least this (BRIEF 4.5 switch spacing)
const T_NOM_W_FRAC := 0.8  ## T_nom = lo + 0.8 x w x (hi - lo)
const LANDING_S := 30.0
const GAFF_S := 15.0
const SLOT_GAP_S := 30.0  ## each fight slot costs T_nom + 30 s of the fight budget
const LAST_CALL_OVERRUN_S := 300.0  ## a workout fight must end <= 5 min after fishing ends
const JUMP_SPACING_S := 115.0  ## jumps = min(rolled, floor(T_nom / 115 s))
const SELF_CAP_PCT := 110.0  ## nothing above 110 %, ever
const LONG_PHASE_CAP_PCT := 105.0  ## BRIEF 4.6.1: phases longer than 300 s (open-ended: max_s)
const BASE_TOP_PCT := 100.0  ## base_60: nothing above 100 %

# --- Pull scheduler -------------------------------------------------------------------------
const PULL_CHANGE_MIN_S := 8.0
const PULL_CHANGE_MAX_S := 16.0
const RAMP_S := 3.0
const RAMP_STEPS := 6
const RAMP_STEP_S := 0.5  ## BRIEF 4.5: at most 2 writes a second
const RAMP_MAX_W_PER_S := 25.0  ## under the governor's 30 W/s slew
const RUN_MAX_ABOVE_105_S := 30.0
const FIGHT_MAX_ABOVE_105_S := 90.0
const PULL_RESUME_AFTER_STAGGER_S := 10.0

# --- Cadence and bands ----------------------------------------------------------------------
const CADENCE_TAU_S := 1.0  ## EMA time constant for band tests
const STALE_S := 3.0  ## stale cadence freezes the meters; stale telemetry makes the rider AFK
const LURE_HALF := 8.0  ## lure band: preferred + species offset +- 8
const BAND_WIDTH := 16.0
const BAND_WIDTH_RELAXED := 22.0
const BAND_LOW_HALF := 8.0  ## low edge = max(65, center - 8); high = low + width
const BAND_LOW_MIN := 65.0  ## above BRIEF 4.6.3's 45 rpm rescue trigger
const BAND_STAMINA_RPM := 10.0  ## center - 10 x (1 - S)
const BAND_SLIDE_RPM_S := 3.0

# --- Workout bites ---------------------------------------------------------------------------
const TROLL_CAST_S := 1.5  ## a Reel starts with the lure going out behind the moving boat
const TROLL_DEPTH_M := 12.0  ## a trolled lure runs this deep
const TROLL_DX_M := 30.0  ## and this far behind the boat
const HAZARD_BASE := 0.35
const HAZARD_STRENGTH := 0.65
const HAZARD_DIV_S := 90.0
const HAZARD_OUT_OF_BAND := 0.25
const TROLL_STRENGTH := 0.7  ## the strength a trolled lure fishes with
const R_MIN_S := 120.0
const FORCED_BITE_AFTER_S := 240.0  ## a bite is forced at R_min + 240 s
const SCHEDULED_BITE_LEAD_S := 4.0

# --- Menu (Free Roam) ------------------------------------------------------------------------
const SCAN_INTERVAL_S := 1.6  ## the pedal-scan highlight step (pedal_nav riders only)
const SCAN_PAUSE_S := 10.0  ## left/right pause the scan
const AUTO_CONFIRM_CYCLES := 2  ## pedal_nav: a menu auto-confirms after two full scan cycles
const AUTOPILOT_MENU_S := 1.0  ## Autopilot and bots pick after a second in the menu

# --- Fight ---------------------------------------------------------------------------------
const D_NEAR := 10.0  ## d moves toward 10 + (d_max - 10) x S
const D_OUT_MPS := 4.0
const D_IN_MPS := 2.0
const Z_BASE := 0.25  ## z moves toward 0.25 + 0.75 x S, or 1 on a run (depth = z x hook depth)
const Z_RATE := 0.5
const METER_FILL_S := 6.0  ## strain or slack fills at 1/6 per second
const METER_DRAIN_S := 12.0  ## the other drains at 1/12 per second
const TIRE_MAX_RATIO := 1.2  ## dS/dt = -min(1.2, P / applied target) / T_nom in band
const RECOVER_RATE := 0.25  ## +0.25 / T_nom out of band
const REPLACEMENT_DELAY_S := 5.0
const REPLACEMENT_KG := 0.75
const STAGGER_RESUME_S := 10.0  ## play resumes 10 s after rescue, AFK or pause ends
const SWIM_OUT_MPS := 1.0
const ABOARD_MPS := 2.0  ## in the Landing the fish comes aboard at this speed

# --- Landing -------------------------------------------------------------------------------
const GAFF_CP_FRAC := 0.4  ## fill = integral max(0, P - CP) dt / (0.4 x CP x 15 s)
const SPRINT_FTP_FRAC := 1.2  ## counted only while P >= 1.2 x FTP (BRIEF 3.5)
const HAPTIC_PCT := 3.0
const HAPTIC_S := 5.0
const HAPTIC_AT_MIN_S := 3.0
const HAPTIC_AT_MAX_S := 6.0
const HAPTIC_PLAN_MIN_S := 300.0  ## never in the first 300 s of the plan

# --- Points, grades, XP ---------------------------------------------------------------------
const POINTS_BASE := 15.0  ## points = round(15 + 12 x kg^0.55) x grade x hookup
const POINTS_PER_KG_EXP := 12.0
const POINTS_EXP := 0.55
const GRADE_TROPHY := 1  ## landed event `grade`: 1 trophy, 0 landed
const GRADE_LANDED := 0
const TROPHY_MULT := 1.5
const HOOKUP_OVERLAP_S := 10.0  ## workouts (co-op): overlapping fights score more
const HOOKUP_MULT := [1.0, 1.0, 1.5, 2.0, 2.5]  ## by fights overlapping (index = count)
const TEAM_GRADES := [[1.25, "S"], [1.0, "A"], [0.8, "B"], [0.6, "C"]]
const XP_PER_KJ := 1.0
const XP_PER_FISH := 10
const XP_PER_TROPHY := 25
const XP_PER_RECORD := 50
const XP_PER_UNLOCK := 500
const CATCH_BOARD := 5  ## the last 5 catches

# --- Warm-up tips ---------------------------------------------------------------------------
const TIP_EVERY_S := 45.0
const TIP_KEYS := 6

# --- Network ------------------------------------------------------------------------------
const SNAPSHOT_MAX_BYTES := 2048
const INTENTS_PER_S := 5  ## host-side rate limit per peer

# --- Screen (art pixels at pixel_base [640, 360]) --------------------------------------------
const PIXEL_W := 640
const PIXEL_H := 360
const PANIC_X := 503  ## the app's PANIC button owns art x >= 503 and y >= 316
const PANIC_Y := 316


static func species_index(id: String) -> int:
	return SPECIES.find(id)


## Hookup multiplier for `count` overlapping fights (the fish's own included).
static func hookup_mult(count: int) -> float:
	return float(HOOKUP_MULT[clampi(count, 0, HOOKUP_MULT.size() - 1)])


## round(15 + 12 x kg^0.55): a fish's points before grade and hookup. A 1 kg mackerel scores 27,
## a 13 kg mahi 64, a 60 kg tuna 128, a 200 kg grouper 237: many small fish near the dock and a
## few giants far out both pay.
static func base_points(kg: float) -> int:
	return roundi(POINTS_BASE + POINTS_PER_KG_EXP * pow(maxf(kg, 0.0), POINTS_EXP))


## Team grade letter for points / expected points (no started fish: "D").
static func team_grade(fraction: float, any_fish: bool) -> String:
	if not any_fish:
		return "D"
	for g: Array in TEAM_GRADES:
		if fraction >= float(g[0]):
			return str(g[1])
	return "D"

class_name FishingPlanBuilder
extends RefCounted
## Every rider's EffortPlan (contract v2). The PlanValidator appends the cool-down.
##
## Free Roam: the plan grows fight by fight. It starts as
##   Drive out  WARMUP SIM game, WARMUP_S (300 s) fixed, lap   "FISHING_PHASE_DRIVE_OUT"
##   Roam       FREE SIM game, open-ended (min_s 5, max_s = play time left + overtime + 60 s), lap
## and at each bite the rules replan the rest as fight_tail(): the Fight, its Landing and a new
## Roam, then end the current Roam (ctx.directives.replan, then end_phase, in the same tick).
## The fixed drive-out keeps every ERG phase out of the first 300 s (BRIEF 4.6.8). The driving
## load is the game's course grade (FishingBoat.grade_for). Switch spacing: a Fight's min_s is
## >= 30 s and every Roam follows a 30 s Landing, so ERG/SIM switches are >= 30 s apart.
##
## Workouts:
##   Ride out  WARMUP ERG 50 % ramp_to 65, 300 s, lap        "FISHING_PHASE_RIDE_OUT"
##   Troll     RECOVERY ERG reel_pct, lap: Base open-ended (min_s 120, max_s = the trip length,
##             duration_s nominal 240); Threshold/e2e fixed (the slot's reel_s)  "FISHING_PHASE_TROLL"
##   <Sp>      WORK ERG base pull, range_pct, open-ended (min_s floor(0.8 T_nom), species max_s),
##             duration_s = T_nom, lap, label = the species' name key
##   Landing   WORK SIM flat 30 s, no lap                     "FISHING_PHASE_LANDING"
## Base ends with a trailing fight-less Troll, so a rider whose slots ran out keeps going until
## finished("trip_over"); scheduled trips end at the last Landing.

const LABEL_DRIVE_OUT := "FISHING_PHASE_DRIVE_OUT"
const LABEL_ROAM := "FISHING_PHASE_ROAM"
const LABEL_RIDE_OUT := "FISHING_PHASE_RIDE_OUT"
const LABEL_TROLL := "FISHING_PHASE_TROLL"
const LABEL_LANDING := "FISHING_PHASE_LANDING"


## Free Roam's starting plan for a session of `play_s` seconds.
static func roam(play_s: float) -> EffortPlan:
	var plan := EffortPlan.new()
	plan.add(
		PlanPhase.sim(Wl.WARMUP, Wl.GRADE_GAME, FishingConst.WARMUP_S, LABEL_DRIVE_OUT).with_lap()
	)
	plan.add(roam_phase(roam_max_s(play_s, FishingConst.WARMUP_S)))
	return plan


## A Roam phase's max_s when it starts at game time `at_t` in a session of `play_s` seconds: the
## rest of play, the overtime and a margin (the game always finishes first).
static func roam_max_s(play_s: float, at_t: float) -> float:
	return maxf(
		play_s - at_t + FishingConst.OVERTIME_S + FishingConst.ROAM_MARGIN_S,
		FishingConst.ROAM_MIN_S + FishingConst.ROAM_MARGIN_S
	)


static func roam_phase(max_s: float) -> PlanPhase:
	return (
		PlanPhase
		. sim(Wl.FREE, Wl.GRADE_GAME, 0.0, LABEL_ROAM)
		. with_open(FishingConst.ROAM_MIN_S, max_s)
		. with_lap()
	)


## The rest of a Free Roam plan after a bite: the Fight, its Landing and a new Roam.
static func fight_tail(slot: FishingPlanSlot, roam_max: float) -> EffortPlan:
	var plan := EffortPlan.new()
	plan.add(fight_phase(slot))
	plan.add(landing_phase())
	plan.add(roam_phase(roam_max))
	return plan


static func fight_phase(slot: FishingPlanSlot) -> PlanPhase:
	return (
		PlanPhase
		. erg(Wl.WORK, slot.base_pct, slot.t_nom_s, fight_label(slot.species))
		. with_range(slot.range_lo, slot.range_hi)
		. with_open(slot.min_s, slot.max_s)
		. with_lap()
		. with_meta({"slot": slot.index, "species": slot.species})
	)


static func landing_phase() -> PlanPhase:
	return PlanPhase.sim(Wl.WORK, Wl.GRADE_FLAT, FishingConst.LANDING_S, LABEL_LANDING)


## A workout plan from the trip and the rider's pre-rolled slots.
static func build(trip: FishingTripDef, slots: Array[FishingPlanSlot], reel_pct: int) -> EffortPlan:
	var plan := EffortPlan.new()
	var ride := PlanPhase.erg(Wl.WARMUP, trip.ride_out_pct, trip.ride_out_s, LABEL_RIDE_OUT)
	if trip.ride_out_ramp_to > 0.0:
		ride.with_ramp(trip.ride_out_ramp_to)
	plan.add(ride.with_lap())
	var reel := float(trip.reel_target(reel_pct))
	var max_reel := trip_length_s(trip)
	for s in slots:
		plan.add(_troll(reel, s.reel_s, max_reel))
		plan.add(fight_phase(s))
		plan.add(landing_phase())
	if not trip.is_scheduled():
		plan.add(_troll(reel, 0.0, max_reel))
	return plan


## A workout's nominal length in seconds (an open-ended Troll's max_s).
static func trip_length_s(trip: FishingTripDef) -> float:
	return maxf(trip.total_min * 60.0, trip.ride_out_s + trip.fishing_s + FishingConst.REEL_MIN_S)


## The Fight phase label: the species' name key (FISHING_SPECIES_<ID>).
static func fight_label(species: String) -> String:
	return "FISHING_SPECIES_%s" % species.to_upper()


static func _troll(pct: float, fixed_s: float, max_s: float) -> PlanPhase:
	if fixed_s > 0.0:
		return PlanPhase.erg(Wl.RECOVERY, pct, fixed_s, LABEL_TROLL).with_lap()
	return (
		PlanPhase
		. erg(Wl.RECOVERY, pct, FishingConst.REEL_NOMINAL_S, LABEL_TROLL)
		. with_open(FishingConst.REEL_MIN_S, max_s)
		. with_lap()
	)

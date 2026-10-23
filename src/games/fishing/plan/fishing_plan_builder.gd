class_name FishingPlanBuilder
extends RefCounted
## One EffortPlan per rider from the trip and the rider's pre-rolled slots (brief 2.3). The
## PlanValidator appends the cool-down. Fishing never calls replan: open-ended Reels and Fights
## absorb the variation. G0 version; fish-plan owns this file.
##
##   Ride out  WARMUP ERG 50 % ramp_to 65, 300 s, lap        "FISHING_PHASE_RIDE_OUT"
##   Reel n    RECOVERY ERG reel_pct, lap: Free/Base open-ended (min_s 120, max_s = the trip
##             length, duration_s nominal 240); Threshold/e2e fixed (the slot's reel_s)
##   <Sp> n    WORK ERG base pull, range_pct, open-ended (min_s floor(0.8 T_nom), species max_s),
##             duration_s = T_nom, lap
##   Landing   WORK SIM flat 30 s, no lap                     "FISHING_PHASE_LANDING"
## Free and Base end with a trailing fight-less Reel, so a rider whose slots ran out keeps
## reeling until finished("trip_over"); scheduled trips end at the last Landing.

const LABEL_RIDE_OUT := "FISHING_PHASE_RIDE_OUT"
const LABEL_LANDING := "FISHING_PHASE_LANDING"
## Per-number label keys exist in strings.csv up to these counts; beyond them the plain text
## ("Reel 41") passes through ctx.strings.t unchanged.
const REEL_KEYS := 40
const SPECIES_KEYS := {"mackerel": 30, "mahi": 20, "tuna": 12, "marlin": 4}
const PLAIN := {
	"mackerel": "Mackerel", "mahi": "Mahi-mahi", "tuna": "Yellowfin tuna", "marlin": "Blue marlin"
}


static func build(trip: FishingTripDef, slots: Array[FishingPlanSlot], reel_pct: int) -> EffortPlan:
	var plan := EffortPlan.new()
	var ride := PlanPhase.erg(Wl.WARMUP, trip.ride_out_pct, trip.ride_out_s, LABEL_RIDE_OUT)
	if trip.ride_out_ramp_to > 0.0:
		ride.with_ramp(trip.ride_out_ramp_to)
	plan.add(ride.with_lap())
	var reel := float(trip.reel_target(reel_pct))
	var max_reel := trip_length_s(trip)
	var counts := {}
	for s in slots:
		plan.add(_reel(reel, s.reel_s, max_reel, s.index + 1))
		counts[s.species] = int(counts.get(s.species, 0)) + 1
		var fight := (
			PlanPhase
			. erg(Wl.WORK, s.base_pct, s.t_nom_s, fight_label(s.species, counts[s.species]))
			. with_range(s.range_lo, s.range_hi)
			. with_open(s.min_s, s.max_s)
			. with_lap()
			. with_meta({"slot": s.index, "species": s.species})
		)
		plan.add(fight)
		plan.add(PlanPhase.sim(Wl.WORK, Wl.GRADE_FLAT, FishingConst.LANDING_S, LABEL_LANDING))
	if not trip.is_scheduled():
		plan.add(_reel(reel, 0.0, max_reel, slots.size() + 1))
	return plan


## The trip's nominal length in seconds (an open-ended Reel's max_s).
static func trip_length_s(trip: FishingTripDef) -> float:
	return maxf(trip.total_min * 60.0, trip.ride_out_s + trip.fishing_s + FishingConst.REEL_MIN_S)


static func reel_label(n: int) -> String:
	return "FISHING_PHASE_REEL_%d" % n if n <= REEL_KEYS else "Reel %d" % n


static func fight_label(species: String, n: int) -> String:
	if n <= int(SPECIES_KEYS.get(species, 0)):
		return "FISHING_PHASE_%s_%d" % [species.to_upper(), n]
	return "%s %d" % [PLAIN.get(species, species), n]


static func _reel(pct: float, fixed_s: float, max_s: float, n: int) -> PlanPhase:
	if fixed_s > 0.0:
		return PlanPhase.erg(Wl.RECOVERY, pct, fixed_s, reel_label(n)).with_lap()
	return (
		PlanPhase
		. erg(Wl.RECOVERY, pct, FishingConst.REEL_NOMINAL_S, reel_label(n))
		. with_open(FishingConst.REEL_MIN_S, max_s)
		. with_lap()
	)

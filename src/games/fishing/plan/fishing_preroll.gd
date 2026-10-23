class_name FishingPreroll
extends RefCounted
## Draws each rider's fight slots (brief 2.3). Free and Base: per rider from ctx.seed and the slot
## index, species by the trip's weights limited to what fits the remaining fight budget, w capped
## so T_nom + 30 s fits, stopping when no species fits. Threshold and e2e: the shared schedule,
## the same for every rider. G0 version: scheduled trips complete; Free and Base return [] until
## fish-plan's G1 pre-roll lands. fish-plan owns this file.


## The rider's slots, in order. `species` maps id -> FishingSpeciesDef.
static func roll(
	trip: FishingTripDef, species: Dictionary, seed: int, _slot_index: int
) -> Array[FishingPlanSlot]:
	if trip.is_scheduled():
		return scheduled(trip, species, seed)
	return [] as Array[FishingPlanSlot]


## The shared schedule of a Threshold or e2e trip (the same stream for every rider).
static func scheduled(
	trip: FishingTripDef, species: Dictionary, seed: int
) -> Array[FishingPlanSlot]:
	var out: Array[FishingPlanSlot] = []
	var sc := trip.schedule
	var def: FishingSpeciesDef = species[str(sc["species"])]
	var rng := FishingRandom.derive(seed, 0, FishingRandom.STREAM_PREROLL)
	for i in int(sc["fights"]):
		var s := FishingPlanSlot.new()
		s.index = i
		s.species = def.id
		s.sp = FishingConst.species_index(def.id)
		s.w = 0.5
		s.base_pct = float(sc["base_pct"])
		s.change_pct = float(sc.get("change_pct", def.change_pct))
		s.t_nom_s = float(sc["t_nom_s"])
		s.min_s = floorf(FishingConst.FIGHT_MIN_FRAC * s.t_nom_s)
		s.max_s = float(sc["max_s"])
		s.run_kind = def.run_kind if int(sc.get("runs", 0)) > 0 else FishingSpeciesDef.RUN_NONE
		var peak_top := 0.0
		for k in int(sc.get("runs", 0)):
			var dur := rng.range_f(def.run_s_lo, def.run_s_hi)
			var peak := def.run_peak(s.base_pct, rng.unit())
			s.runs.append(dur)
			s.runs.append(peak)
			peak_top = maxf(peak_top, peak)
		s.run_band_shift = def.run_band_shift
		s.run_min_gap_s = def.run_min_gap_s
		var a := s.change_pct / 100.0
		s.range_lo = s.base_pct * (1.0 - a)
		s.range_hi = maxf(s.base_pct * (1.0 + a), peak_top)
		s.band_offset = float(sc.get("band_offset", def.band_offset))
		s.kg = rng.range_f(def.kg_lo, def.kg_hi)
		s.scheduled = true
		s.reel_s = float(sc["first_reel_s"]) if i == 0 else float(sc.get("reel_s", 0))
		out.append(s)
	return out

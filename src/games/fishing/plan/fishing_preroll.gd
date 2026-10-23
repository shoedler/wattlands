class_name FishingPreroll
extends RefCounted
## Draws each rider's fight slots (brief 2.3). fish-plan owns this file.
##
## Free and Base: per rider, one FishingRandom stream from (ctx.seed, slot index, STREAM_PREROLL),
## so riders differ and every peer rolls the same slots. The fight budget is fight_cap_frac x
## fishing_s (Free 40 %, Base 25 %). For each fight slot in turn:
##   1. the trip's marlin slot (free_90, free_120: the 2nd, 1-based) draws a coin and is a marlin
##      with probability marlin_p, when the marlin's window low end + 30 s fits the budget left;
##   2. otherwise the species is drawn by the trip's weights among those whose window low end
##      + 30 s fits the budget left; when none fits, the slots stop;
##   3. w in [0, 1], capped so T_nom + 30 s fits the budget left; base pull = lo + w (hi - lo),
##      T_nom = lo + 0.8 w (hi - lo) (T_nom window), min_s = floor(0.8 T_nom), max_s per species;
##   4. runs: count in the species' range (jumps: min(rolled, floor(T_nom / 115 s))), each with
##      its length (snapped to 0.1 s) and peak (mahi 105-110, tuna base x 1.08, marlin 104);
##   5. range_pct = [base (1 - a), max(base (1 + a), the highest run peak)].
## Base (top_pct 100) tops the base pull, every run peak and the range at 100 %. A phase longer
## than 300 s (max_s) keeps every peak at <= 105 % (BRIEF 4.6.1), and nothing passes 110 %.
## The budget is the only plan-time limit: last call (2.4) is the rules' run-time check. The first
## slot always passes it, since its window low end + 30 s fits the budget (tests prove it).
## Threshold and e2e: the shared schedule, the same for every rider (stream (seed, 0, PREROLL)).

## Run lengths are snapped to this (tick-aligned expiries).
const RUN_SNAP_S := 0.1
## No trip rolls more slots than this (a guard; the budget stops far sooner).
const MAX_SLOTS := 64


## The rider's slots, in order. `species` maps id -> FishingSpeciesDef.
static func roll(
	trip: FishingTripDef, species: Dictionary, seed: int, slot_index: int
) -> Array[FishingPlanSlot]:
	if trip.is_scheduled():
		return scheduled(trip, species, seed)
	return free_slots(trip, species, seed, slot_index)


## Free and Base slots of the rider in `slot_index` (brief 2.3 pre-roll).
static func free_slots(
	trip: FishingTripDef, species: Dictionary, seed: int, slot_index: int
) -> Array[FishingPlanSlot]:
	var out: Array[FishingPlanSlot] = []
	var rng := FishingRandom.derive(seed, slot_index, FishingRandom.STREAM_PREROLL)
	var left := trip.fight_cap_frac * trip.fishing_s
	var weights: Array[float] = []
	weights.resize(FishingConst.SPECIES.size())
	for i in MAX_SLOTS:
		var def: FishingSpeciesDef = null
		if trip.marlin_slot == i + 1 and trip.marlin_p > 0.0:
			var coin := rng.unit()
			var marlin: FishingSpeciesDef = species.get("marlin")
			if marlin != null and coin < trip.marlin_p and fits(marlin, left):
				def = marlin
		if def == null:
			for k in FishingConst.SPECIES.size():
				var id: String = FishingConst.SPECIES[k]
				var cand: FishingSpeciesDef = species.get(id)
				var wgt := float(trip.species_weights.get(id, 0.0))
				weights[k] = wgt if cand != null and wgt > 0.0 and fits(cand, left) else 0.0
			var pick := rng.pick_weighted(weights)
			if pick < 0:
				break
			def = species[FishingConst.SPECIES[pick]]
		var s := _slot(def, i, rng, left, trip.top_pct)
		left -= s.budget_s()
		out.append(s)
	return out


## True when the species' shortest fight (window low end) + 30 s fits `left` seconds of budget.
static func fits(def: FishingSpeciesDef, left: float) -> bool:
	return def.t_nom_lo + FishingConst.SLOT_GAP_S <= left + 1.0e-6


## The largest w whose T_nom + 30 s fits `left` (1 when the whole window fits).
static func w_cap(def: FishingSpeciesDef, left: float) -> float:
	var span := FishingConst.T_NOM_W_FRAC * (def.t_nom_hi - def.t_nom_lo)
	if span <= 0.0:
		return 1.0
	return clampf((left - FishingConst.SLOT_GAP_S - def.t_nom_lo) / span, 0.0, 1.0)


static func _slot(
	def: FishingSpeciesDef, index: int, rng: FishingRandom, left: float, top_pct: float
) -> FishingPlanSlot:
	var s := FishingPlanSlot.new()
	s.index = index
	s.species = def.id
	s.sp = FishingConst.species_index(def.id)
	s.w = minf(rng.unit(), w_cap(def, left))
	var top := _top(def, top_pct)
	s.base_pct = minf(lerpf(def.pull_lo, def.pull_hi, s.w), top)
	s.change_pct = def.change_pct
	s.t_nom_s = def.t_nom_lo + FishingConst.T_NOM_W_FRAC * s.w * (def.t_nom_hi - def.t_nom_lo)
	s.min_s = floorf(FishingConst.FIGHT_MIN_FRAC * s.t_nom_s)
	s.max_s = def.max_s
	s.kg = rng.range_f(def.kg_lo, def.kg_hi)
	_roll_runs(s, def, rng, top)
	var a := s.change_pct / 100.0
	s.range_lo = s.base_pct * (1.0 - a)
	s.range_hi = minf(maxf(s.base_pct * (1.0 + a), _peak_top(s)), top)
	s.band_offset = def.band_offset
	return s


## Every peak's ceiling for this species and trip: 110 %, 105 % in a phase longer than 300 s,
## and the trip's top_pct (Base 100).
static func _top(def: FishingSpeciesDef, top_pct: float) -> float:
	var top := FishingConst.SELF_CAP_PCT
	if def.max_s > PlanValidator.LONG_PHASE_S:
		top = FishingConst.LONG_PHASE_CAP_PCT
	if top_pct > 0.0:
		top = minf(top, top_pct)
	return top


static func _roll_runs(
	s: FishingPlanSlot, def: FishingSpeciesDef, rng: FishingRandom, top: float
) -> void:
	s.run_kind = def.run_kind
	s.run_band_shift = def.run_band_shift
	s.run_min_gap_s = def.run_min_gap_s
	if def.run_kind == FishingSpeciesDef.RUN_NONE:
		return
	var n := rng.range_i(def.runs_lo, def.runs_hi)
	if def.run_kind == FishingSpeciesDef.RUN_JUMP:
		n = mini(n, floori(s.t_nom_s / FishingConst.JUMP_SPACING_S))
	for k in n:
		s.runs.append(snappedf(rng.range_f(def.run_s_lo, def.run_s_hi), RUN_SNAP_S))
		s.runs.append(minf(def.run_peak(s.base_pct, rng.unit()), top))
		if def.run_kind == FishingSpeciesDef.RUN_JUMP:
			s.leaps.append(rng.range_i(def.leaps_lo, def.leaps_hi))
	if n == 0:
		s.run_kind = FishingSpeciesDef.RUN_NONE


static func _peak_top(s: FishingPlanSlot) -> float:
	var top := 0.0
	for k in s.run_count():
		top = maxf(top, s.run_peak_pct(k))
	return top


## The shared schedule of a Threshold or e2e trip (the same stream for every rider).
static func scheduled(
	trip: FishingTripDef, species: Dictionary, seed: int
) -> Array[FishingPlanSlot]:
	var out: Array[FishingPlanSlot] = []
	var sc := trip.schedule
	var def: FishingSpeciesDef = species[str(sc["species"])]
	var rng := FishingRandom.derive(seed, 0, FishingRandom.STREAM_PREROLL)
	var top := _top(def, trip.top_pct)
	for i in int(sc["fights"]):
		var s := FishingPlanSlot.new()
		s.index = i
		s.species = def.id
		s.sp = FishingConst.species_index(def.id)
		s.w = 0.5
		s.base_pct = minf(float(sc["base_pct"]), top)
		s.change_pct = float(sc.get("change_pct", def.change_pct))
		s.t_nom_s = float(sc["t_nom_s"])
		s.min_s = floorf(FishingConst.FIGHT_MIN_FRAC * s.t_nom_s)
		s.max_s = float(sc["max_s"])
		s.run_kind = def.run_kind if int(sc.get("runs", 0)) > 0 else FishingSpeciesDef.RUN_NONE
		s.run_band_shift = def.run_band_shift
		s.run_min_gap_s = def.run_min_gap_s
		var peak_top := 0.0
		for k in int(sc.get("runs", 0)):
			var dur := snappedf(rng.range_f(def.run_s_lo, def.run_s_hi), RUN_SNAP_S)
			var peak := minf(def.run_peak(s.base_pct, rng.unit()), top)
			s.runs.append(dur)
			s.runs.append(peak)
			if def.run_kind == FishingSpeciesDef.RUN_JUMP:
				s.leaps.append(rng.range_i(def.leaps_lo, def.leaps_hi))
			peak_top = maxf(peak_top, peak)
		var a := s.change_pct / 100.0
		s.range_lo = s.base_pct * (1.0 - a)
		s.range_hi = minf(maxf(s.base_pct * (1.0 + a), peak_top), top)
		s.band_offset = float(sc.get("band_offset", def.band_offset))
		s.kg = rng.range_f(def.kg_lo, def.kg_hi)
		s.scheduled = true
		s.reel_s = float(sc["first_reel_s"]) if i == 0 else float(sc.get("reel_s", 0))
		out.append(s)
	return out

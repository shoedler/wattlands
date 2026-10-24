class_name FishingTripDef
extends FishingRecord
## One content from content/fishing/trips/<content id>.json (contract v2).
##
## Free Roam (kind "roam"): {"id": "roam_30", "kind": "roam", "label": "FISHING_CONTENT_ROAM_30",
##   "minutes": 30}: play time in minutes from the start (the first 5 min are the drive-out
##   warm-up); the fixed map is content/fishing/map.json.
## Workouts, on the endless map:
##   Base (pre-rolled per rider):
##   {"id": "base_60", "kind": "base", "label": "FISHING_CONTENT_BASE_60", "total_min": 60,
##    "ride_out": {"duration_s": 300, "target_pct": 50, "ramp_to_pct": 65}, "fishing_s": 3120,
##    "species_weights": {"mackerel": 60, "mahi": 40}, "fight_cap_frac": 0.25, "top_pct": 100,
##    "k_rmin": 3}
##   top_pct 100 caps every target and range at 100 % (0 = no extra cap).
##   Threshold and e2e (one shared schedule):
##   {"id": "e2e_2min", "kind": "e2e", ..., "ride_out": {"duration_s": 15, "target_pct": 50},
##    "reel_pct": 55, "schedule": {"first_reel_s": 20, "reel_s": 0, "fights": 1,
##    "species": "mackerel", "base_pct": 62, "change_pct": 4, "band_offset": 3, "t_nom_s": 45,
##    "max_s": 70, "runs": 0}}
##   Reels are fixed: first_reel_s, then reel_s between fights. band_offset (optional) overrides
##   the species' offset; runs n draws its dur_s and peak like the species table.
##   reel_pct (optional) fixes the Reel target and ignores the rider's reel_pct option.

var id: String = ""
var kind: String = ""
var label: String = ""
## Free Roam: play minutes.
var minutes: float = 0.0
var total_min: float = 0.0
var ride_out_s: float = 0.0
var ride_out_pct: float = 0.0
## PlanPhase.NONE (-1) = no ramp.
var ride_out_ramp_to: float = -1.0
var fishing_s: float = 0.0
## species id -> weight (Free and Base).
var species_weights: Dictionary = {}
var fight_cap_frac: float = 0.4
var top_pct: float = 0.0
var k_rmin: float = 1.5
## Fixed Reel target (e2e 55); -1 = the rider's reel_pct option.
var reel_pct: int = -1
## Scheduled trips only (see above); {} for Free and Base.
var schedule: Dictionary = {}


static func from_dict(d: Dictionary) -> FishingTripDef:
	var t := FishingTripDef.new()
	t.id = str(d.get("id", ""))
	t.kind = str(d.get("kind", ""))
	t.label = str(d.get("label", "FISHING_CONTENT_%s" % t.id.to_upper()))
	t.minutes = float(d.get("minutes", 0))
	t.total_min = float(d.get("total_min", 0))
	var ro: Dictionary = d.get("ride_out", {})
	t.ride_out_s = float(ro.get("duration_s", FishingConst.RIDE_OUT_S))
	t.ride_out_pct = float(ro.get("target_pct", FishingConst.RIDE_OUT_PCT))
	t.ride_out_ramp_to = float(ro.get("ramp_to_pct", -1))
	t.fishing_s = float(d.get("fishing_s", 0))
	t.species_weights = (d.get("species_weights", {}) as Dictionary).duplicate()
	t.fight_cap_frac = float(d.get("fight_cap_frac", 0.4))
	t.top_pct = float(d.get("top_pct", 0))
	t.k_rmin = float(d.get("k_rmin", 1.5))
	t.reel_pct = int(d.get("reel_pct", -1))
	t.schedule = (d.get("schedule", {}) as Dictionary).duplicate(true)
	return t


func is_roam() -> bool:
	return kind == FishingConst.TRIP_ROAM


func is_scheduled() -> bool:
	return kind == FishingConst.TRIP_THRESHOLD or kind == FishingConst.TRIP_E2E


## The rider's Reel target: the trip's fixed value or the reel_pct option.
func reel_target(option_pct: int) -> int:
	return reel_pct if reel_pct > 0 else option_pct


## Every problem with a trip file ([] when valid). `species_ids` are the ids species.json defines.
static func errors(d: Variant, species_ids: Array) -> Array[String]:
	var out: Array[String] = []
	if not d is Dictionary:
		out.append("trip is not an object")
		return out
	var e: Dictionary = d
	var trip_kind := str(e.get("kind", ""))
	var kinds := [
		FishingConst.TRIP_ROAM,
		FishingConst.TRIP_BASE,
		FishingConst.TRIP_THRESHOLD,
		FishingConst.TRIP_E2E
	]
	if not trip_kind in kinds:
		out.append("kind must be one of %s" % [kinds])
		return out
	if str(e.get("id", "")) == "":
		out.append("id missing")
	if trip_kind == FishingConst.TRIP_ROAM:
		var m := float(e.get("minutes", 0))
		if m < 10.0 or m > 120.0:
			out.append("minutes must be 10..120")
		return out
	var ro: Variant = e.get("ride_out", {})
	if not ro is Dictionary or float((ro as Dictionary).get("duration_s", 0)) <= 0.0:
		out.append("ride_out.duration_s must be positive")
	elif float(ro.get("target_pct", 50)) > 65.0 or float(ro.get("ramp_to_pct", -1)) > 65.0:
		out.append("ride_out targets must stay <= 65 % (BRIEF 4.6.8)")
	if e.has("reel_pct"):
		var rp := int(e["reel_pct"])
		if rp < FishingConst.REEL_PCT_MIN or rp > FishingConst.REEL_PCT_MAX:
			out.append("reel_pct must be 50..70")
	if trip_kind == FishingConst.TRIP_BASE:
		if float(e.get("fishing_s", 0)) <= 0.0:
			out.append("fishing_s must be positive")
		var w: Variant = e.get("species_weights", {})
		if not w is Dictionary or (w as Dictionary).is_empty():
			out.append("species_weights must be a non-empty object")
		else:
			for k: Variant in w:
				if not species_ids.has(str(k)):
					out.append("species_weights: unknown species %s" % k)
				elif float(w[k]) < 0.0:
					out.append("species_weights: negative weight for %s" % k)
		var cap := float(e.get("fight_cap_frac", 0.4))
		if cap <= 0.0 or cap > 0.4:
			out.append("fight_cap_frac must be in (0, 0.4]")
		if float(e.get("k_rmin", 1.5)) < 1.0:
			out.append("k_rmin must be >= 1")
	else:
		var s: Variant = e.get("schedule", null)
		if not s is Dictionary:
			out.append("a %s trip needs a schedule" % trip_kind)
			return out
		var sc: Dictionary = s
		if not species_ids.has(str(sc.get("species", ""))):
			out.append("schedule.species unknown")
		for key: String in ["first_reel_s", "base_pct", "t_nom_s", "max_s"]:
			if float(sc.get(key, 0)) <= 0.0:
				out.append("schedule.%s must be positive" % key)
		if int(sc.get("fights", 0)) < 1:
			out.append("schedule.fights must be >= 1")
		if int(sc.get("fights", 0)) > 1 and float(sc.get("reel_s", 0)) <= 0.0:
			out.append("schedule.reel_s must be positive with more than one fight")
		if float(sc.get("max_s", 0)) < float(sc.get("t_nom_s", 0)):
			out.append("schedule.max_s must be >= t_nom_s")
		if float(sc.get("base_pct", 0)) > FishingConst.SELF_CAP_PCT:
			out.append("schedule.base_pct above 110 %")
	return out

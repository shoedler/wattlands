class_name FishingContent
extends RefCounted
## Loads and validates every content file a trip needs (brief 2.9; G0 contract), always through
## ctx.load_content_json so run_game_sim --override reaches it:
##   species.json            FishingSpeciesDef entries
##   trips/<content id>.json FishingTripDef
##   areas/<trip area>.json  {"id", "label", "distance_m": [40, 80], "hints_per_cast": 3,
##                            "spots": [{"type": "bird_pile", "label": key,
##                                       "affinity": {"mackerel": 0.4, "mahi": 1.0, ...}}, ...]}
##   cosmetics.json          {"unlock_every_xp": 500, "items": [{"id", "kind", "value", "label"}]}
##                           kind: line | canopy | trim | pennant, in unlock order; value: a
##                           "#rrggbb" palette colour or a pattern id the view draws in code
## A bad file is rejected with one push_error naming every problem (ok false), so the session
## never starts on bad content (build_effort_plans returns {}).

const COSMETIC_KINDS := ["line", "canopy", "trim", "pennant"]

var ok: bool = false
var errors: Array[String] = []
## species id -> FishingSpeciesDef
var species: Dictionary = {}
var trip: FishingTripDef = null
var area: Dictionary = {}
var cosmetics: Dictionary = {}


static func load_for(ctx: GameContext, quiet: bool = false) -> FishingContent:
	var c := FishingContent.new()
	var sp: Variant = ctx.load_content_json("species.json")
	var tr: Variant = ctx.load_content_json("trips/%s.json" % ctx.content_id)
	var ar: Variant = null
	if tr is Dictionary:
		ar = ctx.load_content_json("areas/%s.json" % str(tr.get("area", "coral_bank")))
	var co: Variant = ctx.load_content_json("cosmetics.json")
	c.parse(sp, tr, ar, co)
	if not c.ok and not quiet:
		push_error("fishing: content %s: %s" % [ctx.content_id, "; ".join(c.errors)])
	return c


## Validates and fills from parsed JSON values (null for a missing file). Pure.
func parse(sp: Variant, tr: Variant, ar: Variant, co: Variant) -> FishingContent:
	errors = []
	species = {}
	if not sp is Dictionary or not (sp as Dictionary).get("species") is Array:
		errors.append('species.json: needs {"species": [...]}')
	else:
		for e: Variant in sp["species"]:
			var errs := FishingSpeciesDef.errors(e)
			errors.append_array(errs)
			if errs.is_empty():
				var def := FishingSpeciesDef.from_dict(e)
				if species.has(def.id):
					errors.append("species %s: listed twice" % def.id)
				species[def.id] = def
	if tr == null:
		errors.append("trip file missing")
	else:
		var terrs := FishingTripDef.errors(tr, species.keys())
		for t in terrs:
			errors.append("trip: %s" % t)
		if terrs.is_empty():
			trip = FishingTripDef.from_dict(tr)
	errors.append_array(area_errors(ar, species.keys()))
	area = ar if ar is Dictionary else {}
	errors.append_array(cosmetics_errors(co))
	cosmetics = co if co is Dictionary else {}
	ok = errors.is_empty()
	return self


## Affinity of spot type `spot_type` (FishingConst.SPOTS index) for species index `sp`.
func affinity(spot_type: int, sp: int) -> float:
	if sp < 0 or sp >= FishingConst.SPECIES.size():
		return 0.0
	for s: Dictionary in area.get("spots", []):
		if FishingConst.spot_index(str(s.get("type", ""))) == spot_type:
			return float((s.get("affinity", {}) as Dictionary).get(FishingConst.SPECIES[sp], 0.0))
	return 0.0


## The area's spot types, as FishingConst.SPOTS indexes, in file order.
func spot_types() -> Array[int]:
	var out: Array[int] = []
	for s: Dictionary in area.get("spots", []):
		out.append(FishingConst.spot_index(str(s.get("type", ""))))
	return out


## cosmetics.json items of one kind, in unlock order.
func cosmetics_of(kind: String) -> Array:
	return (cosmetics.get("items", []) as Array).filter(
		func(it: Dictionary) -> bool: return str(it.get("kind", "")) == kind
	)


static func area_errors(ar: Variant, species_ids: Array) -> Array[String]:
	var out: Array[String] = []
	if not ar is Dictionary:
		out.append("area file missing or not an object")
		return out
	var spots: Variant = (ar as Dictionary).get("spots")
	if not spots is Array or (spots as Array).size() < FishingConst.HINTS_PER_CAST:
		out.append("area: needs at least %d spots" % FishingConst.HINTS_PER_CAST)
		return out
	for s: Variant in spots:
		if not s is Dictionary or FishingConst.spot_index(str(s.get("type", ""))) < 0:
			out.append("area: unknown spot type %s" % [s.get("type") if s is Dictionary else s])
			continue
		var aff: Variant = s.get("affinity")
		if not aff is Dictionary:
			out.append("area: spot %s needs an affinity object" % s["type"])
			continue
		for id: Variant in species_ids:
			var v: Variant = aff.get(id)
			if not (v is float or v is int) or float(v) < 0.0 or float(v) > 1.0:
				out.append("area: spot %s affinity for %s must be 0..1" % [s["type"], id])
	var dr: Variant = (ar as Dictionary).get("distance_m", [40, 80])
	if (
		not dr is Array
		or (dr as Array).size() != 2
		or float(dr[0]) <= 0.0
		or float(dr[0]) > float(dr[1])
	):
		out.append("area: distance_m must be [lo, hi]")
	return out


static func cosmetics_errors(co: Variant) -> Array[String]:
	var out: Array[String] = []
	if not co is Dictionary or not (co as Dictionary).get("items") is Array:
		out.append('cosmetics.json: needs {"items": [...]}')
		return out
	if int((co as Dictionary).get("unlock_every_xp", 0)) <= 0:
		out.append("cosmetics.json: unlock_every_xp must be positive")
	var ids := {}
	for it: Variant in co["items"]:
		if not it is Dictionary:
			out.append("cosmetics.json: an item is not an object")
			continue
		var id := str(it.get("id", ""))
		if id == "" or ids.has(id):
			out.append("cosmetics.json: missing or repeated id %s" % id)
		ids[id] = true
		if not COSMETIC_KINDS.has(str(it.get("kind", ""))):
			out.append("cosmetics.json: %s has an unknown kind" % id)
		if str(it.get("value", "")) == "":
			out.append("cosmetics.json: %s needs a value" % id)
	return out

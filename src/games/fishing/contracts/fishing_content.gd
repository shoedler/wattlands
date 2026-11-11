class_name FishingContent
extends RefCounted
## Loads and validates every content file a session needs (contract v2), always through
## ctx.load_content_json so run_game_sim --override reaches it:
##   species.json            FishingSpeciesDef entries (every FishingConst.SPECIES id once)
##   trips/<content id>.json FishingTripDef
##   map.json                the Free Roam map (FishingWorld.from_map; roam contents only), or the
##                           file the trip's "map" field names (map_big_game.json)
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
## The parsed map file (roam contents; {} for workouts).
var map: Dictionary = {}
var cosmetics: Dictionary = {}


static func load_for(ctx: GameContext, quiet: bool = false) -> FishingContent:
	var c := FishingContent.new()
	var sp: Variant = ctx.load_content_json("species.json")
	var tr: Variant = ctx.load_content_json("trips/%s.json" % ctx.content_id)
	var mp: Variant = null
	if tr is Dictionary and str(tr.get("kind", "")) == FishingConst.TRIP_ROAM:
		mp = ctx.load_content_json(FishingTripDef.map_file_of(tr))
	var co: Variant = ctx.load_content_json("cosmetics.json")
	c.parse(sp, tr, mp, co)
	if not c.ok and not quiet:
		push_error("fishing: content %s: %s" % [ctx.content_id, "; ".join(c.errors)])
	return c


## Validates and fills from parsed JSON values (null for a missing file; `mp` is only read for
## a roam trip: the file its "map" field names, map.json without one). Pure.
func parse(sp: Variant, tr: Variant, mp: Variant, co: Variant) -> FishingContent:
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
		for id: String in FishingConst.SPECIES:
			if not species.has(id):
				errors.append("species.json: %s missing" % id)
	if tr == null:
		errors.append("trip file missing")
	else:
		var terrs := FishingTripDef.errors(tr, species.keys())
		for t in terrs:
			errors.append("trip: %s" % t)
		if terrs.is_empty():
			trip = FishingTripDef.from_dict(tr)
	map = {}
	if trip != null and trip.is_roam():
		if mp == null:
			errors.append("trip: map file %s is missing" % trip.map)
		else:
			for e in FishingWorld.errors(mp):
				errors.append(e.replace("map.json:", trip.map + ":"))
		map = mp if mp is Dictionary else {}
	errors.append_array(cosmetics_errors(co))
	cosmetics = co if co is Dictionary else {}
	ok = errors.is_empty()
	return self


## cosmetics.json items of one kind, in unlock order.
func cosmetics_of(kind: String) -> Array:
	return (cosmetics.get("items", []) as Array).filter(
		func(it: Dictionary) -> bool: return str(it.get("kind", "")) == kind
	)


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

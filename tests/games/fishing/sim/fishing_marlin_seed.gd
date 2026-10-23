extends SceneTree
## Finds a free_120 seed whose rider in slot 0 has a marlin in their pre-rolled slots (brief 4.2
## scenario 6), with the pure pre-roll, never with simulations:
##
##   tools/godot.sh --headless --path . -s tests/games/fishing/sim/fishing_marlin_seed.gd \
##       [-- --trip=free_120 --from=1 --to=500]
##
## Prints "marlin_seed=<n>" for the first seed in [from, to] and exits 0; prints "marlin_seed=none"
## and exits 1 when no seed has one (FishingPreroll returns no Free slots until fish-plan's pre-roll
## lands) or the content does not load.

const CONTENT := "res://content/fishing"


func _init() -> void:
	var opts := {"trip": "free_120", "from": "1", "to": "500"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var found := find_seed(str(opts["trip"]), int(opts["from"]), int(opts["to"]))
	print("marlin_seed=%s" % (str(found) if found > 0 else "none"))
	quit(0 if found > 0 else 1)


static func _json(rel: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(CONTENT.path_join(rel)))


## The first seed in [from, to] whose slot-0 pre-roll holds a marlin, or 0.
static func find_seed(trip_id: String, from: int, to: int) -> int:
	var trip: Variant = _json("trips/%s.json" % trip_id)
	var area := "coral_bank"
	if trip is Dictionary:
		area = str((trip as Dictionary).get("area", area))
	var c := FishingContent.new().parse(
		_json("species.json"), trip, _json("areas/%s.json" % area), _json("cosmetics.json")
	)
	if not c.ok:
		printerr("fishing_marlin_seed: content %s: %s" % [trip_id, "; ".join(c.errors)])
		return 0
	for n in range(from, to + 1):
		for s: FishingPlanSlot in FishingPreroll.roll(c.trip, c.species, n, 0):
			if s.species == "marlin":
				return n
	return 0

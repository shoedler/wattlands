class_name FishingAutopilot
extends RefCounted
## Autopilot's Free Roam choices for Autopilot riders and bots (pure; FishingRules calls it). It
## never changes effort targets: a human's power is their own; a bot's power follows the power
## band the rules publish for it (effort_frac x FTP while driving).
##
## Every Autopilot rider plays one strategy, a row of STRATEGY_TABLE: the zone it fishes, the
## drive effort (bots), which hint it casts at, and how often it moves on after a catch. Bots
## draw theirs per session (FishingGame, from ctx.rng); Autopilot humans play "mixed".
##   vibe   chilling: low effort, the shallows, any fish, rarely moves
##   small  many small fish near the dock: the near shallows, the smallest fish, moves on a bit
##   mixed  the reef, the biggest fish on offer
##   big    go big or go home: hard to the deep (or the abyss), only deep fish
## A zone farther than `reach` (half, "big": 70 %) of the play time left at the strategy's effort
## (FishingBoat speed) falls back to the next zone in. The stop x is drawn inside the zone from
## the rider's stream; in the menu the rider casts by its pick rule, moves on (move_on_p after a
## catch, or when no fish fits its zones), or turns around when its stop lies behind it or the
## edge is ahead.

const STRATEGIES: Array[String] = ["vibe", "small", "mixed", "big"]
const MIXED := 2
## zones (nearest first; scanned from the last, the first whose start the boat reaches within
## reach x the play time left wins), stop range inside the zone (fractions), effort (bots, FTP
## fraction), pick rule, move_on_p.
const STRATEGY_TABLE := {
	"vibe":
	{
		"zones": ["shallows", "bluewater"],
		"span": [0.1, 0.9],
		"effort": 0.55,
		"pick": "any",
		"move_on_p": 0.1,
		"reach": 0.5
	},
	"small":
	{
		"zones": ["shallows", "bluewater"],
		"span": [0.0, 0.35],
		"effort": 0.75,
		"pick": "light",
		"move_on_p": 0.25,
		"reach": 0.5
	},
	"mixed":
	{
		"zones": ["shallows", "reef", "bluewater"],
		"span": [0.1, 0.9],
		"effort": 0.85,
		"pick": "heavy",
		"move_on_p": 0.35,
		"reach": 0.5
	},
	"big":
	{
		"zones": ["shallows", "reef", "shelf", "deep", "abyss", "bluewater"],
		"span": [0.2, 0.9],
		"effort": 1.0,
		"pick": "heavy",
		"move_on_p": 0.2,
		"reach": 0.7
	},
}
## Bots ease off to this FTP fraction while stopped, casting or waiting.
const REST_EFFORT := 0.45
## The landing's gaff sprint for bots (FTP fraction; "vibe" bots do not sprint).
const SPRINT_EFFORT := 1.3
## Moving on inside a zone hops 200-800 m (15-55 s at cruise); with less room left than
## MOVE_ON_ROOM_M the rider plans a new stop (or turns around).
const MOVE_ON_MIN_M := 200.0
const MOVE_ON_MAX_M := 800.0
const MOVE_ON_ROOM_M := 300.0


static func row(r: FishingRiderState) -> Dictionary:
	var i := r.strategy if r.strategy >= 0 else MIXED
	return STRATEGY_TABLE[STRATEGIES[clampi(i, 0, STRATEGIES.size() - 1)]]


## The bot's power band centre (FTP fraction) for its action now.
static func effort_frac(r: FishingRiderState) -> float:
	var rw := row(r)
	match r.action:
		FishingConst.A_DRIVE:
			return float(rw["effort"])
		FishingConst.A_LAND:
			if r.landing_t < FishingConst.GAFF_S and STRATEGIES[maxi(r.strategy, 0)] != "vibe":
				return SPRINT_EFFORT
	return REST_EFFORT


## Picks the stop x for the rider's strategy (seaward of x only when heading out).
static func plan_stop(st: FishingState, r: FishingRiderState) -> void:
	var rw := row(r)
	var zones: Array = rw["zones"]
	var left_s := maxf(st.play_end_t - st.t, 1.0)
	var v := FishingBoat.cruise_speed(float(rw["effort"]) * FishingConst.P_EFF_REF_W)
	var pick: Dictionary = {}
	for i in range(zones.size() - 1, -1, -1):
		var z := _zone(st.world, str(zones[i]))
		if z.is_empty():
			continue
		var reach := maxf(float(z["x0"]) - r.x_m, 0.0) / maxf(v, 0.1)
		pick = z
		if reach <= float(rw["reach"]) * left_s:
			break
	if pick.is_empty():
		r.stop_x = r.x_m
		return
	var span: Array = rw["span"]
	var x0 := float(pick["x0"])
	var x1 := minf(float(pick["x1"]), st.world.edge_x_m() - 20.0)
	r.stop_x = lerpf(x0, x1, r.rng.range_f(float(span[0]), float(span[1])))


## True when a driving Autopilot rider should let the boat drift to a stop here.
static func wants_stop(r: FishingRiderState) -> bool:
	if is_nan(r.stop_x):
		return false
	return (r.heading > 0 and r.x_m >= r.stop_x) or (r.heading < 0 and r.x_m <= r.stop_x)


## The menu entry index to pick, or -1 to wait. `just_landed`: back from a catch.
static func menu_pick(st: FishingState, r: FishingRiderState, just_landed: bool) -> int:
	if r.menu.is_empty() or st.time_up:
		return -1
	var at_edge := r.heading > 0 and r.x_m >= st.world.edge_x_m() - 1.0
	if is_nan(r.stop_x):
		plan_stop(st, r)
	var behind := (r.stop_x - r.x_m) * float(r.heading) < -100.0
	if at_edge or behind:
		return r.menu.find(FishingConst.M_TURN)
	if (r.stop_x - r.x_m) * float(r.heading) > 100.0:
		return r.menu.find(FishingConst.M_DRIVE_ON)
	if just_landed and r.rng.unit() < float(row(r)["move_on_p"]):
		return _move_on(st, r)
	var best := best_hint(st, r)
	if best < 0:
		return _move_on(st, r)
	return r.menu.find(best)


## The hint to cast at by the strategy's pick rule among fish of its zones; -1 when none fits.
static func best_hint(st: FishingState, r: FishingRiderState) -> int:
	var rw := row(r)
	var zones: Array = rw["zones"]
	var rule := str(rw["pick"])
	var best := -1
	var best_v := 0.0
	for i in r.hint_count():
		var sp := int(r.hints[4 * i])
		var zone := st.world.zone_at(r.x_m)
		if not zones.has(zone):
			continue
		var w := r.hints[4 * i + 3]
		var score := 0.0
		match rule:
			"light":
				score = -float(sp) - w
			"heavy":
				score = float(sp) + w
			_:
				score = -float(i)
		if best < 0 or score > best_v:
			best = i
			best_v = score
	return best


static func _move_on(st: FishingState, r: FishingRiderState) -> int:
	var z := _zone(st.world, st.world.zone_at(r.x_m))
	var room := (
		float(z.get("x1", r.x_m)) - r.x_m if r.heading > 0 else r.x_m - float(z.get("x0", 0))
	)
	if room < MOVE_ON_ROOM_M:
		r.stop_x = NAN
		plan_stop(st, r)
		if absf(r.stop_x - r.x_m) < 100.0:
			return r.menu.find(FishingConst.M_TURN)
	else:
		var hop := r.rng.range_f(MOVE_ON_MIN_M, minf(MOVE_ON_MAX_M, room - 20.0))
		r.stop_x = r.x_m + float(r.heading) * hop
	return r.menu.find(FishingConst.M_DRIVE_ON)


static func _zone(world: FishingWorld, zid: String) -> Dictionary:
	for z in world.zones():
		if str(z["id"]) == zid:
			return z
	return {}

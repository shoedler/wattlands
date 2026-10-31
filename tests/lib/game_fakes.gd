class_name TestGameFakes
extends RefCounted
## What every game's <id>_fakes.gd shares: the recording sinks a GameContext needs and the plan
## helpers. A game's fakes extend this and add its own Directives, make_ctx, frame and make_game, so
## tests reach all of it through the game's own class (F.Hud, F.plans_of).


class Hud:
	extends HudFeed
	## The game time of the tick being stepped (a game's run() may set it).
	var t: float = 0.0
	## [name, args...] in call order.
	var calls: Array = []
	## [[t, peer, lo_w, hi_w]] (power_band calls with the time).
	var power_band_at: Array = []

	func power_band(peer: int, lo_w: float, hi_w: float) -> void:
		calls.append(["power_band", peer, lo_w, hi_w])
		power_band_at.append([t, peer, lo_w, hi_w])

	func teammate_status(peer: int, status: Dictionary) -> void:
		calls.append(["teammate_status", peer, status])

	func toast(key: String, args: Variant = [], peer: int = 0) -> void:
		calls.append(["toast", key, args, peer])

	func banner(key: String, args: Variant = [], seconds: float = 3.0, peer: int = 0) -> void:
		calls.append(["banner", key, args, seconds, peer])

	func readout(id: String, text: String) -> void:
		calls.append(["readout", id, text])

	func of(call_name: String) -> Array:
		return calls.filter(func(c: Array) -> bool: return c[0] == call_name)


class Intents:
	extends IntentSink
	var sent: Array = []

	func send(intent: Dictionary) -> void:
		sent.append(intent)


class Stats:
	extends SessionStats
	## peer -> partial base row (missing keys are zeros).
	var rows: Dictionary = {}

	func base_row(peer: int) -> Dictionary:
		var row := super.base_row(peer)
		row.merge(rows.get(peer, {}), true)
		return row

	func kj(peer: int) -> float:
		return float(base_row(peer)["kj"])


## Defaults of a manifest option list ({id: default}).
static func option_defaults(entries: Variant) -> Dictionary:
	var out := {}
	for e: Variant in entries if entries is Array else []:
		out[str(e["id"])] = e["default"]
	return out


## The plan with the platform's cool-down appended (what the PlanValidator returns).
static func with_cooldown(plan: EffortPlan) -> EffortPlan:
	var p := plan.duplicate_plan()
	p.add(PlanValidator.cooldown_phase())
	p.cooldown_appended = true
	return p


## Plans from the module, each with the cool-down appended.
static func plans_of(game: GameModule) -> Dictionary:
	var out := {}
	var built := game.build_effort_plans()
	for peer: int in built:
		out[peer] = with_cooldown(built[peer])
	return out

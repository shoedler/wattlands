class_name TankDifficulty
extends RefCounted
## v4: the difficulty table (enemies.json difficulty). Only rules, HUD and results read it. effort/ and
## TankSeatPlan never do (tests/games/tank/static asserts it): no effort number, plan or governor input.


## The level an option value means: auto takes the mission's difficulty_default (normal without one).
static func resolve(option: Variant, c: TankContent) -> String:
	var v := str(option)
	if v == "" or v == TankIds.DIFF_AUTO:
		v = str(c.mission().get("difficulty_default", TankIds.DIFF_NORMAL)) if c != null else ""
	return v if TankIds.DIFFICULTIES.has(v) else TankIds.DIFF_NORMAL


static func row(state: TankState) -> Dictionary:
	if state == null or state.content == null:
		return {}
	return state.content.value("enemies", "difficulty.%s" % state.difficulty, {})


## A multiplier from the row ("hp", "damage", "accuracy", "count", "telegraph", "repair"), default 1.
static func mult(state: TankState, key: String) -> float:
	return float(row(state).get(key, 1.0))


## Hull at 0 is a real defeat: not on Easy, never in a warm-up kind (the drill's skirmish).
static func tank_loss(state: TankState) -> bool:
	return bool(row(state).get("tank_loss", false)) and state.seg.kind != Wl.WARMUP

class_name SiegeAutopilot
extends RefCounted
## Autopilot's routing and shop decisions (brief 2.5). Owner: B2 "module". Pure, static and
## deterministic (reads only the state; no RNG needed). Never changes effort targets and never
## triggers Overdrive: it only returns route targets and normalized buy intents.
##
## Who calls it (ADR "Autopilot runs inside the host rules"): SiegeRules (B1) for every rider
## whose route_fallback / shop_fallback is true (bots, Autopilot-on humans and humans who haven't
## routed or bought by hand yet), in slot order: route_choice() once a second, shop_picks() in a
## break at balance.json autopilot.shop_at_s (at most 2 buys per break). GameModule's
## autopilot_intents() returns [] (the platform never calls it for Autopilot-off humans, so the
## rules own every fallback). The HUD's shop panel also calls shop_picks() on clients for its top
## entry (the recommendation), from the snapshot-rebuilt state.
##
## Contract notes for the callers:
## - route_choice() writes nothing. The caller applies a returned target (and sets
##   rider.routed_t = state.t and the reconnect), because the 8 s switch limit reads routed_t.
## - shop_picks(max_items) returns at most max_items picks and does NOT subtract rider.ap_buys:
##   pass what is left of the break's two.
## - Both return nothing outside their window: routing only in a wave (a break keeps the
##   target), the shop only while it is open.


## The target `rider` should route to now (TARGET_GEN or a pad), or -1 to keep the current one.
## Rules: the tower with the most enemy HP in range (state.enemy_hp_in_range), within the
## 2-rider limit (state.routed_count); none in range: the generator; ties go to the lower pad;
## switch at most once per 8 s (rider.routed_t) and only for >= 25% more enemy HP.
static func route_choice(state: SiegeState, rider: SiegeRiderState) -> int:
	if state == null or rider == null or state.content == null:
		return -1
	if not state.in_wave() or rider.afk or not rider.connected:
		return -1
	var best := _best_pad(state, rider)
	var want := SiegeIds.TARGET_GEN if best.is_empty() else int(best["pad"])
	if want == rider.target:
		return -1
	if state.t - rider.routed_t < state.content.num("autopilot.switch_min_s", 8.0):
		return -1
	if want != SiegeIds.TARGET_GEN:
		var cur_hp := (
			state.enemy_hp_in_range(rider.target) if SiegeIds.is_pad(rider.target) else 0.0
		)
		var margin := state.content.num("autopilot.switch_margin", 0.25)
		if float(best["hp"]) < cur_hp * (1.0 + margin) - 1e-9:
			return -1
	return want


## The "hot" tower for the down control (brief 2.4): the pad with the most enemy HP in range,
## within the 2-rider limit, ties to the lower pad. -1 when no tower has an enemy in range.
static func hot_target(state: SiegeState, rider: SiegeRiderState) -> int:
	if state == null or rider == null or state.content == null:
		return -1
	return SiegeRouting.hot_pad(state, rider)


## Autopilot's shop picks for `rider` in this break, best first, as normalized buy intents
## (SiegeIntents.normalize form, "auto": true), at most `max_items`. Order (brief 2.5): repair
## below 50%; build on the road with the most gate damage (Ballista vs Shield walls or rams,
## Caltrop vs Horsemen if that road has none, else Scorpion; no damage yet: Ballista, Scorpion,
## Caltrop in turn on the least-covered road); upgrade the lowest tower on that road; generator
## level; Iron bands; perks; save (an empty list). A pick must be affordable with what is left
## after the earlier picks; an unaffordable or impossible step falls through to the next one.
static func shop_picks(
	state: SiegeState, rider: SiegeRiderState, max_items: int = 2
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or rider == null or state.content == null or max_items <= 0:
		return out
	if not state.shop_open() or state.content.map == null:
		return out
	var plan := ShopPlan.new(state, rider.denarii)
	for _i in max_items:
		var pick := plan.next_pick()
		if pick.is_empty():
			break
		out.append(SiegeIntents.normalize(SiegeIntents.buy(pick["item"], pick["pad"], true)))
	return out


## The road Autopilot defends in the shop: the one with the most gate damage, else the least
## covered by towers (ties to the lower road index).
static func target_road(state: SiegeState) -> int:
	if state == null or state.content == null or state.content.map == null:
		return 0
	return ShopPlan.new(state, 0.0).road()


## The tower type Autopilot would build on `road` now (see shop_picks): Ballista against Shield
## walls or rams, Caltrop against Horsemen, else Scorpion; with no gate damage yet the type built
## least, in the order Ballista, Scorpion, Caltrop.
static func build_type(state: SiegeState, road: int) -> int:
	if state == null or state.content == null or state.content.map == null:
		return SiegeIds.TOWER_BALLISTA
	return ShopPlan.new(state, 0.0).build_type_for(road)


## The best pad `rider` may join: {"pad", "hp"} (most enemy HP in reach, ties to the lower pad,
## towers already holding 2 other riders skipped), or {} when no tower has an enemy in reach. The
## rules' own "hot" resolution (SiegeRouting.hot_choice), so the three never differ.
static func _best_pad(state: SiegeState, rider: SiegeRiderState) -> Dictionary:
	return SiegeRouting.hot_choice(state, rider)


## A throwaway copy of what a rider could buy, so the second pick sees the first.
class ShopPlan:
	extends RefCounted
	var state: SiegeState
	var funds: float = 0.0
	var gate_hp: float = 0.0
	var gate_max: float = 0.0
	var gen_level: int = 0
	var bands: int = 0
	var perks: Array[int] = []
	## pad -> [type, level] of the towers built (and bought by earlier picks).
	var towers: Dictionary = {}

	func _init(p_state: SiegeState, p_funds: float) -> void:
		state = p_state
		funds = p_funds
		gate_hp = state.gate_hp
		gate_max = state.gate_max
		gen_level = state.gen_level
		bands = state.iron_bands
		perks = state.perks.duplicate()
		for tw in state.pads:
			if tw.built():
				towers[tw.pad] = [tw.type, tw.level]

	## The next pick as {"item", "pad", "cost"} (applied to this copy), or {} to save.
	func next_pick() -> Dictionary:
		var pick := _repair()
		if pick.is_empty():
			pick = _build()
		if pick.is_empty():
			pick = _upgrade()
		if pick.is_empty():
			pick = _generator()
		if pick.is_empty():
			pick = _iron_bands()
		if pick.is_empty():
			pick = _perk()
		return pick

	func road() -> int:
		var dmg := state.gate_damage_by_road
		var best := 0
		var total := 0.0
		for r in dmg.size():
			total += dmg[r]
			if dmg[r] > dmg[best] + 1e-9:
				best = r
		if total > 0.0:
			return best
		var least := 0
		var least_cover := 1000000
		for r in SiegeIds.ROAD_COUNT:
			var c := _cover(r)
			if c < least_cover:
				least_cover = c
				least = r
		return least

	func _dist(pad: int, r: int) -> float:
		return state.content.map.distance_to_road(state.content.map.pad_pos(pad), r)

	func _cover(r: int) -> int:
		var n := 0
		for pad: int in towers:
			if _reach(pad) >= _dist(pad, r):
				n += 1
		return n

	func _reach(pad: int) -> float:
		var t: Array = towers[pad]
		var base := float(state.content.tower_def(int(t[0])).get("range_m", 0.0))
		return base * 1.25 if int(t[1]) >= 2 else base

	func _spend(cost: float) -> bool:
		if cost > funds + 1e-9:
			return false
		funds -= cost
		return true

	func _repair() -> Dictionary:
		var cost := state.content.num("shop.repair", 20.0)
		var below := state.content.num("autopilot.repair_below_frac", 0.5)
		if gate_hp >= gate_max or gate_hp / maxf(gate_max, 1.0) >= below:
			return {}
		if not _spend(cost):
			return {}
		gate_hp = minf(gate_hp + state.content.num("gate.repair_hp", 20.0), gate_max)
		return {"item": SiegeIds.ITEM_REPAIR, "pad": 0, "cost": cost}

	## The preferred type on the road; when no free pad is in its reach (a Scorpion's 18 m), the
	## Ballista, Caltrop thrower or Scorpion that has one. An unaffordable type is not swapped
	## for a cheaper one: the step falls through.
	func _build() -> Dictionary:
		var r := road()
		var preferred := build_type_for(r)
		var order: Array[int] = [preferred]
		for t: int in [SiegeIds.TOWER_BALLISTA, SiegeIds.TOWER_CALTROP, SiegeIds.TOWER_SCORPION]:
			if t != preferred:
				order.append(t)
		for type in order:
			var def := state.content.tower_def(type)
			var cost := float(def.get("cost", 0.0))
			var pad := _free_pad(r, float(def.get("range_m", 0.0)))
			if pad == 0:
				continue
			if not _spend(cost):
				return {}
			towers[pad] = [type, 0]
			return {"item": _build_item(type), "pad": pad, "cost": cost}
		return {}

	## Ballista against Shield walls or rams on the road, a Caltrop thrower against Horsemen
	## when it has none, otherwise a Scorpion; no damage yet: the type built least, in the
	## order Ballista, Scorpion, Caltrop. In a break nobody is on the road, so damage on it
	## means the heavy enemies (every wave pushes a ram up each active road): a Ballista.
	func build_type_for(r: int) -> int:
		var total := 0.0
		for d in state.gate_damage_by_road:
			total += d
		if total <= 0.0:
			var counts := {
				SiegeIds.TOWER_BALLISTA: 0, SiegeIds.TOWER_SCORPION: 0, SiegeIds.TOWER_CALTROP: 0
			}
			for pad: int in towers:
				counts[int((towers[pad] as Array)[0])] += 1
			var pick := SiegeIds.TOWER_BALLISTA
			for t: int in [SiegeIds.TOWER_SCORPION, SiegeIds.TOWER_CALTROP]:
				if counts[t] < counts[pick]:
					pick = t
			return pick
		var live := 0
		var horsemen := false
		for e in state.enemies:
			if e.road != r or e.st == SiegeIds.EN_RETREAT:
				continue
			live += 1
			if e.type == SiegeIds.ENEMY_SHIELD_WALL or e.type == SiegeIds.ENEMY_RAM:
				return SiegeIds.TOWER_BALLISTA
			horsemen = horsemen or e.type == SiegeIds.ENEMY_HORSEMEN
		if live == 0:
			return SiegeIds.TOWER_BALLISTA
		return SiegeIds.TOWER_CALTROP if horsemen else SiegeIds.TOWER_SCORPION

	func _build_item(type: int) -> String:
		for item: String in SiegeIds.BUILD_TOWER:
			if int(SiegeIds.BUILD_TOWER[item]) == type:
				return item
		return SiegeIds.ITEM_BUILD_BALLISTA

	## The empty pad closest to road `r` that its tower could still reach, ties to the lower pad.
	func _free_pad(r: int, reach: float) -> int:
		var best := 0
		var best_d := INF
		for n in range(1, SiegeIds.PAD_COUNT + 1):
			if towers.has(n):
				continue
			var d := _dist(n, r)
			if d <= reach and d < best_d - 1e-9:
				best = n
				best_d = d
		return best

	func _upgrade() -> Dictionary:
		var r := road()
		var best := 0
		var best_level := SiegeIds.MAX_TOWER_LEVEL
		for n in range(1, SiegeIds.PAD_COUNT + 1):
			if not towers.has(n):
				continue
			var level := int((towers[n] as Array)[1])
			if level >= SiegeIds.MAX_TOWER_LEVEL or _dist(n, r) > _reach(n):
				continue
			if level < best_level:
				best = n
				best_level = level
		if best == 0:
			return {}
		var cost := float(state.content.upgrade_cost(best_level + 1))
		if cost < 0.0 or not _spend(cost):
			return {}
		(towers[best] as Array)[1] = best_level + 1
		return {"item": SiegeIds.ITEM_UPGRADE, "pad": best, "cost": cost}

	func _generator() -> Dictionary:
		var costs: Array = state.content.balance.get("generator", {}).get("level_costs", [])
		if gen_level >= costs.size():
			return {}
		var cost := float(costs[gen_level])
		if not _spend(cost):
			return {}
		gen_level += 1
		return {"item": SiegeIds.ITEM_GENERATOR, "pad": 0, "cost": cost}

	func _iron_bands() -> Dictionary:
		var cost := state.content.num("shop.iron_bands", 45.0)
		if bands >= int(state.content.num("gate.iron_bands_max", 2.0)) or not _spend(cost):
			return {}
		bands += 1
		return {"item": SiegeIds.ITEM_IRON_BANDS, "pad": 0, "cost": cost}

	func _perk() -> Dictionary:
		for spec: Array in [
			[SiegeIds.PERK_RESERVE, SiegeIds.ITEM_RESERVE, "shop.reserve_flywheel"],
			[SiegeIds.PERK_AQUEDUCT, SiegeIds.ITEM_AQUEDUCT, "shop.aqueduct_drive"],
		]:
			if perks.has(int(spec[0])):
				continue
			var cost := state.content.num(str(spec[2]), 80.0)
			if not _spend(cost):
				return {}
			perks.append(int(spec[0]))
			return {"item": spec[1], "pad": 0, "cost": cost}
		return {}

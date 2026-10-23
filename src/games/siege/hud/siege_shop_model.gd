class_name SiegeShopModel
extends RefCounted
## The entries of the break shop panel (brief 2.4 "Shop", 3 HUD): the top entry is the
## Autopilot's recommendation (SiegeAutopilot.shop_picks), the second is "Save denarii", then
## what else the rider could buy right now. Pure: the panel feeds it the state and draws the
## result in a PedalScanList.
##
## An entry is {"id": {"item": String, "pad": int}, "text": String, "detail": String,
## "cost": int, "disabled": bool, "recommended": bool}. The Save entry has item ITEM_SAVE and
## is never sent as an intent.

const MAX_ENTRIES := 6


## The empty pad a new tower fits best: nearest to the road with the most gate damage so far,
## else nearest to any road (ties go to the lower pad). 0 when every pad is built.
static func suggest_pad(state: SiegeState) -> int:
	var map: SiegeMap = state.content.map
	var hot := -1
	var most := 0.0
	for road in SiegeIds.ROAD_COUNT:
		if state.gate_damage_by_road[road] > most:
			most = state.gate_damage_by_road[road]
			hot = road
	var best := 0
	var best_d := INF
	for pad in range(1, SiegeIds.PAD_COUNT + 1):
		if state.pad(pad).built():
			continue
		var p := map.pad_pos(pad)
		var d := INF
		if hot >= 0:
			d = map.distance_to_road(p, hot)
		else:
			for road in SiegeIds.ROAD_COUNT:
				d = minf(d, map.distance_to_road(p, road))
		if d < best_d - 1e-6:
			best_d = d
			best = pad
	return best


## The built tower an upgrade is best spent on: the lowest level below 3, ties to the lower
## pad. 0 when there is none.
static func upgrade_pad(state: SiegeState) -> int:
	var best := 0
	var level := 99
	for tw in state.pads:
		if tw.built() and tw.level < SiegeIds.MAX_TOWER_LEVEL and tw.level < level:
			level = tw.level
			best = tw.pad
	return best


## The cost of an item now (-1 when it can't be bought).
static func cost_of(state: SiegeState, item: String, pad: int) -> int:
	var c := state.content
	match item:
		SiegeIds.ITEM_BUILD_BALLISTA, SiegeIds.ITEM_BUILD_SCORPION, SiegeIds.ITEM_BUILD_CALTROP:
			if pad < 1 or state.pad(pad).built():
				return -1
			return int(c.tower_def(int(SiegeIds.BUILD_TOWER[item])).get("cost", -1))
		SiegeIds.ITEM_UPGRADE:
			if pad < 1 or not state.pad(pad).built():
				return -1
			return c.upgrade_cost(state.pad(pad).level + 1)
		SiegeIds.ITEM_GENERATOR:
			var costs: Array = (c.balance.get("generator", {}) as Dictionary).get("level_costs", [])
			return int(costs[state.gen_level]) if state.gen_level < costs.size() else -1
		SiegeIds.ITEM_IRON_BANDS:
			if state.iron_bands >= int(c.num("gate.iron_bands_max", 2.0)):
				return -1
			return int(c.num("shop.iron_bands", 45.0))
		SiegeIds.ITEM_REPAIR:
			if state.gate_hp >= state.gate_max:
				return -1
			return int(c.num("shop.repair", 20.0))
		SiegeIds.ITEM_RESERVE:
			if state.perks.has(SiegeIds.PERK_RESERVE):
				return -1
			return int(c.num("shop.reserve_flywheel", 80.0))
		SiegeIds.ITEM_AQUEDUCT:
			if state.perks.has(SiegeIds.PERK_AQUEDUCT):
				return -1
			return int(c.num("shop.aqueduct_drive", 100.0))
	return -1


static func _text_of(state: SiegeState, strings: GameStrings, item: String, pad: int) -> String:
	match item:
		SiegeIds.ITEM_BUILD_BALLISTA, SiegeIds.ITEM_BUILD_SCORPION, SiegeIds.ITEM_BUILD_CALTROP:
			return strings.t("SIEGE_SHOP_%s" % item.to_upper(), [pad])
		SiegeIds.ITEM_UPGRADE:
			return strings.t(
				"SIEGE_SHOP_UPGRADE_ON_PAD", [pad, state.pad(pad).level + 1 if pad >= 1 else 1]
			)
		SiegeIds.ITEM_GENERATOR:
			return strings.t("SIEGE_SHOP_GEN_LEVEL", [state.gen_level + 1])
		SiegeIds.ITEM_SAVE:
			return strings.t("SIEGE_ITEM_SAVE")
	return strings.t("SIEGE_ITEM_%s" % item.to_upper())


static func _entry(
	state: SiegeState,
	strings: GameStrings,
	rider: SiegeRiderState,
	item: String,
	pad: int,
	recommended: bool
) -> Dictionary:
	var cost := 0 if item == SiegeIds.ITEM_SAVE else cost_of(state, item, pad)
	var affordable := (
		item == SiegeIds.ITEM_SAVE or (cost >= 0 and float(cost) <= floorf(rider.denarii))
	)
	var text := _text_of(state, strings, item, pad)
	return {
		"id": {"item": item, "pad": pad},
		"text":
		text if item == SiegeIds.ITEM_SAVE else strings.t("SIEGE_SHOP_ITEM_COST", [text, cost]),
		"detail": strings.t("SIEGE_SHOP_PICK_TAG") if recommended else "",
		"cost": cost,
		"disabled": not affordable,
		"recommended": recommended,
	}


## The entries for `rider`. `picks` are the Autopilot's recommendations (normalized buy intents,
## best first; only the first is used).
static func entries(
	state: SiegeState, rider: SiegeRiderState, strings: GameStrings, picks: Array[Dictionary]
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or rider == null or state.content == null:
		return out
	var seen := {}
	if not picks.is_empty():
		var p := picks[0]
		var item := str(p.get("item", ""))
		var pad := int(p.get("pad", 0))
		if SiegeIds.ITEMS.has(item) and cost_of(state, item, pad) >= 0:
			out.append(_entry(state, strings, rider, item, pad, true))
			seen["%s/%d" % [item, pad]] = true
	out.append(_entry(state, strings, rider, SiegeIds.ITEM_SAVE, 0, false))
	var empty_pad := suggest_pad(state)
	var up_pad := upgrade_pad(state)
	var wanted: Array = [
		[SiegeIds.ITEM_REPAIR, 0],
		[SiegeIds.ITEM_BUILD_BALLISTA, empty_pad],
		[SiegeIds.ITEM_BUILD_SCORPION, empty_pad],
		[SiegeIds.ITEM_BUILD_CALTROP, empty_pad],
		[SiegeIds.ITEM_UPGRADE, up_pad],
		[SiegeIds.ITEM_GENERATOR, 0],
		[SiegeIds.ITEM_IRON_BANDS, 0],
		[SiegeIds.ITEM_RESERVE, 0],
		[SiegeIds.ITEM_AQUEDUCT, 0],
	]
	for w: Array in wanted:
		if out.size() >= MAX_ENTRIES:
			break
		var item: String = w[0]
		var pad: int = w[1]
		if SiegeIds.PAD_ITEMS.has(item) and pad < 1:
			continue
		if seen.has("%s/%d" % [item, pad]) or cost_of(state, item, pad) < 0:
			continue
		out.append(_entry(state, strings, rider, item, pad, false))
	return out


## A string that changes when the list's content does (the panel rebuilds only then).
static func signature(list: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for e in list:
		var id: Dictionary = e["id"]
		parts.append("%s/%d/%d" % [id["item"], id["pad"], int(bool(e["disabled"]))])
	return "|".join(parts)

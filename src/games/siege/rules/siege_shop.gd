class_name SiegeShop
extends RefCounted
## The shop (brief 2.4 "Shop", 2.5 "Zero input"). Pure. Open in every break (the build break
## included), closed in waves and the cool-down. The host resolves purchases in arrival order
## (slot order, then each rider's intents in order); every buy answers with a `buy` event (ok 1,
## or ok 0 with the buyer's slot and a SiegeIds.BUY_* reason; only the buyer's peer toasts).
##
## Items and prices (balance.json, towers.json):
##   build_ballista / scorpion / caltrop   50 / 40 / 35 on an empty pad
##   upgrade                               40 / 50 / 70, the pad's next level (1: +40% output,
##                                         2: +25% range, 3: the special)
##   generator                             60 / 90 / 130, the next team level (+20% denarii each)
##   iron_bands                            45, +25 max and current gate HP, twice
##   repair                                20, +20 gate HP up to the max
##   reserve_flywheel / aqueduct_drive     80 / 100, team perks, once each
## Checks run in this order: closed, then the item's own limit, then funds.
##
## Zero input: a rider is shop-fallback (Autopilot buys for them) while shop_fallback (until
## their first buy intent that was not auto-confirmed; bots never clear it) or autopilot. While
## so, their auto-confirmed buys are ignored (no double purchase) and the rules call
## SiegeAutopilot.shop_picks at autopilot.shop_at_s into the break, at most autopilot.shop_max
## per break.

## Test seam: when valid, called as shop_hook.call(state, rider, max_items) -> Array of
## normalized buy intents instead of SiegeAutopilot.shop_picks.
static var shop_hook: Callable = Callable()


## True while Autopilot shops for `r`.
static func autopiloted(r: SiegeRiderState) -> bool:
	return r.autopilot or r.shop_fallback


## Applies one normalized buy intent from `r`.
static func intent(
	state: SiegeState, r: SiegeRiderState, it: Dictionary, events: Array[Dictionary]
) -> void:
	var auto := bool(it.get("auto", false))
	if auto and autopiloted(r):
		return
	if auto and not state.shop_open():
		return
	if not auto and not r.is_bot:
		r.shop_fallback = false
	events.append(buy(state, r, str(it.get("item", "")), int(it.get("pad", 0))))


## Resolves one purchase and returns its `buy` event.
static func buy(state: SiegeState, r: SiegeRiderState, item: String, pad: int) -> Dictionary:
	var res := purchase(state, r, item, pad)
	return SiegeEvents.buy(
		r.slot, item, pad, str(res["why"]) == SiegeIds.BUY_OK, str(res["why"]), int(res["lvl"])
	)


## Checks and (when allowed) performs a purchase; {"why": BUY_*, "lvl": level after it}.
static func purchase(state: SiegeState, r: SiegeRiderState, item: String, pad: int) -> Dictionary:
	if not state.shop_open():
		return _res(SiegeIds.BUY_CLOSED)
	var c := state.content
	var cost := 0.0
	var lvl := 0
	match item:
		SiegeIds.ITEM_BUILD_BALLISTA, SiegeIds.ITEM_BUILD_SCORPION, SiegeIds.ITEM_BUILD_CALTROP:
			if not SiegeIds.is_pad(pad):
				return _res(SiegeIds.BUY_NO_TOWER)
			if state.pad(pad).built():
				return _res(SiegeIds.BUY_PAD_TAKEN)
			cost = float(c.tower_def(int(SiegeIds.BUILD_TOWER[item])).get("cost", 0.0))
		SiegeIds.ITEM_UPGRADE:
			if not SiegeIds.is_pad(pad) or not state.pad(pad).built():
				return _res(SiegeIds.BUY_NO_TOWER)
			lvl = state.pad(pad).level + 1
			if lvl > SiegeIds.MAX_TOWER_LEVEL:
				return _res(SiegeIds.BUY_MAX_LEVEL)
			cost = float(c.upgrade_cost(lvl))
		SiegeIds.ITEM_GENERATOR:
			var costs: Array = c.balance["generator"]["level_costs"]
			if state.gen_level >= costs.size():
				return _res(SiegeIds.BUY_MAX_LEVEL)
			lvl = state.gen_level + 1
			cost = float(costs[state.gen_level])
		SiegeIds.ITEM_IRON_BANDS:
			if state.iron_bands >= int(c.num("gate.iron_bands_max", 2.0)):
				return _res(SiegeIds.BUY_LIMIT)
			cost = c.num("shop.iron_bands", 45.0)
		SiegeIds.ITEM_REPAIR:
			if state.gate_hp >= state.gate_max:
				return _res(SiegeIds.BUY_GATE_FULL)
			cost = c.num("shop.repair", 20.0)
		SiegeIds.ITEM_RESERVE:
			if state.perks.has(SiegeIds.PERK_RESERVE):
				return _res(SiegeIds.BUY_LIMIT)
			cost = c.num("shop.reserve_flywheel", 80.0)
		SiegeIds.ITEM_AQUEDUCT:
			if state.perks.has(SiegeIds.PERK_AQUEDUCT):
				return _res(SiegeIds.BUY_LIMIT)
			cost = c.num("shop.aqueduct_drive", 100.0)
		_:
			return _res(SiegeIds.BUY_NO_TOWER)
	if r.denarii + 1e-9 < cost:
		return _res(SiegeIds.BUY_FUNDS)
	r.denarii = maxf(r.denarii - cost, 0.0)
	match item:
		SiegeIds.ITEM_BUILD_BALLISTA, SiegeIds.ITEM_BUILD_SCORPION, SiegeIds.ITEM_BUILD_CALTROP:
			var tw := state.pad(pad)
			tw.type = int(SiegeIds.BUILD_TOWER[item])
			tw.level = 0
			tw.m = 0.0
			tw.hold_m = 0.0
			tw.hold_s = 0.0
			tw.cd_s = float(c.tower_def(tw.type).get("interval_s", 1.0))
			tw.age_s = 0.0
			tw.built_by = r.slot
			tw.kills = 0
			tw.damage = 0.0
			r.towers_built += 1
		SiegeIds.ITEM_UPGRADE:
			state.pad(pad).level = lvl
		SiegeIds.ITEM_GENERATOR:
			state.gen_level = lvl
		SiegeIds.ITEM_IRON_BANDS:
			var add := c.num("gate.iron_bands_hp", 25.0)
			state.iron_bands += 1
			state.gate_max += add
			state.gate_hp += add
			lvl = state.iron_bands
		SiegeIds.ITEM_REPAIR:
			state.gate_hp = minf(state.gate_hp + c.num("gate.repair_hp", 20.0), state.gate_max)
			lvl = ceili(state.gate_hp)
		SiegeIds.ITEM_RESERVE:
			state.perks.append(SiegeIds.PERK_RESERVE)
			lvl = 1
		SiegeIds.ITEM_AQUEDUCT:
			state.perks.append(SiegeIds.PERK_AQUEDUCT)
			lvl = 1
	return _res(SiegeIds.BUY_OK, lvl)


## Autopilot's purchases for riders on the shop fallback, in slot order, once the break has run
## autopilot.shop_at_s[ap_buys] seconds (4 s for the first, 9 s for the second).
static func autopilot(state: SiegeState, _inputs: SiegeInputs, events: Array[Dictionary]) -> void:
	if not state.shop_open():
		return
	var c := state.content
	var max_buys := int(c.num("autopilot.shop_max", 2.0))
	var at: Array = c.balance["autopilot"]["shop_at_s"]
	for r in state.riders:
		if not autopiloted(r) or r.ap_buys >= max_buys or at.is_empty():
			continue
		if state.phase_elapsed_s < float(at[mini(r.ap_buys, at.size() - 1)]):
			continue
		var picks := pick(state, r, 1)
		if picks.is_empty():
			r.ap_buys = max_buys
			continue
		r.ap_buys += 1
		var it := picks[0]
		events.append(buy(state, r, str(it.get("item", "")), int(it.get("pad", 0))))


## Autopilot's picks for `r` (best first, normalized buy intents).
static func pick(state: SiegeState, r: SiegeRiderState, max_items: int) -> Array[Dictionary]:
	if shop_hook.is_valid():
		var out: Array[Dictionary] = []
		for x: Variant in shop_hook.call(state, r, max_items):
			out.append(x)
		return out
	return SiegeAutopilot.shop_picks(state, r, max_items)


static func _res(why: String, lvl: int = 0) -> Dictionary:
	return {"why": why, "lvl": lvl}

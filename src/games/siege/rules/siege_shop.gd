class_name SiegeShop
extends RefCounted
## The shop (brief 2.4 "Shop", 2.5 "Zero input"). Pure. Open in every break (the build break
## included), closed in waves and the cool-down. A pick does not buy: it goes through
## SiegeReceipt (add, take back, vote), and the receipt is bought here, item by item, when the
## break ends. Every purchase answers with a `buy` event (ok 1, or ok 0 with the buyer's slot and
## a SiegeIds.BUY_* reason; only the buyer's peer toasts); so does a pick the shop would refuse.
## Gold is personal and anyone may pick anything.
##
## Items and prices (stations.json, balance.json):
##   upgrade (station 1..4)        40 / 50 / 70, the station's next level, team-wide (1: +40%
##                                 output, 2: +25% range / curtain max, 3: the special)
##   mine                          60 / 90 / 130, the next mine level (+20% gold each)
##   scorpion (pad 1..4)           40 on an empty pad
##   pad_upgrade (pad 1..4)        40 / 50 / 70, the pad's next level
##   iron_bands                    45, +25 max and current gate HP, twice
##   repair                        20, +20 gate HP up to the max
##   reserve_flywheel / aqueduct_drive / spare_cauldron   80 / 100 / 60, team perks, once each
## Checks run in this order: closed, then the item's own limit, then funds.
##
## Zero input: a rider is shop-fallback (Autopilot picks for them) while shop_fallback (until
## their first pick that was not auto-confirmed; bots never clear it) or autopilot. An
## auto-confirmed pick (PedalScanList in ERG) never reaches the receipt, whoever the rider is, and
## the rules call SiegeAutopilot.shop_picks at autopilot.shop_at_s into the break, at most
## autopilot.shop_max per break, and add them to the receipt.

## Test seam: when valid, called as shop_hook.call(state, rider, max_items) -> Array of
## normalized buy intents instead of SiegeAutopilot.shop_picks.
static var shop_hook: Callable = Callable()


## True while Autopilot shops for `r`.
static func autopiloted(r: SiegeRiderState) -> bool:
	return r.autopilot or r.shop_fallback


## Applies one normalized pick intent from `r`. An auto-confirm never counts, and a pick while the
## shop is closed is ignored. Adding an item or taking one back is a deliberate pick and ends the
## rider's shop fallback; casting a vote on someone else's item does not.
static func intent(
	state: SiegeState, r: SiegeRiderState, it: Dictionary, events: Array[Dictionary]
) -> void:
	if bool(it.get("auto", false)) or not state.shop_open():
		return
	var act := SiegeReceipt.pick(state, r, it, events)
	if not r.is_bot and act != SiegeIds.RC_NO and act != SiegeIds.RC_YES:
		r.shop_fallback = false


## Resolves one purchase (a normalized intent's item, station and pad) and returns its `buy`
## event.
static func buy(state: SiegeState, r: SiegeRiderState, it: Dictionary) -> Dictionary:
	var item := str(it.get("item", ""))
	var station := int(it.get("station", 0))
	var pad := int(it.get("pad", 0))
	var res := purchase(state, r, item, station, pad)
	var why := str(res["why"])
	return SiegeEvents.buy(r.slot, item, station, pad, why == SiegeIds.BUY_OK, why, int(res["lvl"]))


## The price of `item` now (-1 when it can't be bought at all: max level, limit reached). `lvl` is
## the level of an upgrade, mine level or pad upgrade to price (0: the next one after what stands).
static func price(
	state: SiegeState, item: String, station: int = 0, pad: int = 0, lvl: int = 0
) -> int:
	var c := state.content
	if lvl > SiegeIds.MAX_LEVEL:
		return -1
	match item:
		SiegeIds.ITEM_UPGRADE:
			if not SiegeIds.UPGRADABLE.has(station):
				return -1
			return c.station_upgrade_cost(lvl if lvl > 0 else state.station(station).level + 1)
		SiegeIds.ITEM_MINE:
			return c.mine_level_cost(lvl if lvl > 0 else state.mine_level + 1)
		SiegeIds.ITEM_SCORPION:
			return int(c.pad_def(SiegeIds.PAD_SCORPION).get("cost", 40))
		SiegeIds.ITEM_PAD_UPGRADE:
			if not SiegeIds.is_pad(pad) or not state.pad(pad).built():
				return -1
			return c.pad_upgrade_cost(lvl if lvl > 0 else state.pad(pad).level + 1)
		SiegeIds.ITEM_IRON_BANDS:
			if state.iron_bands >= int(c.num("gate.iron_bands_max", 2.0)):
				return -1
			return int(c.num("shop.iron_bands", 45.0))
		SiegeIds.ITEM_REPAIR:
			return int(c.num("shop.repair", 20.0))
		SiegeIds.ITEM_RESERVE, SiegeIds.ITEM_AQUEDUCT, SiegeIds.ITEM_CAULDRON:
			if state.perks.has(int(SiegeIds.PERK_ITEMS[item])):
				return -1
			return int(c.num("shop." + item, 80.0))
	return -1


## Everything that can refuse `item` except the buyer's gold: the shop closed, the item's own limit
## (a level, a built pad, the bands, a perk, a whole gate). {"why": BUY_*, "lvl": the level a
## purchase would reach (0 for an item without one)}.
static func limits(state: SiegeState, item: String, station: int, pad: int) -> Dictionary:
	if not state.shop_open():
		return _res(SiegeIds.BUY_CLOSED)
	var c := state.content
	var lvl := 0
	match item:
		SiegeIds.ITEM_UPGRADE:
			if not SiegeIds.UPGRADABLE.has(station):
				return _res(SiegeIds.BUY_NO_STATION)
			lvl = state.station(station).level + 1
			if lvl > SiegeIds.MAX_LEVEL:
				return _res(SiegeIds.BUY_MAX_LEVEL)
		SiegeIds.ITEM_MINE:
			lvl = state.mine_level + 1
			if lvl > SiegeIds.MAX_LEVEL:
				return _res(SiegeIds.BUY_MAX_LEVEL)
		SiegeIds.ITEM_SCORPION:
			if not SiegeIds.is_pad(pad):
				return _res(SiegeIds.BUY_NO_PAD)
			if state.pad(pad).built():
				return _res(SiegeIds.BUY_PAD_TAKEN)
		SiegeIds.ITEM_PAD_UPGRADE:
			if not SiegeIds.is_pad(pad) or not state.pad(pad).built():
				return _res(SiegeIds.BUY_NO_PAD)
			lvl = state.pad(pad).level + 1
			if lvl > SiegeIds.MAX_LEVEL:
				return _res(SiegeIds.BUY_MAX_LEVEL)
		SiegeIds.ITEM_IRON_BANDS:
			if state.iron_bands >= int(c.num("gate.iron_bands_max", 2.0)):
				return _res(SiegeIds.BUY_LIMIT)
		SiegeIds.ITEM_REPAIR:
			if state.gate_hp >= state.gate_max:
				return _res(SiegeIds.BUY_GATE_FULL)
		SiegeIds.ITEM_RESERVE, SiegeIds.ITEM_AQUEDUCT, SiegeIds.ITEM_CAULDRON:
			if state.perks.has(int(SiegeIds.PERK_ITEMS[item])):
				return _res(SiegeIds.BUY_LIMIT)
		_:
			return _res(SiegeIds.BUY_NO_STATION)
	return _res(SiegeIds.BUY_OK, lvl)


## Checks and (when allowed) performs a purchase; {"why": BUY_*, "lvl": level after it}.
static func purchase(
	state: SiegeState, r: SiegeRiderState, item: String, station: int, pad: int
) -> Dictionary:
	var res := limits(state, item, station, pad)
	if res["why"] != SiegeIds.BUY_OK:
		return res
	var lvl := int(res["lvl"])
	var c := state.content
	var cost := float(price(state, item, station, pad))
	if cost < 0.0:
		return _res(SiegeIds.BUY_MAX_LEVEL)
	if r.gold + 1e-9 < cost:
		return _res(SiegeIds.BUY_FUNDS)
	r.gold = maxf(r.gold - cost, 0.0)
	match item:
		SiegeIds.ITEM_UPGRADE:
			state.station(station).level = lvl
			if station == SiegeIds.STATION_TAR:
				state.tar.curtain_max = state.curtain_max()
		SiegeIds.ITEM_MINE:
			state.mine_level = lvl
			state.station(SiegeIds.STATION_MINE).level = lvl
		SiegeIds.ITEM_SCORPION:
			var pd := state.pad(pad)
			pd.type = SiegeIds.PAD_SCORPION
			pd.level = 0
			pd.cd_s = 0.0
			pd.built_by = r.slot
			pd.shots = 0
			pd.hits = 0
			pd.kills = 0
			pd.damage = 0.0
			lvl = 0
		SiegeIds.ITEM_PAD_UPGRADE:
			state.pad(pad).level = lvl
		SiegeIds.ITEM_IRON_BANDS:
			var add := c.num("gate.iron_bands_hp", 25.0)
			state.iron_bands += 1
			state.gate_max += add
			state.gate_hp += add
			lvl = state.iron_bands
		SiegeIds.ITEM_REPAIR:
			state.gate_hp = minf(state.gate_hp + c.num("gate.repair_hp", 20.0), state.gate_max)
			lvl = ceili(state.gate_hp)
		SiegeIds.ITEM_RESERVE, SiegeIds.ITEM_AQUEDUCT, SiegeIds.ITEM_CAULDRON:
			state.perks.append(int(SiegeIds.PERK_ITEMS[item]))
			if item == SiegeIds.ITEM_CAULDRON:
				state.tar.cauldron_max_l = state.cauldron_max()
			lvl = 1
	return _res(SiegeIds.BUY_OK, lvl)


## Autopilot's picks for riders on the shop fallback, in slot order, once the break has run
## autopilot.shop_at_s[ap_buys] seconds (4 s for the first, 9 s for the second). They go on the
## receipt like anyone's, and a bot's or Autopilot's rider votes yes like everyone who has not
## said no.
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
		SiegeReceipt.add(
			state,
			r,
			str(picks[0]["item"]),
			int(picks[0].get("station", 0)),
			int(picks[0].get("pad", 0)),
			events
		)


## Autopilot's picks for `r` (best first, normalized pick intents).
static func pick(state: SiegeState, r: SiegeRiderState, max_items: int) -> Array[Dictionary]:
	if shop_hook.is_valid():
		var out: Array[Dictionary] = []
		for x: Variant in shop_hook.call(state, r, max_items):
			out.append(x)
		return out
	return SiegeAutopilot.shop_picks(state, r, max_items)


static func _res(why: String, lvl: int = 0) -> Dictionary:
	return {"why": why, "lvl": lvl}

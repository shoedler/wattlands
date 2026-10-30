class_name SiegeShopModel
extends RefCounted
## The entries of the break shop (docs/games/siege.md 2.4 "Shop", 3 HUD): the top entry is
## Autopilot's pick for the rider (SiegeAutopilot.shop_picks), the second is "Save gold", then
## what else the rider could buy now: a gate repair, the four station upgrades, a mine level, a
## Scorpion on the first empty pad, a pad upgrade, Iron bands and the three perks. Prices come
## from the rules (SiegeShop.price). Pure: the panel draws the result in a PedalScanList.
##
## An entry is {"id": {"item", "at"}, "text", "detail", "cost", "disabled", "recommended"}; `at`
## is the station (upgrade) or the pad (scorpion, pad_upgrade). The Save entry (ITEM_SAVE) is
## never sent as an intent.

const MAX_ENTRIES := 5


## The first empty pad (0 when every pad is built).
static func empty_pad(state: SiegeState) -> int:
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		if not state.pad(n).built():
			return n
	return 0


## The built pad an upgrade is best spent on: the lowest level below 3, ties to the lower pad
## (0 when there is none).
static func upgrade_pad(state: SiegeState) -> int:
	var best := 0
	var level := 99
	for pd in state.pads:
		if pd.built() and pd.level < SiegeIds.MAX_LEVEL and pd.level < level:
			level = pd.level
			best = pd.pad
	return best


## The cost of an item now (-1 when it can't be bought).
static func cost_of(state: SiegeState, item: String, at: int) -> int:
	match item:
		SiegeIds.ITEM_UPGRADE:
			if not SiegeIds.UPGRADABLE.has(at) or state.station(at).level >= SiegeIds.MAX_LEVEL:
				return -1
			return SiegeShop.price(state, item, at, 0)
		SiegeIds.ITEM_MINE:
			if state.mine_level >= SiegeIds.MAX_LEVEL:
				return -1
		SiegeIds.ITEM_SCORPION:
			if not SiegeIds.is_pad(at) or state.pad(at).built():
				return -1
			return SiegeShop.price(state, item, 0, at)
		SiegeIds.ITEM_PAD_UPGRADE:
			if not SiegeIds.is_pad(at) or state.pad(at).level >= SiegeIds.MAX_LEVEL:
				return -1
			return SiegeShop.price(state, item, 0, at)
		SiegeIds.ITEM_REPAIR:
			if state.gate_hp >= state.gate_max:
				return -1
	return SiegeShop.price(state, item, 0, 0)


static func text_of(state: SiegeState, strings: GameStrings, item: String, at: int) -> String:
	match item:
		SiegeIds.ITEM_UPGRADE:
			var lvl := clampi(state.station(at).level + 1, 1, 3)
			return strings.t("SIEGE_ITEM_UPGRADE_%d" % lvl, [strings.t(SiegeGame.station_key(at))])
		SiegeIds.ITEM_MINE:
			return strings.t("SIEGE_ITEM_MINE_%d" % clampi(state.mine_level + 1, 1, 3))
		SiegeIds.ITEM_SCORPION:
			return "%s (%s)" % [strings.t("SIEGE_ITEM_SCORPION"), strings.t("SIEGE_PAD", [at])]
		SiegeIds.ITEM_PAD_UPGRADE:
			return strings.t(
				"SIEGE_ITEM_PAD_UPGRADE_%d" % clampi(state.pad(at).level + 1, 1, 3), [at]
			)
	return strings.t("SIEGE_ITEM_" + item.to_upper())


static func _entry(
	state: SiegeState,
	strings: GameStrings,
	rider: SiegeRiderState,
	item: String,
	at: int,
	recommended: bool
) -> Dictionary:
	var save := item == SiegeIds.ITEM_SAVE
	var cost := 0 if save else cost_of(state, item, at)
	var affordable := save or (cost >= 0 and float(cost) <= floorf(rider.gold))
	# one line per entry (the cost after the name), so six fit the shop's rect at 32 px
	var text := text_of(state, strings, item, at)
	if not save:
		text = "%s   %s" % [text, strings.t("SIEGE_SHOP_COST", [cost])]
	return {
		"id": {"item": item, "at": at},
		"text": text,
		"detail": strings.t("SIEGE_SHOP_RECOMMENDED") if recommended else "",
		"cost": cost,
		"disabled": not affordable,
		"recommended": recommended,
	}


## The entries for `rider`. `picks` are Autopilot's (normalized buy intents, best first; only
## the first is used).
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
		var at := int(p.get("station", p.get("pad", 0)))
		if SiegeIds.ITEMS.has(item) and cost_of(state, item, at) >= 0:
			out.append(_entry(state, strings, rider, item, at, true))
			seen["%s/%d" % [item, at]] = true
	out.append(_entry(state, strings, rider, SiegeIds.ITEM_SAVE, 0, false))
	var wanted: Array = [[SiegeIds.ITEM_REPAIR, 0]]
	for id in SiegeIds.UPGRADABLE:
		wanted.append([SiegeIds.ITEM_UPGRADE, id])
	(
		wanted
		. append_array(
			[
				[SiegeIds.ITEM_MINE, 0],
				[SiegeIds.ITEM_SCORPION, empty_pad(state)],
				[SiegeIds.ITEM_PAD_UPGRADE, upgrade_pad(state)],
				[SiegeIds.ITEM_IRON_BANDS, 0],
				[SiegeIds.ITEM_RESERVE, 0],
				[SiegeIds.ITEM_AQUEDUCT, 0],
				[SiegeIds.ITEM_CAULDRON, 0],
			]
		)
	)
	for w: Array in wanted:
		if out.size() >= MAX_ENTRIES:
			break
		var item: String = w[0]
		var at: int = w[1]
		if SiegeIds.PAD_ITEMS.has(item) and at < 1:
			continue
		if seen.has("%s/%d" % [item, at]) or cost_of(state, item, at) < 0:
			continue
		out.append(_entry(state, strings, rider, item, at, false))
	return out


## A string that changes when the list's content does (the panel rebuilds only then).
static func signature(list: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for e in list:
		var id: Dictionary = e["id"]
		parts.append("%s/%d/%d/%s" % [id["item"], id["at"], int(bool(e["disabled"])), e["text"]])
	return "|".join(parts)

class_name SiegeShopModel
extends RefCounted
## The entries of the break shop (docs/games/siege.md 2.4 "Shop", 3 HUD): the top entry is
## Autopilot's pick for the rider (SiegeAutopilot.shop_picks), the second is "Save gold", then
## everything else the rules sell now (anyone may buy anything): a gate repair, each station's
## next upgrade, the next mine level, a Scorpion on each empty pad, each built pad's next upgrade,
## Iron bands and the three perks. Prices come from the rules (SiegeShop.price). Pure: the panel
## pages the result through a PedalScanList (pages(): ROWS rows, the last row of a page "More" when
## there is more).
##
## An entry is {"id": {"item", "at"}, "name", "text", "detail", "cost", "disabled", "recommended"}
## ("name" is the item alone, "text" the name with its price); `at`
## is the station (upgrade) or the pad (scorpion, pad_upgrade). The Save entry (ITEM_SAVE) and
## the More entry (ITEM_MORE) are never sent as intents.

## Rows a page shows (the Quartermaster plate holds five in the BODY face).
const ROWS := 5
const ITEM_MORE := "more"


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
	var item_name := text_of(state, strings, item, at)
	var text := item_name
	if not save:
		text = "%s   %s" % [item_name, strings.t("SIEGE_SHOP_COST", [cost])]
	return {
		"id": {"item": item, "at": at},
		"name": item_name,
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
		# a normalized intent carries both keys; the pad is the one that counts for pad items
		var at := int(p.get("pad", 0)) if SiegeIds.PAD_ITEMS.has(item) else int(p.get("station", 0))
		if SiegeIds.ITEMS.has(item) and cost_of(state, item, at) >= 0:
			out.append(_entry(state, strings, rider, item, at, true))
			seen["%s/%d" % [item, at]] = true
	out.append(_entry(state, strings, rider, SiegeIds.ITEM_SAVE, 0, false))
	for w: Array in candidates(state):
		var item: String = w[0]
		var at: int = w[1]
		if SiegeIds.PAD_ITEMS.has(item) and at < 1:
			continue
		if seen.has("%s/%d" % [item, at]) or cost_of(state, item, at) < 0:
			continue
		out.append(_entry(state, strings, rider, item, at, false))
	return out


## Every [item, at] the shop could sell, in the list's order (cost_of decides what is on sale).
static func candidates(state: SiegeState) -> Array:
	var out: Array = [[SiegeIds.ITEM_REPAIR, 0]]
	for id in SiegeIds.UPGRADABLE:
		out.append([SiegeIds.ITEM_UPGRADE, id])
	out.append([SiegeIds.ITEM_MINE, 0])
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		out.append([SiegeIds.ITEM_SCORPION, n])
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		if state.pad(n).built():
			out.append([SiegeIds.ITEM_PAD_UPGRADE, n])
	for item in [
		SiegeIds.ITEM_IRON_BANDS,
		SiegeIds.ITEM_RESERVE,
		SiegeIds.ITEM_AQUEDUCT,
		SiegeIds.ITEM_CAULDRON
	]:
		out.append([item, 0])
	return out


## The entries cut into pages of ROWS rows: the first page keeps the head of the list (the pick
## and "Save gold" on top); when there is more, each page's last row is a More entry ("More
## items: 2 of 5", the page it opens) that moves on to the next page, and the last page's More
## goes back to the first.
static func pages(list: Array[Dictionary], strings: GameStrings) -> Array:
	var out: Array = []
	if list.size() <= ROWS:
		out.append(list.duplicate())
		return out
	var per := ROWS - 1
	var count := ceili(float(list.size()) / per)
	for p in count:
		var page: Array[Dictionary] = []
		page.assign(list.slice(p * per, (p + 1) * per))
		(
			page
			. append(
				{
					"id": {"item": ITEM_MORE, "at": (p + 1) % count},
					"text": strings.t("SIEGE_SHOP_MORE", [(p + 1) % count + 1, count]),
					"detail": "",
					"cost": 0,
					"disabled": false,
					"recommended": false,
				}
			)
		)
		out.append(page)
	return out


## A string that changes when the list's content does (the panel rebuilds only then).
static func signature(list: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for e in list:
		var id: Dictionary = e["id"]
		parts.append("%s/%d/%d/%s" % [id["item"], id["at"], int(bool(e["disabled"])), e["text"]])
	return "|".join(parts)

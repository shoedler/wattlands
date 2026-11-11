class_name SiegeShopModel
extends RefCounted
## The entries of the break shop (docs/games/siege.md 2.4 "Shop", 3 HUD): the top entry is
## Autopilot's pick for the rider (SiegeAutopilot.shop_picks), the second is "Save gold", then
## everything else the rules sell now (anyone may pick anything): a gate repair, each station's
## next upgrade, the next mine level, a Scorpion on each empty pad, each built pad's next upgrade,
## Iron bands and the three perks. While level N of an upgrade, mine level or pad upgrade is on the
## receipt its own row follows, and a row for level N+1 after it (up to level 3). Prices come from
## the rules (SiegeShop.price). Pure: the panel pages the result through a PedalScanList (pages():
## ROWS rows, the last row of a page "More" when there is more).
##
## An entry is {"id": {"item", "at", "lvl"}, "name", "text", "detail", "cost", "disabled", "recommended",
## "added", "mine", "by", "my_no"} ("name" is the item alone, "text" the name with its price); `at`
## is the station (upgrade) or the pad (scorpion, pad_upgrade). "added": the item is on the shared
## receipt, "mine": the rider put it there (picking it takes it back), "by": the picker's name,
## "my_no": the rider has voted no on it. An item on the receipt stays pickable whatever the gold
## (a pick votes or takes back); any other needs the gold the rider has free
## (SiegeState.spendable). The Save entry (ITEM_SAVE) and the More entry (ITEM_MORE) are never sent
## as intents.

## Rows a page shows (the Quartermaster plate holds five in the BODY face).
const ROWS := 5
const ITEM_MORE := "more"


## The cost of an item now (-1 when it can't be bought).
static func cost_of(state: SiegeState, item: String, at: int, lvl: int = 0) -> int:
	if lvl > 0 and SiegeIds.LEVELED_ITEMS.has(item):
		if lvl > SiegeIds.MAX_LEVEL or lvl <= state.level_of(item, at):
			return -1
		match item:
			SiegeIds.ITEM_UPGRADE:
				if not SiegeIds.UPGRADABLE.has(at):
					return -1
				return SiegeShop.price(state, item, at, 0, lvl)
			SiegeIds.ITEM_PAD_UPGRADE:
				if not SiegeIds.is_pad(at) or not state.pad(at).built():
					return -1
				return SiegeShop.price(state, item, 0, at, lvl)
		return SiegeShop.price(state, item, 0, 0, lvl)
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


## The row's name; `lvl` is the level of a leveled item (0: the next one after what stands).
static func text_of(
	state: SiegeState, strings: GameStrings, item: String, at: int, lvl: int = 0
) -> String:
	match item:
		SiegeIds.ITEM_UPGRADE:
			var up := clampi(lvl if lvl > 0 else state.station(at).level + 1, 1, 3)
			return strings.t("SIEGE_ITEM_UPGRADE_%d" % up, [strings.t(SiegeGame.station_key(at))])
		SiegeIds.ITEM_MINE:
			return strings.t(
				"SIEGE_ITEM_MINE_%d" % clampi(lvl if lvl > 0 else state.mine_level + 1, 1, 3)
			)
		SiegeIds.ITEM_SCORPION:
			return "%s (%s)" % [strings.t("SIEGE_ITEM_SCORPION"), strings.t("SIEGE_PAD", [at])]
		SiegeIds.ITEM_PAD_UPGRADE:
			return strings.t(
				(
					"SIEGE_ITEM_PAD_UPGRADE_%d"
					% clampi(lvl if lvl > 0 else state.pad(at).level + 1, 1, 3)
				),
				[at]
			)
	return strings.t("SIEGE_ITEM_" + item.to_upper())


static func _entry(
	state: SiegeState,
	strings: GameStrings,
	rider: SiegeRiderState,
	item: String,
	at: int,
	lvl: int,
	recommended: bool,
	names: Dictionary
) -> Dictionary:
	var save := item == SiegeIds.ITEM_SAVE
	var cost := 0 if save else cost_of(state, item, at, lvl)
	var line := null if save else state.receipt_line(item, at, lvl)
	var added := line != null
	var affordable := save or added or (cost >= 0 and float(cost) <= floorf(state.spendable(rider)))
	var item_name := text_of(state, strings, item, at, lvl)
	var text := item_name
	if not save:
		text = "%s   %s" % [item_name, strings.t("SIEGE_SHOP_COST", [cost])]
	return {
		"id": {"item": item, "at": at, "lvl": lvl},
		"name": item_name,
		"text": text,
		"detail": strings.t("SIEGE_SHOP_RECOMMENDED") if recommended else "",
		"cost": cost,
		"disabled": not affordable,
		"recommended": recommended,
		"added": added,
		"mine": added and line.slot == rider.slot,
		"by": str(names.get(line.slot, "Rider %d" % (line.slot + 1))) if added else "",
		"my_no": added and line.no.has(rider.slot),
	}


## The entries for `rider`. `picks` are Autopilot's (normalized pick intents, best first; only
## the first is used). `names` is slot -> the rider's name for the "by" of an added item.
static func entries(
	state: SiegeState,
	rider: SiegeRiderState,
	strings: GameStrings,
	picks: Array[Dictionary],
	names: Dictionary = {}
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
		var lvl := state.level_of(item, at) + 1 if SiegeIds.LEVELED_ITEMS.has(item) else 0
		if SiegeIds.ITEMS.has(item) and cost_of(state, item, at, lvl) >= 0:
			out.append(_entry(state, strings, rider, item, at, lvl, true, names))
			seen[SiegeReceiptLine.key_of(item, at, lvl)] = true
	out.append(_entry(state, strings, rider, SiegeIds.ITEM_SAVE, 0, 0, false, names))
	for w: Array in candidates(state):
		var item: String = w[0]
		var at: int = w[1]
		var lvl: int = w[2]
		if SiegeIds.PAD_ITEMS.has(item) and at < 1:
			continue
		if seen.has(SiegeReceiptLine.key_of(item, at, lvl)) or cost_of(state, item, at, lvl) < 0:
			continue
		out.append(_entry(state, strings, rider, item, at, lvl, false, names))
	return out


## Every [item, at, lvl] the shop could sell, in the list's order (cost_of decides what is on sale;
## lvl is 0 for an item without levels). A leveled item lists each level from the next one to the
## one after the last on the receipt.
static func candidates(state: SiegeState) -> Array:
	var out: Array = [[SiegeIds.ITEM_REPAIR, 0, 0]]
	for id in SiegeIds.UPGRADABLE:
		out.append_array(_levels(state, SiegeIds.ITEM_UPGRADE, id))
	out.append_array(_levels(state, SiegeIds.ITEM_MINE, 0))
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		out.append([SiegeIds.ITEM_SCORPION, n, 0])
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		if state.pad(n).built():
			out.append_array(_levels(state, SiegeIds.ITEM_PAD_UPGRADE, n))
	for item in [
		SiegeIds.ITEM_IRON_BANDS,
		SiegeIds.ITEM_RESERVE,
		SiegeIds.ITEM_AQUEDUCT,
		SiegeIds.ITEM_CAULDRON
	]:
		out.append([item, 0, 0])
	return out


static func _levels(state: SiegeState, item: String, at: int) -> Array:
	var out: Array = []
	var last := mini(state.next_level(item, at), SiegeIds.MAX_LEVEL)
	for lvl in range(state.level_of(item, at) + 1, last + 1):
		out.append([item, at, lvl])
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
					"added": false,
					"mine": false,
					"by": "",
					"my_no": false,
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
		parts.append(
			(
				"%s/%d/%d/%d/%s/%d/%d/%s"
				% [
					id["item"],
					id["at"],
					id.get("lvl", 0),
					int(bool(e["disabled"])),
					e["text"],
					int(bool(e.get("added", false))),
					int(bool(e.get("my_no", false))),
					e.get("by", "")
				]
			)
		)
	return "|".join(parts)

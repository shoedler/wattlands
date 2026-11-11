class_name SiegeReceipt
extends RefCounted
## The shared receipt (brief 2.4 "Shop"). Pure. In a break a pick puts an item on a receipt every
## rider sees and holds the picker's gold for it (SiegeState.spendable); nothing is spent until the
## break ends, when buy_all() buys what is left in the order it was added (the order the host
## resolved the picks in: slot order within a tick, so the tie-break is deterministic).
##
##   pick(): an item not on the receipt goes on it; picking your own takes it back (the gold is
##     free again); picking someone else's votes no, and picking it again returns your vote to yes.
##   Votes: every rider of the session votes, in slot order, the picker counting yes and a rider
##     who has not cast a no counting yes (a rider who dropped or went AFK included). The moment a
##     vote cast makes "no" outnumber "yes" or tie them, the line leaves the receipt and its gold is
##     the picker's again. Nothing is re-counted when a rider drops, and only a vote cast rejects.
##   Levels: an upgrade, a mine level or a pad upgrade comes one line per level. Level N+1 can be
##     picked while level N is on the receipt, with its own cost and its own vote; when level N
##     leaves the receipt (taken back or voted off), the lines above it leave with it and their gold
##     is free. They are added in order, so level N is bought before N+1.
##   buy_all(): the end of the break.
## One line per item and level (item + station or pad + level), so nothing is on the receipt twice
## or past its limit, and a pick never takes more than the picker's free gold, so gold never goes
## negative.


## Applies one normalized pick of rider `r` in an open shop and returns what it did (RC_ADD,
## RC_TAKE, RC_NO or RC_YES; 0 when it did nothing, a refusal included). A refused item answers the
## picker with a `buy` event that says why.
static func pick(
	state: SiegeState, r: SiegeRiderState, it: Dictionary, events: Array[Dictionary]
) -> int:
	if not state.shop_open():
		return 0
	var item := str(it.get("item", ""))
	var at := SiegeIntents.at_of(it)
	var lvl := int(it.get("lvl", 0))
	var line := state.receipt_line(item, at, lvl)
	var act := 0
	if line == null:
		# a level goes on top of what is there: a stale or skipped level is ignored
		if lvl == 0 or lvl == state.next_level(item, at):
			if add(state, r, item, int(it.get("station", 0)), int(it.get("pad", 0)), events):
				act = SiegeIds.RC_ADD
	elif line.slot == r.slot:
		_remove(state, line, SiegeIds.RC_TAKE, events)
		act = SiegeIds.RC_TAKE
	else:
		act = _vote(state, r, line, events)
	return act


## Puts `item` on the receipt for `r` (at the next level for an upgrade, mine level or pad
## upgrade): false (and a refusal `buy` event, or nothing for an item already on the receipt) when
## it can't go on.
static func add(
	state: SiegeState,
	r: SiegeRiderState,
	item: String,
	station: int,
	pad: int,
	events: Array[Dictionary]
) -> bool:
	var at := SiegeIntents.at_of({"item": item, "station": station, "pad": pad})
	var lvl := state.next_level(item, at)
	if not state.shop_open() or state.receipt_line(item, at, lvl) != null:
		return false
	var res := SiegeShop.limits(state, item, station, pad)
	var why := str(res["why"])
	var cost := SiegeShop.price(state, item, station, pad, lvl)
	if why == SiegeIds.BUY_OK and cost < 0:
		why = SiegeIds.BUY_MAX_LEVEL
	if why == SiegeIds.BUY_OK and state.spendable(r) + 1e-9 < float(cost):
		why = SiegeIds.BUY_FUNDS
	if why != SiegeIds.BUY_OK:
		events.append(SiegeEvents.buy(r.slot, item, station, pad, false, why, 0))
		return false
	var line := SiegeReceiptLine.new()
	line.item = item
	line.at = at
	line.lvl = lvl
	line.cost = cost
	line.slot = r.slot
	state.receipt.append(line)
	events.append(_event(r.slot, line, SiegeIds.RC_ADD, state))
	return true


## Rider `r` votes on someone else's line: their vote flips, no to yes or yes to no. Returns RC_NO
## or RC_YES, or 0 for a rider who is not a voter. A no that makes the vote reject the line takes
## it off.
static func _vote(
	state: SiegeState, r: SiegeRiderState, line: SiegeReceiptLine, events: Array[Dictionary]
) -> int:
	var tv := state.vote_on(line)
	if not tv.voters.has(r.slot):
		return 0
	var yes := tv.toggle(r.slot)
	line.no.assign(tv.no_voters())
	var act := SiegeIds.RC_YES if yes else SiegeIds.RC_NO
	events.append(_event(r.slot, line, act, state, tv))
	if tv.rejected():
		_remove(state, line, SiegeIds.RC_REJECT, events, tv)
	return act


## Takes `line` off the receipt with `act` (RC_TAKE or RC_REJECT) and, for a level, every line
## above it of the same item there (RC_DROP): their gold is free again.
static func _remove(
	state: SiegeState,
	line: SiegeReceiptLine,
	act: int,
	events: Array[Dictionary],
	tv: TeamVote = null
) -> void:
	var above: Array[SiegeReceiptLine] = []
	for other in state.receipt:
		if (
			line.lvl > 0
			and other.item == line.item
			and other.at == line.at
			and other.lvl > line.lvl
		):
			above.append(other)
	state.receipt.erase(line)
	events.append(_event(line.slot, line, act, state, tv))
	for other in above:
		state.receipt.erase(other)
		events.append(_event(other.slot, other, SiegeIds.RC_DROP, state))


## The end of a break: buys what is left on the receipt in the order it was added, each from its
## picker's gold (a rider who dropped included: their held gold is spent as usual), and empties the
## receipt. Every purchase answers with a `buy` event, then one `receipt` event sums it up.
static func buy_all(state: SiegeState, events: Array[Dictionary]) -> void:
	var lines := state.receipt.duplicate()
	state.receipt.clear()
	var bought := 0
	var spent := 0
	for line: SiegeReceiptLine in lines:
		var r := state.rider_at(line.slot)
		if r == null:
			continue
		var station := line.at if SiegeIds.STATION_ITEMS.has(line.item) else 0
		var pad := line.at if SiegeIds.PAD_ITEMS.has(line.item) else 0
		var ev := SiegeShop.buy(state, r, {"item": line.item, "station": station, "pad": pad})
		events.append(ev)
		if int(ev["ok"]) != 0:
			bought += 1
			spent += line.cost
	if bought > 0:
		events.append(
			SiegeEvents.receipt(0, "", 0, 0, SiegeIds.RC_BOUGHT, 0, bought, 0, 0, 0, spent)
		)


## The `receipt` event for `line`: the actor's slot, the item, the act, and the vote after it.
## `who` carries the slots that care (the picker and every rider who voted no) as a bit mask.
static func _event(
	slot: int, line: SiegeReceiptLine, act: int, state: SiegeState, tv: TeamVote = null
) -> Dictionary:
	var vote := tv if tv != null else state.vote_on(line)
	var station := line.at if SiegeIds.STATION_ITEMS.has(line.item) else 0
	var pad := line.at if SiegeIds.PAD_ITEMS.has(line.item) else 0
	var who := 1 << line.slot
	for no in line.no:
		who |= 1 << no
	return SiegeEvents.receipt(
		slot,
		line.item,
		station,
		pad,
		act,
		line.slot,
		vote.yes_count(),
		vote.no_count(),
		line.lvl,
		who,
		line.cost
	)

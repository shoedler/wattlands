class_name SiegeReceipt
extends RefCounted
## The shared receipt (brief 2.4 "Shop"). Pure. In a break a pick puts an item on a receipt every
## rider sees and holds the picker's gold for it (SiegeState.spendable); nothing is spent until the
## break ends, when buy_all() buys what is left in the order it was added (the order the host
## resolved the picks in: slot order within a tick, so the tie-break is deterministic).
##
##   pick(): an item not on the receipt goes on it; picking your own takes it back (the gold is
##     free again); picking someone else's votes no, and picking it again returns your vote to yes.
##   settle(): the TeamVote of every line over the connected riders (the picker counts yes, a bot
##     or Autopilot's rider never says no): the moment "no" outnumbers "yes" or ties them, the line
##     leaves the receipt and its gold is the picker's again. A line whose picker has left the
##     session leaves with them (ADR "receipt: a rider who leaves").
##   buy_all(): the end of the break.
## One line per item (item + station or pad), so an item is never on the receipt twice and a limit
## (a level, a perk, the bands) is never passed. A pick never takes more than the picker's free
## gold, so gold never goes negative.


## Applies one normalized pick of rider `r` in an open shop. An unknown or refused item answers
## the picker with a `buy` event that says why.
static func pick(
	state: SiegeState, r: SiegeRiderState, it: Dictionary, events: Array[Dictionary]
) -> void:
	if not state.shop_open():
		return
	var item := str(it.get("item", ""))
	var at := SiegeIntents.at_of(it)
	var line := state.receipt_line(item, at)
	if line == null:
		add(state, r, item, int(it.get("station", 0)), int(it.get("pad", 0)), events)
	elif line.slot == r.slot:
		state.receipt.erase(line)
		events.append(_event(r.slot, line, SiegeIds.RC_TAKE, state))
	else:
		_vote(state, r, line, events)
	settle(state, events)


## Puts `item` on the receipt for `r`: false (and a refusal `buy` event, or nothing for an item
## already on the receipt) when it can't go on.
static func add(
	state: SiegeState,
	r: SiegeRiderState,
	item: String,
	station: int,
	pad: int,
	events: Array[Dictionary]
) -> bool:
	var at := SiegeIntents.at_of({"item": item, "station": station, "pad": pad})
	if not state.shop_open() or state.receipt_line(item, at) != null:
		return false
	if not state.voter_slots().has(r.slot):
		return false
	var res := SiegeShop.limits(state, item, station, pad)
	var why := str(res["why"])
	var cost := SiegeShop.price(state, item, station, pad)
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
	line.cost = cost
	line.slot = r.slot
	state.receipt.append(line)
	events.append(_event(r.slot, line, SiegeIds.RC_ADD, state))
	return true


## Rider `r` votes on someone else's line: their vote flips, no to yes or yes to no. A rider who
## is not a voter (disconnected) changes nothing.
static func _vote(
	state: SiegeState, r: SiegeRiderState, line: SiegeReceiptLine, events: Array[Dictionary]
) -> void:
	var tv := state.vote_on(line)
	if not tv.voters.has(r.slot):
		return
	var yes := tv.toggle(r.slot)
	line.no.assign(tv.no_voters())
	events.append(_event(r.slot, line, SiegeIds.RC_YES if yes else SiegeIds.RC_NO, state))


## Re-reads every vote against the riders who are connected now: a picker who left takes their
## lines with them, a voter who left drops their no, and a line the vote rejects leaves the
## receipt. Runs after every change to the receipt and every tick of an open shop.
static func settle(state: SiegeState, events: Array[Dictionary]) -> void:
	var i := 0
	while i < state.receipt.size():
		var line := state.receipt[i]
		var tv := state.vote_on(line)
		if not tv.voters.has(line.slot):
			state.receipt.remove_at(i)
			events.append(_event(line.slot, line, SiegeIds.RC_DROP, state, tv))
			continue
		line.no.assign(tv.no_voters())
		if tv.rejected():
			state.receipt.remove_at(i)
			events.append(_event(line.slot, line, SiegeIds.RC_REJECT, state, tv))
			continue
		i += 1


## The end of a break: buys what is left on the receipt in the order it was added, each from its
## picker's gold, and empties the receipt. Every purchase answers with a `buy` event.
static func buy_all(state: SiegeState, events: Array[Dictionary]) -> void:
	settle(state, events)
	var lines := state.receipt.duplicate()
	state.receipt.clear()
	for line: SiegeReceiptLine in lines:
		var r := state.rider_at(line.slot)
		if r == null:
			continue
		var station := line.at if SiegeIds.STATION_ITEMS.has(line.item) else 0
		var pad := line.at if SiegeIds.PAD_ITEMS.has(line.item) else 0
		events.append(SiegeShop.buy(state, r, {"item": line.item, "station": station, "pad": pad}))


## The `receipt` event for `line`: the actor's slot, the item, the act, and the vote after it.
static func _event(
	slot: int, line: SiegeReceiptLine, act: int, state: SiegeState, tv: TeamVote = null
) -> Dictionary:
	var vote := tv if tv != null else state.vote_on(line)
	var station := line.at if SiegeIds.STATION_ITEMS.has(line.item) else 0
	var pad := line.at if SiegeIds.PAD_ITEMS.has(line.item) else 0
	return SiegeEvents.receipt(
		slot, line.item, station, pad, act, line.slot, vote.yes_count(), vote.no_count()
	)

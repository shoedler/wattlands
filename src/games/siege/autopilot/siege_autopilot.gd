class_name SiegeAutopilot
extends RefCounted
## Autopilot's routing and shop decisions (brief 2.5). Pure, static and deterministic (reads only
## the state; no RNG). Never changes effort targets and never triggers Overdrive: it only returns
## stations and normalized buy intents.
##
## Who calls it (ADR "Autopilot runs inside the host rules"): SiegeRules for every rider whose
## route_fallback / shop_fallback is true (bots, Autopilot-on humans and humans who haven't routed
## or bought by hand yet), in slot order: route_choice() once a second, shop_picks() in a break at
## balance.json autopilot.shop_at_s (at most 2 buys per break). GameModule.autopilot_intents()
## returns []. The HUD's shop panel may call shop_picks() on clients for its top entry, from the
## snapshot-rebuilt state.
##
## Station scores (scores(), brief 2.5):
##   weapon     the sum over live enemies that will be inside its range band at some point of
##              the next look_ahead_s (10) seconds at their current speed (sampled at 0, 5 and
##              10 s) of HP x autopilot.weights[station][type];
##   tar works  when a ram or siege tower is within tar_engine_m (60) of the gate, or any enemy
##              within tar_any_m (40), and the cauldrons hold >= tar_min_frac (2/3): tar_scale x
##              the gate threat of those enemies (gate_hp per body; an engine's threat); 0 while
##              boarders are on the wall;
##   mine       autopilot.mine_score, a small constant that wins when nothing is in reach.
## route_choice switches at most once per switch_min_s (8 s) and only for a score at least
## switch_margin (25%) above the current station's (and never between two equal scores, so idle
## riders the mine's cap keeps off it don't wander between empty stations).

const SAMPLES := 3


## The five stations' scores now (index = station id).
static func scores(state: SiegeState) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	if state == null or state.content == null or state.path == null:
		return out
	var c := state.content
	out[SiegeIds.STATION_MINE] = c.num("autopilot.mine_score", 40.0)
	var weights: Dictionary = (c.balance.get("autopilot", {}) as Dictionary).get("weights", {})
	var ahead := c.num("autopilot.look_ahead_s", 10.0)
	for id in SiegeIds.WEAPONS:
		var w: Dictionary = weights.get(SiegeIds.STATION_NAMES[id], {})
		var sum := 0.0
		for e in state.enemies:
			if not e.alive():
				continue
			var wt := float(w.get(SiegeIds.ENEMY_NAMES[e.type], 1.0))
			if wt <= 0.0:
				continue
			for i in SAMPLES:
				var t := ahead * float(i) / float(SAMPLES - 1)
				var p := e.pos if i == 0 else SiegeAim.aim_point(state.path, e, t, 0.0)
				if state.in_band(id, p):
					sum += e.hp * wt
					break
		out[id] = sum
	out[SiegeIds.STATION_TAR] = tar_score(state)
	return out


## The tar works' score (see the class notes).
static func tar_score(state: SiegeState) -> float:
	var c := state.content
	var tar := state.tar
	if tar.boarded or tar.cauldron_l < c.num("autopilot.tar_min_frac", 0.667) * tar.cauldron_max_l:
		return 0.0
	var engine_m := c.num("autopilot.tar_engine_m", 60.0)
	var any_m := c.num("autopilot.tar_any_m", 40.0)
	var triggered := false
	var threat := 0.0
	for e in state.enemies:
		if not e.alive():
			continue
		var d := state.path.dist_to_gate(e.prog_m)
		if SiegeIds.is_engine(e.type):
			if d <= engine_m:
				triggered = true
				threat += float(c.enemy_def(e.type).get("threat", 20.0))
		elif d <= any_m:
			triggered = true
			threat += float(c.enemy_def(e.type).get("gate_hp", 2.0))
	return c.num("autopilot.tar_scale", 20.0) * threat if triggered else 0.0


## The station `rider` should route to now, or -1 to keep the current one. `sc`: scores() (pass
## it to share one computation among the riders of a tick; empty: computed here).
static func route_choice(
	state: SiegeState, rider: SiegeRiderState, sc: PackedFloat32Array = PackedFloat32Array()
) -> int:
	if state == null or rider == null or state.content == null:
		return -1
	if not state.in_wave() or rider.afk or not rider.connected:
		return -1
	if sc.size() != SiegeIds.STATION_COUNT:
		sc = scores(state)
	var want := best_station(state, rider, sc)
	if want < 0 or want == rider.target:
		return -1
	if state.t - rider.routed_t < state.content.num("autopilot.switch_min_s", 8.0):
		return -1
	var margin := state.content.num("autopilot.switch_margin", 0.25)
	if sc[want] <= sc[rider.target] + 1e-6 or sc[want] < sc[rider.target] * (1.0 + margin) - 1e-6:
		return -1
	return want


## The highest-scoring station `rider` may route to (within the caps; ties to the lower id), or
## -1.
static func best_station(state: SiegeState, rider: SiegeRiderState, sc: PackedFloat32Array) -> int:
	var best := -1
	for id in SiegeIds.STATION_COUNT:
		if not SiegeRouting.can_route_to(state, rider, id):
			continue
		if best < 0 or sc[id] > sc[best] + 1e-6:
			best = id
	return best


## The "hot" station for the down control (brief 2.4): Autopilot's pick for `rider` now (no
## switch limit), or -1 when it is the current one or none has room.
static func hot_target(state: SiegeState, rider: SiegeRiderState) -> int:
	if state == null or rider == null or state.content == null:
		return -1
	var best := best_station(state, rider, scores(state))
	return best if best != rider.target else -1


## Autopilot's shop picks for `rider` in this break, best first, as normalized pick intents
## (SiegeIntents.normalize form, "auto": true), at most `max_items`. Order (brief 2.5): repair
## below 50%; an upgrade for the station that did the most damage last wave; a Scorpion on the
## first empty pad; a mine level; Iron bands; perks (Reserve flywheel, Aqueduct drive, Spare
## cauldron); save (an empty list). A pick must be affordable with what the rider has free (their
## gold less what they hold on the receipt) after the earlier picks. An upgrade or a mine level goes
## on top of the levels already on the receipt (anyone's), a Scorpion, Iron bands, repair or perk
## already on it is not picked again: an unaffordable, impossible or taken step falls through to
## the next one. `blind` ignores the receipt (all the rider's gold, nothing taken): the shop's
## list keeps its order while items come and go.
static func shop_picks(
	state: SiegeState, rider: SiegeRiderState, max_items: int = 2, blind: bool = false
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or rider == null or state.content == null or max_items <= 0:
		return out
	if not state.shop_open():
		return out
	var plan := ShopPlan.new(state, rider.gold if blind else state.spendable(rider), blind)
	for _i in max_items:
		var pick := plan.next_pick()
		if pick.is_empty():
			break
		out.append(SiegeIntents.normalize(SiegeIntents.pick(pick["item"], int(pick["at"]), true)))
	return out


## The weapon that did the most damage in the current or last wave (ties to the lower id; the
## ballista when none did any).
static func top_weapon(state: SiegeState) -> int:
	var best := SiegeIds.STATION_BALLISTA
	for id in SiegeIds.WEAPONS:
		if state.station(id).damage_wave > state.station(best).damage_wave + 1e-6:
			best = id
	return best


## A throwaway copy of what a rider could buy, so the second pick sees the first.
class ShopPlan:
	extends RefCounted
	var state: SiegeState
	var funds: float = 0.0
	var gate_hp: float = 0.0
	var gate_max: float = 0.0
	var mine_level: int = 0
	var bands: int = 0
	var perks: Array[int] = []
	var levels: Array[int] = []
	var pads: Array[int] = []
	## The receipt's "<item>/<at>" keys: what is already picked this break.
	var taken: Array[String] = []

	func _init(p_state: SiegeState, p_funds: float, blind: bool = false) -> void:
		state = p_state
		funds = floorf(p_funds)
		# The snapshot carries the gate HP rounded up, so a client decides on the same number.
		gate_hp = ceilf(state.gate_hp)
		gate_max = state.gate_max
		mine_level = state.mine_level
		bands = state.iron_bands
		perks = state.perks.duplicate()
		for st in state.stations:
			levels.append(st.level)
		for pd in state.pads:
			pads.append(pd.type)
		if not blind:
			# the levels on the receipt count as bought: the next pick goes on top of them
			for line in state.receipt:
				match line.item:
					SiegeIds.ITEM_UPGRADE:
						levels[line.at] += 1
					SiegeIds.ITEM_MINE:
						mine_level += 1
					_:
						taken.append(line.key())

	func _free(item: String, at: int) -> bool:
		return not taken.has(SiegeReceiptLine.key_of(item, at))

	## The next pick as {"item", "at", "cost"} (applied to this copy), or {} to save.
	func next_pick() -> Dictionary:
		for step: Callable in [_repair, _upgrade, _scorpion, _mine, _iron_bands, _perk]:
			var pick: Dictionary = step.call()
			if not pick.is_empty():
				taken.append(SiegeReceiptLine.key_of(str(pick["item"]), int(pick["at"])))
				return pick
		return {}

	func _spend(cost: float) -> bool:
		if cost < 0.0 or cost > funds + 1e-9:
			return false
		funds -= cost
		return true

	func _repair() -> Dictionary:
		var c := state.content
		var below := c.num("autopilot.repair_below_frac", 0.5)
		if gate_hp >= gate_max or gate_hp / maxf(gate_max, 1.0) >= below:
			return {}
		if not _free(SiegeIds.ITEM_REPAIR, 0):
			return {}
		var cost := c.num("shop.repair", 20.0)
		if not _spend(cost):
			return {}
		gate_hp = minf(gate_hp + c.num("gate.repair_hp", 20.0), gate_max)
		return {"item": SiegeIds.ITEM_REPAIR, "at": 0, "cost": cost}

	func _upgrade() -> Dictionary:
		var id := SiegeAutopilot.top_weapon(state)
		if levels[id] >= SiegeIds.MAX_LEVEL:
			return {}
		var cost := float(state.content.station_upgrade_cost(levels[id] + 1))
		if not _spend(cost):
			return {}
		levels[id] += 1
		return {"item": SiegeIds.ITEM_UPGRADE, "at": id, "cost": cost}

	func _scorpion() -> Dictionary:
		var free := pads.find(SiegeIds.PAD_NONE)
		while free >= 0 and not _free(SiegeIds.ITEM_SCORPION, free + 1):
			free = pads.find(SiegeIds.PAD_NONE, free + 1)
		if free < 0:
			return {}
		var cost := float(state.content.pad_def(SiegeIds.PAD_SCORPION).get("cost", 40))
		if not _spend(cost):
			return {}
		pads[free] = SiegeIds.PAD_SCORPION
		return {"item": SiegeIds.ITEM_SCORPION, "at": free + 1, "cost": cost}

	func _mine() -> Dictionary:
		var cost := float(state.content.mine_level_cost(mine_level + 1))
		if mine_level >= SiegeIds.MAX_LEVEL or not _spend(cost):
			return {}
		mine_level += 1
		return {"item": SiegeIds.ITEM_MINE, "at": 0, "cost": cost}

	func _iron_bands() -> Dictionary:
		var c := state.content
		var cost := c.num("shop.iron_bands", 45.0)
		if (
			bands >= int(c.num("gate.iron_bands_max", 2.0))
			or not _free(SiegeIds.ITEM_IRON_BANDS, 0)
		):
			return {}
		if not _spend(cost):
			return {}
		bands += 1
		return {"item": SiegeIds.ITEM_IRON_BANDS, "at": 0, "cost": cost}

	func _perk() -> Dictionary:
		for item: String in [SiegeIds.ITEM_RESERVE, SiegeIds.ITEM_AQUEDUCT, SiegeIds.ITEM_CAULDRON]:
			var code := int(SiegeIds.PERK_ITEMS[item])
			if perks.has(code) or not _free(item, 0):
				continue
			var cost := state.content.num("shop." + item, 80.0)
			if not _spend(cost):
				return {}
			perks.append(code)
			return {"item": item, "at": 0, "cost": cost}
		return {}

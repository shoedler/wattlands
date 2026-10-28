class_name TankHullRules
extends RefCounted
## The hull's HP, the berm, the breakdown and its repair (brief 2.4 Drive, Dig in, Enemies;
## owner: rules). Hull 100 HP (+20 per checkpoint, TankSegments). At 0 HP the tank breaks down: no
## movement or fire and damage is ignored, while the crew's P_eff pays 5 kJ toward the repair
## (12-30 s); then it runs again on 40 HP.


## The driver's station: the diesel (the Drive seat; null when the tank has none). v3: an empty
## Drive seat has no P_eff, so the tank stops.
static func driver(state: TankState) -> TankDieselState:
	return state.station(TankIds.ENGINE_DIESEL) as TankDieselState


## A round of `dmg` lands on the tank (an enemy or Behemoth shell). The berm absorbs first. During
## a breakdown the round still raises a `hit` event with 0 damage. Returns the HP lost.
static func hit(
	state: TankState, dmg: float, shell: int, x: float, events: Array[Dictionary]
) -> float:
	var hull := state.hull
	if hull.breakdown:
		events.append(TankEvents.hit(TankEvents.ON_TANK, 0, 0.0, shell, 0.0, x))
		return 0.0
	if state.content != null:
		# v3 solo balance: enemies.json crew_damage_scale (enemy HP stays the same for every crew).
		dmg *= state.content.crew_damage_scale(state.crew)
	var absorbed := minf(hull.berm_hp, dmg)
	hull.berm_hp -= absorbed
	if absorbed > 0.0:
		state.score.berm_absorbed += absorbed
		var d := driver(state)
		var r := state.rider_at(d.slot) if d != null and d.slot >= 0 else null
		if r != null:
			r.berm_absorbed += absorbed
	var lost := dmg - absorbed
	hull.hp -= lost
	events.append(TankEvents.hit(TankEvents.ON_TANK, 0, dmg, shell, absorbed, x))
	_check_breakdown(state, events)
	return lost


static func _check_breakdown(state: TankState, events: Array[Dictionary]) -> void:
	var hull := state.hull
	if hull.hp > 0.0 or hull.breakdown:
		return
	hull.hp = 0.0
	hull.breakdown = true
	hull.repair_j = 0.0
	hull.speed_mps = 0.0
	state.score.breakdowns += 1
	events.append(TankEvents.breakdown())


## Pays the repair (v3: the crew works it, brief 3.2): the mean P_eff of the manned seats (the
## reserve's 60 W included; nothing when everyone is AFK), so a repair takes as long as v2's
## driver-paid one whatever seats are manned; back to repair_hp HP when repair_j reaches repair_j.
static func repair(state: TankState, dt: float, events: Array[Dictionary]) -> void:
	var hull := state.hull
	if not hull.breakdown or state.all_afk:
		return
	var sum := 0.0
	var n := 0
	for st in state.stations:
		if not st.is_empty():
			sum += st.p_eff_w
			n += 1
	if n == 0:
		return
	var c := state.content
	hull.repair_j += sum / float(n) * dt
	if hull.repair_j >= c.num("tanks", "hull.repair_j", 5000.0):
		hull.breakdown = false
		hull.repair_j = 0.0
		hull.hp = minf(c.num("tanks", "hull.repair_hp", 40.0), hull.hp_max)
		events.append(TankEvents.repaired(hull.hp))


## Dig in (a gun line, v3: the Drive seat in SIM flat): the driver's P_eff in band raises the mud
## berm by 1 HP per 250 J up to 40 HP; a rescue or an empty Drive seat stops the berm growing.
static func dig(state: TankState, inputs: TankInputs, dt: float) -> void:
	var hull := state.hull
	if state.seg.seg != TankIds.SEG_GUN_LINE or hull.breakdown or state.all_afk:
		return
	var d := driver(state)
	if d == null or d.slot < 0 or not d.in_band:
		return
	var ri := inputs.rider(d.peer)
	if TankStations.in_rescue(ri):
		return
	var c := state.content
	var max_hp := c.num("tanks", "berm.max_hp", 40.0)
	if hull.berm_hp >= max_hp:
		hull.berm_j = 0.0
		return
	hull.berm_j += d.p_eff_w * dt
	var per := c.num("tanks", "berm.j_per_hp", 250.0)
	while hull.berm_j >= per and hull.berm_hp < max_hp:
		hull.berm_j -= per
		hull.berm_hp += 1.0

class_name SiegeCombat
extends RefCounted
## Roads, enemies, towers, Caltrop zones, the spawner, rushes, the gate and the 150-enemy cap
## (brief 2.4). Pure and deterministic like SiegeRules, which calls step() once per tick after
## routing and the generator.
##
## One tick, in order:
##   1. shots older than 0.1 s drop; the Breach clock runs (at its end the gate is restored)
##   2. SiegeSpawner: warm-up toast, road rotation, groups, ram push, rush
##   3. movement: zones slow (no stacking: the strongest wins) and amplify; walkers advance, reach
##      the gate (leak: damage, then gone) or, during a Breach, vanish without damage; a ram
##      stops at the gate and batters 3 HP/s (paused in a Breach); retreating enemies walk back
##      for 3 s and vanish without bounty or damage
##   4. SiegeTowers: output m, fire, kills and bounties
##   5. removed enemies are compacted away and queued spawns fill up to the cap
##
## A ram's `retreat_s` holds the battering damage not yet reported as whole-HP leak events while
## it is at the gate (EN_BATTER); `hp <= 0` marks an enemy for compaction within a step.


## One combat tick; returns its events in order.
static func step(state: SiegeState, inputs: SiegeInputs, dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.content == null or state.content.map == null:
		return events
	var tb := SiegeCombatTable.of(state.content, state)
	_age_shots(state, dt)
	_breach_clock(state, dt, events)
	SiegeSpawner.step(state, inputs, tb, dt, events)
	_zones(state, dt)
	_move(state, tb, dt, events)
	SiegeTowers.step(state, tb, dt, events)
	_compact(state, tb)
	SiegeSpawner.drain(state, tb)
	return events


## Gate damage `dmg` with the warm-up wave's floor applied; returns the HP actually lost and
## starts a Breach when the gate reaches 0. No damage lands during a Breach.
static func damage_gate(state: SiegeState, dmg: float, events: Array[Dictionary]) -> float:
	if state.breach_s > 0.0 or dmg <= 0.0:
		return 0.0
	var before := state.gate_hp
	var after := before - dmg
	if state.role == SiegeIds.ROLE_WARMUP_WAVE:
		var floor_hp := state.content.num("gate.warmup_floor_hp", 50.0)
		after = maxf(after, minf(floor_hp, before))
	after = maxf(after, 0.0)
	state.gate_hp = after
	if after <= 0.0:
		state.breaches += 1
		state.breach_s = state.content.num("gate.breach_s", 10.0)
		for tw in state.pads:
			tw.hold_s = 0.0
		events.append(SiegeEvents.breach(state.breaches))
	return before - after


static func _age_shots(state: SiegeState, dt: float) -> void:
	if state.shots.is_empty():
		return
	var kept: Array[SiegeShot] = []
	for s in state.shots:
		s.age_s += dt
		if s.age_s < 0.1 - 1e-6:
			kept.append(s)
	state.shots = kept


## The Breach clock; at its end the gate is back at restore_hp and every rider loses 30% of
## their unspent denarii (rounded down).
static func _breach_clock(state: SiegeState, dt: float, events: Array[Dictionary]) -> void:
	if state.breach_s <= 0.0:
		return
	state.breach_s = maxf(snappedf(state.breach_s - dt, 0.001), 0.0)
	if state.breach_s > 0.0:
		return
	state.gate_hp = minf(state.content.num("gate.restore_hp", 30.0), state.gate_max)
	var loss := state.content.num("gate.breach_loss", 0.3)
	for r in state.riders:
		r.denarii -= floorf(floorf(r.denarii) * loss + 1e-9)
	events.append(SiegeEvents.gate_restored(state.gate_hp))


static func _zones(state: SiegeState, dt: float) -> void:
	if state.zones.is_empty():
		return
	var kept: Array[SiegeZoneState] = []
	for z in state.zones:
		if z.delay_s > 0.0:
			z.delay_s = maxf(snappedf(z.delay_s - dt, 0.001), 0.0)
		else:
			z.ttl_s = maxf(snappedf(z.ttl_s - dt, 0.001), 0.0)
		if z.delay_s > 0.0 or z.ttl_s > 0.0:
			kept.append(z)
	state.zones = kept


static func _move(
	state: SiegeState, tb: SiegeCombatTable, dt: float, events: Array[Dictionary]
) -> void:
	var map := state.content.map
	var landed: Array[SiegeZoneState] = []
	for z in state.zones:
		if z.landed():
			landed.append(z)
	for e in state.enemies:
		if e.hp <= 0.0:
			continue
		match e.st:
			SiegeIds.EN_WALK:
				var slow := 1.0
				var amp := 1.0
				for z in landed:
					if z.road == e.road and absf(e.prog_m - z.prog_m) <= z.radius_m:
						slow = minf(slow, z.slow)
						amp = maxf(amp, z.amp)
				e.slow = slow
				e.amp = amp
				e.prog_m += tb.speed[e.type] * slow * dt
				if e.prog_m >= tb.road_len[e.road]:
					_arrive(state, tb, e, map, events)
				else:
					e.place(map)
			SiegeIds.EN_BATTER:
				_batter(state, tb, e, dt, events)
			_:
				e.retreat_s -= dt
				e.prog_m = maxf(e.prog_m - tb.speed[e.type] * dt, 0.0)
				if e.retreat_s <= 0.0:
					e.hp = 0.0
					tb.removed += 1
				else:
					e.place(map)


## A walker reaches the gate: damage, a leak, gone. A ram stops there and starts battering.
static func _arrive(
	state: SiegeState,
	tb: SiegeCombatTable,
	e: SiegeEnemyState,
	map: SiegeMap,
	events: Array[Dictionary]
) -> void:
	e.prog_m = tb.road_len[e.road]
	e.place(map)
	var w := state.wave
	var by_road := state.role == SiegeIds.ROLE_WAVE
	if e.type == SiegeIds.ENEMY_RAM:
		e.st = SiegeIds.EN_BATTER
		e.retreat_s = 0.0
		w.leaks += 1
		if by_road:
			state.leaks_by_road[e.road] += 1
		return
	var applied := damage_gate(state, tb.gate_hp[e.type], events)
	w.leaks += 1
	w.gate_damage += applied
	if by_road:
		state.leaks_by_road[e.road] += 1
		state.gate_damage_by_road[e.road] += applied
	events.append(SiegeEvents.leak(e.id, e.type, e.road, roundi(applied)))
	e.hp = 0.0
	tb.removed += 1


## A ram at the gate: 3 HP/s until destroyed or the wave ends; one leak event per whole HP.
static func _batter(
	state: SiegeState,
	tb: SiegeCombatTable,
	e: SiegeEnemyState,
	dt: float,
	events: Array[Dictionary]
) -> void:
	if state.breach_s > 0.0:
		return
	var applied := damage_gate(state, tb.ram_dps * dt, events)
	state.wave.gate_damage += applied
	if state.role == SiegeIds.ROLE_WAVE:
		state.gate_damage_by_road[e.road] += applied
	e.retreat_s += applied
	while e.retreat_s >= 1.0 - 1e-9:
		events.append(SiegeEvents.leak(e.id, e.type, e.road, 1))
		e.retreat_s -= 1.0


static func _compact(state: SiegeState, tb: SiegeCombatTable) -> void:
	if tb.removed <= 0:
		return
	var alive: Array[SiegeEnemyState] = []
	for e in state.enemies:
		if e.hp > 0.0:
			alive.append(e)
	state.enemies = alive

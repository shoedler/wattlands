class_name SiegeCombat
extends RefCounted
## The road, the enemies, the stations, the pads, the projectiles, the tar works, the gate and
## the 150-enemy cap (brief 2.4). Pure and deterministic like SiegeRules, which calls step() once
## per tick after routing and the mine.
##
## One tick, in order:
##   1. the Breach clock (at its end the gate is restored)
##   2. SiegeSpawner: warm-up toast, groups from the staging grounds, siege engines, rushes
##   3. movement: walkers advance (the bridge coat slows them; chariots change speed), reach the
##      gate (a leak: damage to the curtain, then the gate, then gone) or, during a Breach,
##      vanish without damage; a ram stops at the gate and batters it (paused in a Breach); the
##      siege tower docks at the moat edge; retreating enemies walk back for 3 s and vanish
##   4. SiegeTarWorks: cauldrons, pump, curtain, coat, boarders
##   5. SiegeStations: output m, winding, slew, aim and fire (projectiles and `shot` events)
##   6. SiegePads: the Scorpions
##   7. SiegeProjectiles: flight and impacts (pierce, splash, arrows), kills and bounties
##   8. removed enemies are compacted away and queued spawns fill up to the cap


## One combat tick; returns its events in order.
static func step(state: SiegeState, inputs: SiegeInputs, dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.content == null or state.path == null:
		return events
	_breach_clock(state, dt, events)
	var tb := SiegeCombatTable.of(state.content, state)
	SiegeSpawner.step(state, inputs, tb, dt, events)
	_move(state, tb, dt, events)
	tb.invalidate()
	SiegeTarWorks.step(state, tb, dt)
	SiegeStations.step(state, tb, dt, events)
	SiegePads.step(state, tb, dt, events)
	SiegeProjectiles.step(state, tb, events)
	_compact(state, tb)
	SiegeSpawner.drain(state, tb, events)
	return events


## Gate damage `dmg`: the curtain takes it first, then the gate, with the warm-up wave's floor
## applied; starts a Breach when the gate reaches 0 (every rider loses 30% of their unspent gold,
## rounded down, at once: ADR "Breach gold cut at the start"). No damage lands during a Breach.
## Returns the damage taken by curtain and gate together.
static func damage_gate(state: SiegeState, dmg: float, events: Array[Dictionary]) -> float:
	if state.breach_s > 0.0 or dmg <= 0.0:
		return 0.0
	var tar := state.tar
	var soak := minf(tar.curtain_hp, dmg)
	tar.curtain_hp -= soak
	var rest := dmg - soak
	var before := state.gate_hp
	var after := before - rest
	if state.role == SiegeIds.ROLE_WARMUP_WAVE:
		var floor_hp := state.content.num("gate.warmup_floor_hp", 50.0)
		after = maxf(after, minf(floor_hp, before))
	after = maxf(after, 0.0)
	state.gate_hp = after
	var lost := before - after
	state.wave.gate_damage += lost
	state.gate_damage += lost
	if after <= 0.0 and before > 0.0:
		state.breaches += 1
		state.breach_s = state.content.num("gate.breach_s", 10.0)
		for st in state.stations:
			st.hold_s = 0.0
		var loss := state.content.num("gate.breach_loss", 0.3)
		for r in state.riders:
			r.gold -= floorf(floorf(r.gold) * loss + 1e-9)
		events.append(SiegeEvents.breach(state.breaches))
	return soak + lost


## The Breach clock; at its end the gate is back at restore_hp (30), or keeps more when repairs
## and Iron bands bought in a break the Breach ran into already raised it.
static func _breach_clock(state: SiegeState, dt: float, events: Array[Dictionary]) -> void:
	if state.breach_s <= 0.0:
		return
	state.breach_s = maxf(snappedf(state.breach_s - dt, 0.001), 0.0)
	if state.breach_s > 0.0:
		return
	var restore := minf(state.content.num("gate.restore_hp", 30.0), state.gate_max)
	state.gate_hp = maxf(state.gate_hp, restore)
	events.append(SiegeEvents.gate_restored(state.gate_hp))


static func _move(
	state: SiegeState, tb: SiegeCombatTable, dt: float, events: Array[Dictionary]
) -> void:
	var path := state.path
	var chariot := state.content.enemy_def(SiegeIds.ENEMY_CHARIOT)
	for e in state.enemies:
		if e.hp <= 0.0:
			continue
		match e.st:
			SiegeIds.EN_WALK:
				var on_bridge := e.prog_m >= tb.bridge_from_m
				var f := tb.bridge_f if on_bridge else 1.0
				if e.type == SiegeIds.ENEMY_CHARIOT:
					_chariot(state, tb, e, chariot, on_bridge and f < 1.0, f, dt)
				else:
					e.speed_mps = tb.speed[e.type] * f
				e.prog_m += e.speed_mps * dt
				if e.type == SiegeIds.ENEMY_TOWER and e.prog_m >= tb.moat_edge_m:
					_dock(state, e, events)
				elif e.prog_m >= tb.length_m:
					_arrive(state, tb, e, events)
				e.place(path)
			SiegeIds.EN_BATTER:
				e.speed_mps = 0.0
				_batter(state, tb, e, dt, events)
			SiegeIds.EN_DOCKED:
				e.speed_mps = 0.0
			_:
				e.retreat_s -= dt
				e.speed_mps = -tb.speed[e.type]
				e.prog_m = maxf(e.prog_m - tb.speed[e.type] * dt, 0.0)
				if e.retreat_s <= 0.0:
					e.hp = 0.0
					tb.removed += 1
				else:
					e.place(path)


## A chariot's speed: a redrawn wish (base x (1 +- 0.3) every 3..6 s, seeded) it accelerates
## toward at 2 m/s^2; on a coated bridge it loses its speed changes (the base speed, coat slowed).
static func _chariot(
	state: SiegeState,
	tb: SiegeCombatTable,
	e: SiegeEnemyState,
	def: Dictionary,
	skid: bool,
	f: float,
	dt: float
) -> void:
	var base := tb.speed[SiegeIds.ENEMY_CHARIOT]
	if skid:
		e.want_mps = base
		e.speed_mps = base * f
		return
	e.redraw_s -= dt
	if e.redraw_s <= 0.0:
		redraw_chariot(state, e, def, base)
	var acc := float(def.get("accel_mps2", 2.0)) * dt
	var goal := e.want_mps * f
	e.speed_mps = clampf(goal, e.speed_mps - acc, e.speed_mps + acc)


## Draws a chariot's next wished speed and the seconds until the next draw (state.rng).
static func redraw_chariot(
	state: SiegeState, e: SiegeEnemyState, def: Dictionary, base: float
) -> void:
	var v := float(def.get("speed_var", 0.3))
	e.want_mps = base * (1.0 + state.rng.randf_range(-v, v))
	var r: Variant = def.get("redraw_s", [3, 6])
	e.redraw_s = state.rng.randf_range(float(r[0]), float(r[1]))


## A walker reaches the gate: damage (curtain first), a leak, gone. A ram stops there and starts
## battering.
static func _arrive(
	state: SiegeState, tb: SiegeCombatTable, e: SiegeEnemyState, events: Array[Dictionary]
) -> void:
	e.prog_m = tb.length_m
	var counted := state.role == SiegeIds.ROLE_WAVE
	state.wave.leaks += 1
	if counted:
		state.leaks += 1
	if e.type == SiegeIds.ENEMY_RAM:
		e.st = SiegeIds.EN_BATTER
		e.retreat_s = 0.0
		e.reached = true
		events.append(SiegeEvents.reach(e.id, e.type))
		return
	var applied := damage_gate(state, tb.gate_hp[e.type], events)
	events.append(SiegeEvents.leak(e.id, e.type, roundi(applied)))
	e.hp = 0.0
	tb.removed += 1


## The siege tower reaches the moat edge and docks: its boarders land on the wall.
static func _dock(state: SiegeState, e: SiegeEnemyState, events: Array[Dictionary]) -> void:
	e.prog_m = state.path.moat_edge_m
	e.st = SiegeIds.EN_DOCKED
	e.speed_mps = 0.0
	e.reached = true
	state.tar.boarded = true
	events.append(SiegeEvents.dock(e.id))


## A ram at the gate: gate_hp_per_s (3 HP/s) until destroyed or the wave ends; one leak event per
## whole HP.
static func _batter(
	state: SiegeState,
	tb: SiegeCombatTable,
	e: SiegeEnemyState,
	dt: float,
	events: Array[Dictionary]
) -> void:
	if state.breach_s > 0.0:
		return
	e.retreat_s += damage_gate(state, tb.ram_dps * dt, events)
	while e.retreat_s >= 1.0 - 1e-9:
		events.append(SiegeEvents.leak(e.id, e.type, 1))
		e.retreat_s -= 1.0


static func _compact(state: SiegeState, tb: SiegeCombatTable) -> void:
	if tb.removed <= 0:
		return
	var alive: Array[SiegeEnemyState] = []
	for e in state.enemies:
		if e.hp > 0.0:
			alive.append(e)
	state.enemies = alive
	tb.invalidate()
	if state.tar.boarded and state.docked_tower() == null:
		state.tar.boarded = false

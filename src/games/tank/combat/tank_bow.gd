class_name TankBow
extends RefCounted
## The bow guns (brief 2.4 Gun; owner: rules): two short guns in the nose of every tank, as in the
## reference, replacing v1's Citadel secondaries. A burst (one SHELL_BOW round for the pair) does
## tanks.json bow.damage (5) every bow.every_s (2 s) at the nearest enemy, or Behemoth part, ahead
## whose near edge is bow.min_px..bow.max_px (40-220 px) off the hull front, auto-aimed and hitting
## at once (a tracer: shot and hit events, no shell in flight). Armour is enemies.json light_mult
## (mediums 50%; heavies, destroyers and the Behemoth's parts 25%). With no enemy in range they
## work on a wire or wreck barricade in range instead: bow.clear_s (4 s) of fire clears it.
##
## Power by tank: the Bastion's arc generator (full rate in band, bow.under_band_rate under band,
## none while its rider is on reserve or stalled); the Rampart's and the Citadel's dynamo bank
## (bow.per_burst_units a burst, none below bow.min_bank or while the dynamo is stalled); the
## Bulwark's gearbox (bow.bulwark_rate, free). Nothing fires in a breakdown or with every rider
## AFK. The rate scales the burst clock (half rate: a burst every 4 s) and the clearing time.
## Each tick the Bastion's arc room records whether the guns were firing (engaged on a target with
## power): TankArcState.note_fire, the arc load `duty` the director turns into its ERG target.


static func step(state: TankState, dt: float, events: Array[Dictionary]) -> void:
	var aux := TankAux.of(state)
	var hull := state.hull
	var c := state.content
	var src := source(state)
	var rate := power_rate(state, src)
	var t := target(state, aux)
	var engaged := rate > 0.0 and t != null
	hull.bow_cd_s = maxf(hull.bow_cd_s - dt * rate, 0.0)
	if engaged:
		if t.kind == TankTarget.KIND_OBSTACLE:
			t.obstacle.bow_s += dt * rate
			if t.obstacle.bow_s >= c.num("tanks", "bow.clear_s", 4.0) - 1e-6:
				t.obstacle.cleared = true
		if hull.bow_cd_s <= 0.0:
			_burst(state, aux, src, t, events)
	var arc := state.station(TankIds.ENGINE_ARC) as TankArcState
	if arc != null:
		arc.note_fire(state.tick, engaged)


## The station that powers the bow guns: the arc generator (Bastion), else the dynamo (Rampart,
## Citadel), else the Bulwark's gearbox; null for none.
static func source(state: TankState) -> TankStationState:
	for engine: String in [TankIds.ENGINE_ARC, TankIds.ENGINE_DYNAMO, TankIds.ENGINE_BULWARK]:
		var st := state.station(engine)
		if st != null:
			return st
	return null


## The bow guns' rate now: 1 full, bow.under_band_rate or bow.bulwark_rate, 0 none (see the class
## doc). The dynamo's bank must hold a burst.
static func power_rate(state: TankState, src: TankStationState) -> float:
	var c := state.content
	if src == null or state.hull.breakdown or state.all_afk:
		return 0.0
	if src is TankArcState:
		var arc := src as TankArcState
		if arc.slot < 0 or arc.stalled or arc.reserve or arc.unpowered:
			return 0.0
		return 1.0 if arc.in_band else c.num("tanks", "bow.under_band_rate", 0.5)
	if src is TankDynamoState:
		var dyn := src as TankDynamoState
		if dyn.slot < 0 or dyn.stalled or dyn.bank < c.num("tanks", "bow.min_bank", 10.0):
			return 0.0
		return 1.0
	if src is TankGearboxState:
		return c.num("tanks", "bow.bulwark_rate", 0.5)
	return 0.0


## The distance from the hull's front to `t`'s near edge (negative when it starts behind it).
static func distance(state: TankState, t: TankTarget) -> float:
	return t.rect.position.x - (state.hull.x_px + float(state.hull.hull_w))


## The bow guns' target: the nearest standing enemy or Behemoth part ahead within range, else the
## nearest wire or wreck barricade within range; null for none.
static func target(state: TankState, aux: TankAux) -> TankTarget:
	var c := state.content
	var lo := c.num("tanks", "bow.min_px", 40.0)
	var hi := c.num("tanks", "bow.max_px", 220.0)
	var best: TankTarget = null
	var best_d := INF
	var prop: TankTarget = null
	var prop_d := INF
	for t in aux.targets:
		if t.drill or not TankShells.collidable(t):
			continue
		if t.kind == TankTarget.KIND_ENEMY and t.enemy.side < 0:
			continue
		var d := distance(state, t)
		if d < lo - 1e-6 or d > hi + 1e-6:
			continue
		if t.kind == TankTarget.KIND_OBSTACLE:
			if TankDrive.blocks(t.obstacle) and d < prop_d:
				prop_d = d
				prop = t
		elif d < best_d:
			best_d = d
			best = t
	return best if best != null else prop


## One burst at `t`: the dynamo pays for it, the shot and hit events, the damage (kills credited
## to the powering station's rider, by BY_BOW) and the counters.
static func _burst(
	state: TankState,
	aux: TankAux,
	src: TankStationState,
	t: TankTarget,
	events: Array[Dictionary]
) -> void:
	var c := state.content
	state.hull.bow_cd_s = c.num("tanks", "bow.every_s", 2.0)
	if src is TankDynamoState:
		TankStations.drain(state, c.num("tanks", "bow.per_burst_units", 2.0))
	var slot := src.slot
	var r := state.rider_at(slot) if slot >= 0 else null
	events.append(TankEvents.shot(slot, TankIds.SHELL_BOW, state.take_id()))
	state.score.bow_shots += 1
	if r != null:
		r.shells_by_type[int(TankRiderState.SHELL_INDEX[TankIds.SHELL_BOW])] += 1
	var x := t.center().x
	if t.kind == TankTarget.KIND_OBSTACLE:
		events.append(
			TankEvents.hit(
				TankEvents.ON_OBSTACLE,
				t.id,
				TankDamage.shell_damage(c, TankIds.SHELL_BOW),
				TankIds.SHELL_BOW,
				0.0,
				x
			)
		)
		return
	var dmg := TankDamage.against(c, TankIds.SHELL_BOW, t)
	var on := TankEvents.ON_ENEMY if t.kind == TankTarget.KIND_ENEMY else TankEvents.ON_BOSS
	events.append(TankEvents.hit(on, t.id, dmg, TankIds.SHELL_BOW, 0.0, x))
	state.score.bow_hits += 1
	if r != null:
		r.bow_hits += 1
	if t.kind == TankTarget.KIND_ENEMY:
		TankShells.damage_enemy(state, aux, t.enemy, dmg, TankEvents.BY_BOW, slot, events)
	else:
		TankShells.damage_boss(state, aux, t.part, dmg, slot, events)

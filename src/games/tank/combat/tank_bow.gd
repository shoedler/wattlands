class_name TankBow
extends RefCounted
## The bow guns (v3 brief "One tank, five seats": the Secondaries seat, a crank-driven twin belt
## feed; owner: rules). Two short guns in the nose fire exactly TankFeedState.ROUNDS_PER_REV (2)
## rounds per pedal revolution of the Secondaries rider, alternating guns (round k from gun
## (k - 1) mod 2), at the nearest enemy, or Behemoth part, ahead whose near edge is bow.min_px ..
## bow.max_px (40-220 px) off the hull front, else at a wire or wreck barricade there
## (bow.clear_rounds rounds that hit clear it). With nothing in range the guns are silent. The
## revolutions come from the rider's cadence (TankFeedState.rev_acc integrates cadence / 60 per
## second), so the rate is 2 x cadence rounds a minute (TankFeedState.rpm).
##
## Power in band sets the guns' slew speed: they elevate toward the target at tanks.json
## bow.slew_deg_s [under band, in band]; a round hits (bow.damage, armour by enemies.json
## light_mult) when the guns point within bow.aim_tol_deg of the target, else it misses. Rounds are
## hitscan and raise no shot or hit events (up to 6 a second would swamp the event budget): the
## view reads TankFeedState.rounds and fire_tick; kills raise `kill` (BY_BOW, credited to the
## rider), and the score and the rider count rounds fired (shells_by_type) and hits (bow_hits).
##
## An empty Secondaries seat is silent, and so are the guns on reserve, in a rescue, in a
## breakdown or with every rider AFK.


static func step(
	state: TankState, inputs: TankInputs, dt: float, events: Array[Dictionary]
) -> void:
	var st := state.station(TankIds.ENGINE_FEED) as TankFeedState
	if st == null:
		return
	var aux := TankAux.of(state)
	var ri: TankRiderInput = inputs.rider(st.peer) if st.slot >= 0 else null
	var t := target(state, aux)
	var powered := (
		ri != null
		and not st.reserve
		and not st.unpowered
		and not state.all_afk
		and not state.hull.breakdown
		and not TankStations.in_rescue(ri)
	)
	if not powered or t == null:
		st.rpm = 0.0
		st.rev_acc = 0.0
		return
	_slew(state, aux, st, t, dt)
	var cadence := maxf(ri.cadence_rpm, 0.0)
	st.rpm = float(TankFeedState.ROUNDS_PER_REV) * cadence
	st.rev_acc += cadence / 60.0 * dt
	var per_round := 1.0 / float(TankFeedState.ROUNDS_PER_REV)
	while st.rev_acc >= per_round - 1e-9:
		st.rev_acc -= per_round
		_round(state, aux, st, t, events)
		if not _standing(t):
			st.rev_acc = 0.0
			break


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


## The guns' elevation (degrees, up positive) that points from the bow pivots at `t`'s centre.
static func aim_deg(state: TankState, aux: TankAux, t: TankTarget) -> float:
	var pivots := aux.geo.bow_pivots(state.hull.tank)
	var pivot := pivots[0] if not pivots.is_empty() else Vector2(float(state.hull.hull_w), 10.0)
	var from := TankTargets.hull_origin(state) + pivot
	var to := t.center()
	return rad_to_deg(atan2(from.y - to.y, maxf(to.x - from.x, 1.0)))


static func _standing(t: TankTarget) -> bool:
	if t.kind == TankTarget.KIND_OBSTACLE:
		return not t.obstacle.cleared
	return TankShells.collidable(t)


## Elevates the guns toward `t` at the slew speed the rider's band sets.
static func _slew(
	state: TankState, aux: TankAux, st: TankFeedState, t: TankTarget, dt: float
) -> void:
	var pair: Array = state.content.value("tanks", "bow.slew_deg_s", [8, 40])
	var rate := float(pair[1]) if st.in_band else float(pair[0])
	aux.bow_deg = move_toward(aux.bow_deg, aim_deg(state, aux, t), rate * dt)


## One round at `t`: counted, and a hit when the guns point at it.
static func _round(
	state: TankState, aux: TankAux, st: TankFeedState, t: TankTarget, events: Array[Dictionary]
) -> void:
	var c := state.content
	st.rounds += 1
	st.fire_tick = state.tick
	state.score.bow_shots += 1
	var r := state.rider_at(st.slot)
	if r != null:
		r.shells_by_type[int(TankRiderState.SHELL_INDEX[TankIds.SHELL_BOW])] += 1
	var tol := c.num("tanks", "bow.aim_tol_deg", 3.0)
	if absf(aux.bow_deg - aim_deg(state, aux, t)) > tol + 1e-6:
		return
	state.score.bow_hits += 1
	if r != null:
		r.bow_hits += 1
	if t.kind == TankTarget.KIND_OBSTACLE:
		t.obstacle.bow_s += 1.0
		if t.obstacle.bow_s >= c.num("tanks", "bow.clear_rounds", 12.0) - 1e-6:
			t.obstacle.cleared = true
		return
	var dmg := TankDamage.against(c, TankIds.SHELL_BOW, t)
	if t.kind == TankTarget.KIND_ENEMY:
		TankShells.damage_enemy(state, aux, t.enemy, dmg, TankEvents.BY_BOW, st.slot, events)
	else:
		TankShells.damage_boss(state, aux, t.part, dmg, st.slot, events)

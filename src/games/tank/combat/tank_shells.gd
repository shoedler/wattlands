class_name TankShells
extends RefCounted
## Shells in flight and what they do on impact (brief 2.4 Gun, Enemies; owner: rules). v4: a far shell
## flies the far frame's arc (x the range from the hull in m, y the height in m) and resolves when
## left_s runs out: ours at impact_r against the far targets, theirs on the hull as rolled at fire (a
## telegraphed one through TankEvade), a miss raising `splash`. Near friendly shells (a barricade, a
## drill wreck) fly the analytic arc (exact per-tick form) and hit the first box their path enters, or
## the ground line; splash 16 px at 50% on everything else near the impact. Near enemy shells fly
## straight to the point rolled at fire time (the tank, or 20-40 px off) and the hit lands when they
## arrive. Also the one place that applies damage to enemies, the Behemoth and obstacles, and credits
## kills.


static func step(state: TankState, aux: TankAux, dt: float, events: Array[Dictionary]) -> void:
	if state.shells.is_empty():
		return
	var keep: Array[TankShellState] = []
	for s in state.shells:
		var alive := false
		if s.far:
			alive = _fly_far(state, aux, s, dt, events)
		elif s.friendly:
			alive = _fly_friendly(state, aux, s, dt, events)
		else:
			alive = _fly_enemy(state, aux, s, dt, events)
		if state.shells.is_empty():
			# That shell lost the tank: TankEncounters.lose cleared the field, the rest with it.
			return
		if alive:
			keep.append(s)
	state.shells = keep


## The parameter in [0, 1] at which the segment p0 -> p1 first enters `r`, or -1 when it misses.
static func segment_rect(p0: Vector2, p1: Vector2, r: Rect2) -> float:
	var tmin := 0.0
	var tmax := 1.0
	var d := p1 - p0
	for axis in 2:
		var o: float = p0[axis]
		var dd: float = d[axis]
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(dd) < 1e-9:
			if o < lo or o > hi:
				return -1.0
		else:
			var t1 := (lo - o) / dd
			var t2 := (hi - o) / dd
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin


## Whether a friendly shell can still hit `t` (it stands).
static func collidable(t: TankTarget) -> bool:
	# v4: near shells fly past far targets; far impacts do not call this.
	if t.far:
		return false
	match t.kind:
		TankTarget.KIND_ENEMY:
			return t.enemy.hp > 0.0
		TankTarget.KIND_OBSTACLE:
			return not t.obstacle.cleared
	return true


## One tick of a far shell (the exact per-tick form of TankBallistics' far arc).
static func _fly_far(
	state: TankState, aux: TankAux, s: TankShellState, dt: float, events: Array[Dictionary]
) -> bool:
	var g := state.content.num("tanks", "gun.far.g_mps2", 70.0)
	s.left_s -= dt
	s.x += s.vx * dt
	s.y += s.vy * dt - 0.5 * g * dt * dt
	s.vy -= g * dt
	if s.evadable:
		TankEvade.accumulate_shell(state, aux, s, dt)
	if s.left_s > 1e-9:
		return true
	s.left_s = 0.0
	if s.friendly:
		_impact_far(state, aux, s, events)
	else:
		_land_far(state, aux, s, events)
	return false


## An enemy far shell lands: the evade first (a telegraphed one), then the hit, or a splash near us.
static func _land_far(
	state: TankState, aux: TankAux, s: TankShellState, events: Array[Dictionary]
) -> void:
	if s.evadable and TankEvade.land(state, aux, s, events):
		s.will_hit = false
	if s.will_hit:
		TankHullRules.hit(state, s.damage, s.type, TankEnemies.hull_mid(state), events)
		return
	var span: Array = state.content.value("enemies", "miss_m", [40, 90])
	var lo := float(span[0])
	var r := state.rng.randf_range(lo, float(span[1])) if state.rng != null else lo
	events.append(TankEvents.splash(r, s.type, false))


## Whether a far target still stands.
static func _far_stands(state: TankState, t: TankTarget) -> bool:
	if t.kind == TankTarget.KIND_ENEMY:
		return t.enemy.hp > 0.0
	var b := state.boss
	if b.phase != TankIds.BOSS_PHASE_1 and b.phase != TankIds.BOSS_PHASE_2:
		return false
	if t.part == TankBossState.TURRET_PART:
		return b.phase == TankIds.BOSS_PHASE_2 and b.turret_hp > 0.0
	return t.part >= 0 and t.part < b.bogie_hp.size() and b.bogie_hp[t.part] > 0.0


## The standing far target our shell landing at `r` hits directly: the aimed one (`aimed` id) first,
## then the nearest, when its range lies within its hit window; null for none.
static func _direct_far(
	state: TankState, targets: Array[TankTarget], aimed: int, r: float
) -> TankTarget:
	var direct: TankTarget = null
	var best := INF
	for t in targets:
		if not _far_stands(state, t):
			continue
		var off := absf(t.range_m - r)
		if off > t.hit_half_m + 1e-6:
			continue
		if t.id == aimed:
			return t
		if off < best:
			best = off
			direct = t
	return direct


## Our far shell lands at s.impact_r. A direct hit does its damage and raises `hit`; the others within
## gun.far.splash_m take damage.splash_frac; no direct hit raises `splash`.
static func _impact_far(
	state: TankState, aux: TankAux, s: TankShellState, events: Array[Dictionary]
) -> void:
	var c := state.content
	var targets := TankTargets.far_targets(aux)
	var direct := _direct_far(state, targets, s.target_id, s.impact_r)
	if direct != null:
		var dmg := TankDamage.against(c, s.type, direct)
		_damage_far(state, aux, s, direct, dmg, events)
		var on := (
			TankEvents.ON_ENEMY if direct.kind == TankTarget.KIND_ENEMY else TankEvents.ON_BOSS
		)
		events.append(TankEvents.hit(on, direct.id, dmg, s.type, 0.0, direct.range_m))
		state.score.hits += 1
		var rider := state.rider_at(s.source)
		if rider != null:
			rider.hits += 1
	else:
		events.append(TankEvents.splash(s.impact_r, s.type, true))
	var radius := c.num("tanks", "gun.far.splash_m", 60.0)
	var frac := c.num("tanks", "damage.splash_frac", 0.5)
	for t in targets:
		if t == direct or not _far_stands(state, t) or absf(t.range_m - s.impact_r) > radius:
			continue
		_damage_far(state, aux, s, t, TankDamage.against(c, s.type, t) * frac, events)


static func _damage_far(
	state: TankState,
	aux: TankAux,
	s: TankShellState,
	t: TankTarget,
	dmg: float,
	events: Array[Dictionary]
) -> void:
	if t.kind == TankTarget.KIND_ENEMY:
		damage_enemy(state, aux, t.enemy, dmg, TankEvents.BY_SHELL, s.source, events)
	else:
		damage_boss(state, aux, t.part, dmg, s.source, events)


static func _fly_friendly(
	state: TankState, aux: TankAux, s: TankShellState, dt: float, events: Array[Dictionary]
) -> bool:
	var g := state.content.num("tanks", "gun.gravity_px_s2", 300.0)
	var p0 := Vector2(s.x, s.y)
	var p1 := Vector2(s.x + s.vx * dt, s.y + s.vy * dt + 0.5 * g * dt * dt)
	var best_t := 2.0
	var best: TankTarget = null
	for t in aux.targets:
		if not collidable(t):
			continue
		var tt := segment_rect(p0, p1, t.rect)
		if tt >= 0.0 and tt < best_t:
			best_t = tt
			best = t
	var ground_t := 2.0
	if p1.y >= float(TankConst.GROUND_Y):
		ground_t = ((float(TankConst.GROUND_Y) - p0.y) / (p1.y - p0.y) if p1.y > p0.y else 0.0)
	if best != null and best_t <= ground_t:
		_impact(state, aux, s, best, p0.lerp(p1, best_t), events)
		return false
	if ground_t <= 1.0:
		var gp := p0.lerp(p1, clampf(ground_t, 0.0, 1.0))
		gp.y = float(TankConst.GROUND_Y)
		_impact(state, aux, s, null, gp, events)
		return false
	s.x = p1.x
	s.y = p1.y
	s.vy += g * dt
	return absf(s.x - state.hull.x_px) < 4000.0


static func _fly_enemy(
	state: TankState, aux: TankAux, s: TankShellState, dt: float, events: Array[Dictionary]
) -> bool:
	var left := float(aux.shell_left.get(s.id, 0.0)) - dt
	s.x += s.vx * dt
	s.y += s.vy * dt
	if left > 1e-9:
		aux.shell_left[s.id] = left
		return true
	aux.shell_left.erase(s.id)
	if s.will_hit:
		TankHullRules.hit(state, s.damage, s.type, s.x, events)
	return false


## A friendly shell lands at `point`, on `hit` (null: the ground).
static func _impact(
	state: TankState,
	aux: TankAux,
	s: TankShellState,
	hit: TankTarget,
	point: Vector2,
	events: Array[Dictionary]
) -> void:
	var c := state.content
	var rider := state.rider_at(s.source)
	if hit != null:
		var on := TankEvents.ON_ENEMY
		var dmg := 0.0
		match hit.kind:
			TankTarget.KIND_ENEMY:
				dmg = TankDamage.against(c, s.type, hit)
				damage_enemy(state, aux, hit.enemy, dmg, TankEvents.BY_SHELL, s.source, events)
			TankTarget.KIND_BOSS:
				on = TankEvents.ON_BOSS
				dmg = TankDamage.against(c, s.type, hit)
				damage_boss(state, aux, hit.part, dmg, s.source, events)
			TankTarget.KIND_OBSTACLE:
				on = TankEvents.ON_OBSTACLE
				if not hit.drill:
					damage_obstacle(hit.obstacle, s.type, c)
				dmg = TankDamage.shell_damage(c, s.type)
		events.append(TankEvents.hit(on, hit.id, dmg, s.type, 0.0, point.x))
		if not hit.drill and s.type != TankIds.SHELL_BOW:
			state.score.hits += 1
			if rider != null:
				rider.hits += 1
	for t in aux.targets:
		if t == hit or not collidable(t) or t.kind == TankTarget.KIND_OBSTACLE:
			continue
		var sp := TankDamage.splash(c, s.type, t, point)
		if sp <= 0.0:
			continue
		if t.kind == TankTarget.KIND_ENEMY:
			damage_enemy(state, aux, t.enemy, sp, TankEvents.BY_SHELL, s.source, events)
		else:
			damage_boss(state, aux, t.part, sp, s.source, events)


# --- Applying damage ---------------------------------------------------------------------------


## `dmg` (already armoured) to an enemy; a heavy tank backs off after taking backoff_every_damage;
## kills it at 0 HP (credited to `slot`).
static func damage_enemy(
	state: TankState,
	aux: TankAux,
	e: TankEnemyState,
	dmg: float,
	by: int,
	slot: int,
	events: Array[Dictionary]
) -> void:
	if e.hp <= 0.0:
		return
	e.hp -= dmg
	var def := state.content.enemy_def(TankIds.enemy_of(e.code))
	if def.has("backoff_m"):
		e.dmg_since_backoff += dmg
	if e.hp <= 0.0:
		e.hp = 0.0
		kill_enemy(state, aux, e, by, slot, events)
	elif def.has("backoff_m") and e.dmg_since_backoff >= float(def.get("backoff_every_damage", 50)):
		e.dmg_since_backoff = 0.0
		TankFar.back_off(state, e)


## Removes `e` and credits the kill ("by" TankEvents.BY_*; a barrage kills nothing for the score).
static func kill_enemy(
	state: TankState, aux: TankAux, e: TankEnemyState, by: int, slot: int, events: Array[Dictionary]
) -> void:
	state.enemies.erase(e)
	TankEnemies.forget(aux, e.id)
	events.append(TankEvents.kill(e.id, e.code, by, slot))
	if by != TankEvents.BY_BARRAGE:
		state.score.kills[e.code] += 1
		state.score.crew_kills += 1
	if e.gun_line:
		state.gun_line.guns_left = maxi(state.gun_line.guns_left - 1, 0)
		if state.gun_line.guns_left == 0:
			state.hull.traps_cleared = true
			for o in state.obstacles:
				if o.code == TankIds.obstacle_code(TankIds.OBST_TANK_TRAPS):
					o.cleared = true


## `dmg` to Behemoth part `part` (0..2 a bogie, 3 the turret, which only takes damage in phase 2).
static func damage_boss(
	state: TankState, aux: TankAux, part: int, dmg: float, slot: int, events: Array[Dictionary]
) -> void:
	var b := state.boss
	if b.phase != TankIds.BOSS_PHASE_1 and b.phase != TankIds.BOSS_PHASE_2:
		return
	if part == TankBossState.TURRET_PART:
		if b.phase != TankIds.BOSS_PHASE_2 or b.turret_hp <= 0.0:
			return
		b.turret_hp = maxf(b.turret_hp - dmg, 0.0)
		if b.turret_hp <= 0.0:
			TankBoss.die(state, aux, slot, events)
		return
	if part < 0 or part >= 3 or b.bogie_hp[part] <= 0.0:
		return
	b.bogie_hp[part] = maxf(b.bogie_hp[part] - dmg, 0.0)
	if b.bogie_hp[part] <= 0.0:
		TankBoss.bogie_broken(state, events)


## A shell of `shell` hits an obstacle: a heavy or Overpressure shell clears it, three light shells
## do (bow-gun fire clears it by time, TankBow).
static func damage_obstacle(o: TankObstacleState, shell: int, c: TankContent) -> void:
	if o.cleared:
		return
	if shell == TankIds.SHELL_HEAVY or shell == TankIds.SHELL_OVER:
		o.cleared = true
	elif shell == TankIds.SHELL_LIGHT:
		o.light_hits += 1
		if o.light_hits >= int(c.num("tanks", "props.light_hits_to_clear", 3.0)):
			o.cleared = true

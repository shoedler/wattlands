class_name TankEnemies
extends RefCounted
## Enemy tanks (brief 2.4 Enemies; v4; owner: rules, combat): the tick's motion and guns dispatched by
## frame (TankFar: light, medium, destroyer, heavy; TankNear: recon, tankette), and the shots. Hit rolls
## use the session RNG at fire time. A far shell flies the real arc (TankBallistics far_*) and lands
## after its flight; a near shell flies straight to the point rolled at fire time. Nothing ever stands
## or moves behind the hull, and no gun is stationary.


## The definition of `e`'s type (enemies.json).
static func def_of(state: TankState, e: TankEnemyState) -> Dictionary:
	return state.content.enemy_def(TankIds.enemy_of(e.code))


## A near threat's distance from the hull's front to its near edge right now.
static func distance(state: TankState, e: TankEnemyState) -> float:
	return e.x_px - (state.hull.x_px + state.hull.hull_w)


## Places a near threat at `dist` px off the hull's front.
static func place(state: TankState, aux: TankAux, e: TankEnemyState, dist: float) -> void:
	aux.enemy_dist[e.id] = dist
	e.x_px = state.hull.x_px + state.hull.hull_w + dist


## Whether `e` is alive and not breaking off.
static func holds_position(aux: TankAux, e: TankEnemyState) -> bool:
	return e.hp > 0.0 and not bool(aux.enemy_leaving.get(e.id, false))


## Moves every enemy one tick (after the hull moved).
static func move(state: TankState, aux: TankAux, dt: float, events: Array[Dictionary]) -> void:
	var gone: Array[TankEnemyState] = []
	for e in state.enemies:
		var def := def_of(state, e)
		var left := (
			TankNear.move(state, aux, e, def, dt, events)
			if e.is_near()
			else TankFar.move(state, aux, e, def, dt)
		)
		if left:
			gone.append(e)
	for e in gone:
		state.enemies.erase(e)
		forget(aux, e.id)


## Forgets everything the aux keeps about enemy `id` (its running telegraph included).
static func forget(aux: TankAux, id: int) -> void:
	aux.enemy_vx.erase(id)
	aux.enemy_dist.erase(id)
	aux.enemy_age.erase(id)
	aux.enemy_leaving.erase(id)
	aux.enemy_shots.erase(id)
	aux.enemy_flank_done.erase(id)
	aux.enemy_shift.erase(id)
	aux.near_left.erase(id)
	TankEvade.forget(aux, id)


## Counts every enemy's gun down and fires the ones whose time came.
static func fire(state: TankState, aux: TankAux, dt: float, events: Array[Dictionary]) -> void:
	for e in state.enemies.duplicate():
		var def := def_of(state, e)
		if e.is_near():
			TankNear.fire(state, aux, e, def, dt, events)
		else:
			TankFar.fire(state, aux, e, def, dt, events)


## A shot's hit chance before the driver's evasive factor (launch and launch_far apply that):
## its own chance x difficulty.accuracy, capped at 0.95.
static func chance(state: TankState, hit: float) -> float:
	return minf(hit * TankDifficulty.mult(state, "accuracy"), 0.95)


## The roll at fire time: x evasive_hit_mult while the driver is in band; never when `force_miss`.
static func _rolls_hit(state: TankState, hit_chance: float, force_miss: bool) -> bool:
	var p := hit_chance
	if state.hull.evasive:
		p *= state.content.num("tanks", "drive.evasive_hit_mult", 0.7)
	return not force_miss and state.rng != null and state.rng.randf() < p


## A far shot at the tank from `range_m` (the shooter's range): the lower arc that lands on the hull,
## with the hit rolled now. `telegraphed` shots stay evadable in flight: their TankEvade entry moves
## from the shooter to the shell, so a dead shooter's shell still resolves, and the `evade` event comes
## at landing. At the shell cap it resolves at once: the evade event first, then the hit.
static func launch_far(
	state: TankState,
	aux: TankAux,
	range_m: float,
	shell: int,
	damage: float,
	hit_chance: float,
	telegraphed: bool,
	src_id: int,
	code: int,
	events: Array[Dictionary]
) -> void:
	var c := state.content
	var v0 := c.num("tanks", "gun.far.v0_mps", 560.0)
	var g := c.num("tanks", "gun.far.g_mps2", 70.0)
	var reach := minf(maxf(range_m, 1.0), v0 * v0 / g)
	var elev := TankBallistics.far_elevation(reach, v0, g)
	var flight := TankBallistics.far_flight(elev, v0, g)
	var hit := _rolls_hit(state, hit_chance, false)
	var sid := state.take_id()
	events.append(TankEvents.shot(-1, shell, sid, src_id, code, flight, range_m))
	var shooter := TankEvade.boss_shooter() if code == TankIds.BOSS_CODE else src_id
	if state.shells.size() >= int(c.num("tanks", "caps.shells", 24.0)):
		if telegraphed:
			var need := TankEvade.need_s(state, shell)
			if TankEvade.resolve(state, aux, shooter, code, need, events):
				hit = false
		if hit:
			TankHullRules.hit(state, damage, shell, hull_mid(state), events)
		return
	var s := TankShellState.new()
	s.id = sid
	s.type = shell
	s.far = true
	s.x = reach
	s.y = 0.0
	s.vx = -v0 * cos(deg_to_rad(elev))
	s.vy = v0 * sin(deg_to_rad(elev))
	s.left_s = flight
	s.friendly = false
	s.damage = damage
	s.will_hit = hit
	s.evadable = telegraphed
	s.source = src_id
	state.shells.append(s)
	if telegraphed:
		TankEvade.to_shell(aux, shooter, sid, code)


## The world x a far round lands at on the tank (the hit event's x).
static func hull_mid(state: TankState) -> float:
	return state.hull.x_px + float(state.hull.hull_w) * 0.5


## A near shot from `from`: rolls the hit with the session RNG, aims at the tank's centre (a hit) or a
## point 20-40 px short of its nose on the ground (a miss), led for the hull's own speed, and sends a
## straight-flying shell that lands after its flight. At the shell cap the result applies at once.
static func launch(
	state: TankState,
	aux: TankAux,
	from: Vector2,
	shell: int,
	damage: float,
	hit_chance: float,
	force_miss: bool,
	src_id: int,
	enemy_code: int,
	events: Array[Dictionary]
) -> void:
	var c := state.content
	var hull := state.hull
	var hit := _rolls_hit(state, hit_chance, force_miss)
	var rng := state.rng
	var origin := TankTargets.hull_origin(state)
	var center := origin + Vector2(float(hull.hull_w) * 0.5, float(hull.hull_h) * 0.5)
	var hull_v := TankConst.m_to_px(hull.speed_mps)
	var speed := c.num("enemies", "shell_speed_px_s", 300.0)
	var target := center
	if not hit:
		var span: Array = c.value("enemies", "miss_px", [20, 40])
		var off := rng.randf_range(float(span[0]), float(span[1])) if rng != null else 30.0
		target = Vector2(origin.x + float(hull.hull_w) + off, float(TankConst.GROUND_Y))
	var flight := maxf(from.distance_to(target) / speed, 0.05)
	target.x += hull_v * flight
	flight = maxf(from.distance_to(target) / speed, 0.05)
	var sid := state.take_id()
	events.append(TankEvents.shot(-1, shell, sid, src_id, enemy_code))
	if state.shells.size() >= int(c.num("tanks", "caps.shells", 24.0)):
		if hit:
			TankHullRules.hit(state, damage, shell, target.x, events)
		return
	var s := TankShellState.new()
	s.id = sid
	s.type = shell
	s.x = from.x
	s.y = from.y
	var v := (target - from) / flight
	s.vx = v.x
	s.vy = v.y
	s.friendly = false
	s.damage = damage
	s.will_hit = hit
	s.source = src_id
	state.shells.append(s)
	aux.shell_left[sid] = flight


# --- Until the free-roam rewrite (SPEC_TANK 3.9): tank_roam.gd still names these, part two deletes them.


static func clamp_hold(_state: TankState, _w: int, _side: int, hold: float) -> float:
	return hold


static func reserve_hold(
	_state: TankState, _aux: TankAux, _e: TankEnemyState, _want: float, _lane: int
) -> void:
	pass


## Far kinds through TankFar (a dug-in is a heavy now), near kinds through TankNear.
static func spawn(
	state: TankState,
	aux: TankAux,
	type: String,
	_side: int,
	_hold: float,
	_fixed: bool,
	gun_line: bool,
	encounter: int
) -> TankEnemyState:
	if TankIds.NEAR_KINDS.has(type):
		var ignored: Array[Dictionary] = []
		return TankNear.spawn(state, aux, type, encounter, ignored)
	var kind := TankIds.ENEMY_HEAVY if type == TankIds.ENEMY_DUGIN else type
	return TankFar.spawn(state, aux, kind, -1.0, gun_line, encounter)

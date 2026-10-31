class_name TankNear
extends RefCounted
## v4: the near frame's threats (recon car, tankette; owner: rules). They burst from the roadside
## bushes close to the hull's nose, drive AWAY in dashes with pauses, turret traversed back, firing
## at the tank while paused, and flee: at flee_px or past flee_after_s they run, hold their fire and
## are gone past the near panel's end with no reward and no penalty. Only the bow guns hit them
## (TankBow); the main gun never lays on them (TankAim.pick). Motion lives in aux.enemy_dist: rules
## px from the hull's front, keeping pace with the hull.


## A new near threat of `type`, or null at the caps. Raises `ambush`.
static func spawn(
	state: TankState, aux: TankAux, type: String, encounter: int, events: Array[Dictionary]
) -> TankEnemyState:
	var c := state.content
	if state.enemies.size() >= int(c.num("tanks", "caps.enemies", 16.0)):
		return null
	var def := c.enemy_def(type)
	var e := TankEnemyState.new()
	e.id = state.take_id()
	e.code = TankIds.enemy_code(type)
	var size: Array = def.get("size_px", [40, 20])
	e.w = int(size[0])
	e.h = int(size[1])
	e.hp_max = (
		float(def.get("hp", 20)) * c.enemy_scale(state.hull.tank) * TankDifficulty.mult(state, "hp")
	)
	e.hp = e.hp_max
	e.encounter = encounter
	e.lane = aux.near_lane
	aux.near_lane = 1 - aux.near_lane
	e.mode = TankIds.EM_ENTER
	var span: Array = def.get("spawn_px", [10, 50])
	var rng := state.rng
	var dist := rng.randf_range(float(span[0]), float(span[1])) if rng != null else float(span[0])
	TankEnemies.place(state, aux, e, dist)
	aux.near_left[e.id] = float(def.get("burst_s", 0.6))
	var every := float((def.get("gun", {}) as Dictionary).get("every_s", 1.5))
	e.gun_s = (rng.randf_range(0.5, 1.0) if rng != null else 1.0) * every
	state.enemies.append(e)
	events.append(TankEvents.ambush(e.id, e.code))
	return e


## One tick of `e`'s motion. Returns true when it got away (`escaped` raised, counted, no credit).
static func move(
	state: TankState,
	aux: TankAux,
	e: TankEnemyState,
	def: Dictionary,
	dt: float,
	events: Array[Dictionary]
) -> bool:
	var dist := float(aux.enemy_dist.get(e.id, 0.0))
	var age := float(aux.enemy_age.get(e.id, 0.0)) + dt
	aux.enemy_age[e.id] = age
	var flees := (
		dist >= float(def.get("flee_px", 185.0)) or age >= float(def.get("flee_after_s", 16))
	)
	if e.mode != TankIds.EM_LEAVE and flees:
		e.mode = TankIds.EM_LEAVE
		aux.enemy_leaving[e.id] = true
	var left := float(aux.near_left.get(e.id, 0.0))
	match e.mode:
		TankIds.EM_ENTER:
			dist += float(def.get("burst_px_s", 60.0)) * dt
			left -= dt
			if left <= 0.0:
				left = _pause(state, e, def)
		TankIds.EM_PAUSE:
			left -= dt
			if left <= 0.0:
				e.mode = TankIds.EM_MOVE
				left = float(def.get("dash_px", 30.0))
		TankIds.EM_MOVE:
			var step := float(def.get("dash_px_s", 30.0)) * dt
			dist += step
			left -= step
			if left <= 0.0:
				left = _pause(state, e, def)
		TankIds.EM_LEAVE:
			dist += float(def.get("flee_px_s", 100.0)) * dt
	aux.near_left[e.id] = left
	var was := e.x_px
	TankEnemies.place(state, aux, e, dist)
	aux.enemy_vx[e.id] = (e.x_px - was) / dt
	if e.mode == TankIds.EM_LEAVE and dist >= TankConst.NEAR_SPAN_PX + 20.0:
		state.score.near_escaped += 1
		events.append(TankEvents.escaped(e.id, e.code))
		return true
	return false


## Goes to EM_PAUSE; returns the rolled seconds.
static func _pause(state: TankState, e: TankEnemyState, def: Dictionary) -> float:
	e.mode = TankIds.EM_PAUSE
	var span: Array = def.get("pause_s", [1.0, 1.0])
	var lo := float(span[0])
	return state.rng.randf_range(lo, float(span[1])) if state.rng != null else lo


## Counts `e`'s gun down; a paused threat fires its gun: a near shell, no telegraph, not evadable.
static func fire(
	state: TankState,
	aux: TankAux,
	e: TankEnemyState,
	def: Dictionary,
	dt: float,
	events: Array[Dictionary]
) -> void:
	if e.mode == TankIds.EM_LEAVE:
		return
	e.gun_s = maxf(e.gun_s - dt, 0.0)
	if e.mode != TankIds.EM_PAUSE or e.gun_s > 0.0:
		return
	var gun: Dictionary = def.get("gun", {})
	e.gun_s = float(gun.get("every_s", 1.5))
	TankEnemies.launch(
		state,
		aux,
		muzzle(e),
		TankIds.SHELL_ENEMY,
		float(gun.get("damage", 0.5)),
		TankEnemies.chance(state, float(gun.get("hit", 0.5))),
		false,
		e.id,
		e.code,
		events
	)


## The turret's muzzle, traversed back at the tank, in world art px.
static func muzzle(e: TankEnemyState) -> Vector2:
	return Vector2(e.x_px + float(e.w) * 0.25, float(TankConst.GROUND_Y) - float(e.h) * 0.8)

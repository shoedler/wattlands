class_name TankEnemies
extends RefCounted
## Enemy tanks (brief 2.4 Enemies; ADR "P0 simplifications" 1): spawning, kinematic movement, the
## telegraphs and the shots. An enemy enters from its edge at its speed, picks its held distance
## once (from `hold_px` with the session RNG) and then keeps station with the hull (Advance) or
## stays fixed in world space (gun lines). Distances run from the hull's nearer end to the enemy's
## near edge; a held distance is clamped so an enemy ahead ends at screen x <= 632 and 24 px of an
## enemy behind shows at the left edge. Hit rolls use the session RNG at fire time; the shell lands
## on the tank or 20-40 px short of it. Owner: rules (combat).


## The definition of `e`'s type (enemies.json).
static func def_of(state: TankState, e: TankEnemyState) -> Dictionary:
	return state.content.enemy_def(TankIds.enemy_of(e.code))


## The held distance clamped to the screen (brief 2.4): `hold` for an enemy of width `w`.
static func clamp_hold(state: TankState, w: int, side: int, hold: float) -> float:
	var c := state.content
	if side > 0:
		var right := c.num("enemies", "clamp.ahead_max_right_px", 632.0)
		var front_screen := float(TankConst.REAR_SCREEN_X + state.hull.hull_w)
		return minf(hold, right - float(w) - front_screen)
	var show := c.num("enemies", "clamp.behind_min_show_px", 24.0)
	return minf(hold, float(TankConst.REAR_SCREEN_X) - show)


## The distance from the hull's nearer end to the near edge of `e` right now.
static func distance(state: TankState, e: TankEnemyState) -> float:
	var hull := state.hull
	if e.side > 0:
		return e.x_px - (hull.x_px + hull.hull_w)
	return hull.x_px - (e.x_px + e.w)


## Places `e` at distance `dist` from the hull's nearer end.
static func place(state: TankState, e: TankEnemyState, dist: float) -> void:
	var hull := state.hull
	if e.side > 0:
		e.x_px = hull.x_px + hull.hull_w + dist
	else:
		e.x_px = hull.x_px - e.w - dist


## A new enemy of `type`. `hold` < 0 rolls it from the type's hold_px (or the screen edge for a
## destroyer); `fixed` / `gun_line` mark a gun line's guns, which enter from `entry_x` (world left
## edge) when the type moves. Appends it to the state and returns it; null at the caps.
static func spawn(
	state: TankState,
	aux: TankAux,
	type: String,
	side: int,
	hold: float,
	fixed: bool,
	gun_line: bool,
	encounter: int
) -> TankEnemyState:
	var c := state.content
	if state.enemies.size() >= int(c.num("tanks", "caps.enemies", 16.0)):
		return null
	var def := c.enemy_def(type)
	var e := TankEnemyState.new()
	e.id = state.take_id()
	e.code = TankIds.enemy_code(type)
	var size: Array = def.get("size_px", [80, 40])
	e.w = int(size[0])
	e.h = int(size[1])
	e.hp_max = float(def.get("hp", 30)) * c.enemy_scale(state.hull.tank)
	e.hp = e.hp_max
	e.side = side
	e.fixed = fixed
	e.gun_line = gun_line
	e.encounter = encounter
	var rng := state.rng
	if hold >= 0.0:
		e.hold_px = hold
	elif str(def.get("hold", "")) == "edge":
		e.hold_px = 1.0e9
	else:
		var span: Array = def.get("hold_px", [200, 200])
		e.hold_px = (
			rng.randf_range(float(span[0]), float(span[1])) if rng != null else float(span[0])
		)
	e.hold_px = clamp_hold(state, e.w, side, e.hold_px)
	if float(def.get("weave_px", 0.0)) > 0.0 and rng != null:
		e.weave = rng.randf() * TAU
	var gun: Dictionary = def.get("gun", {})
	var tele := float(def.get("telegraph_s", 0.0))
	var every := float(gun.get("every_s", 5.0))
	var roll := rng.randf_range(0.5, 1.0) if rng != null else 1.0
	e.gun_s = tele + roll * maxf(every - tele, 0.0)
	var cam := state.camera_x()
	var margin := c.num("enemies", "spawn_margin_px", 16.0)
	var enters := float(def.get("speed_px_s", 0.0)) > 0.0
	if enters:
		e.mode = TankIds.EM_ENTER
		e.x_px = cam + float(TankConst.SCREEN_W) + margin if side > 0 else cam - e.w - margin
	else:
		e.mode = TankIds.EM_HOLD
	if not enters:
		place(state, e, e.hold_px)
	state.enemies.append(e)
	aux.enemy_vx[e.id] = 0.0
	return e


## A heavy tank backs off: its held distance grows by backoff_px (within the screen clamp).
static func back_off(state: TankState, e: TankEnemyState) -> void:
	var def := def_of(state, e)
	var farther := clamp_hold(state, e.w, e.side, e.hold_px + float(def.get("backoff_px", 30.0)))
	if farther > e.hold_px:
		e.hold_px = farther
		e.mode = TankIds.EM_BACKOFF


## Moves every enemy one tick (after the hull moved): entering, keeping station, weaving, shifting.
static func move(state: TankState, aux: TankAux, dt: float) -> void:
	for e in state.enemies:
		var def := def_of(state, e)
		var speed := float(def.get("speed_px_s", 0.0))
		var old_x := e.x_px
		if e.fixed:
			_move_fixed(state, e, speed, dt)
		else:
			_move_station(state, e, def, speed, dt)
		aux.enemy_vx[e.id] = (e.x_px - old_x) / dt


static func _move_fixed(state: TankState, e: TankEnemyState, speed: float, dt: float) -> void:
	if e.mode != TankIds.EM_ENTER and e.mode != TankIds.EM_BACKOFF:
		return
	var tx := state.hull.x_px + state.hull.hull_w + e.hold_px
	if e.mode == TankIds.EM_ENTER:
		e.x_px = maxf(e.x_px - speed * dt, tx)
		if e.x_px <= tx:
			e.mode = TankIds.EM_HOLD
	else:
		e.x_px = minf(e.x_px + speed * dt, tx)
		if e.x_px >= tx:
			e.mode = TankIds.EM_HOLD


static func _move_station(
	state: TankState, e: TankEnemyState, def: Dictionary, speed: float, dt: float
) -> void:
	var dist := distance(state, e)
	match e.mode:
		TankIds.EM_ENTER:
			dist -= speed * dt
			if dist <= e.hold_px:
				dist = e.hold_px
				e.mode = TankIds.EM_HOLD
		TankIds.EM_MOVE, TankIds.EM_BACKOFF:
			dist = move_toward(dist, e.hold_px, speed * dt)
			if is_equal_approx(dist, e.hold_px):
				e.mode = TankIds.EM_HOLD
		_:
			var amp := float(def.get("weave_px", 0.0))
			if amp > 0.0:
				e.weave += TAU / maxf(float(def.get("weave_s", 3.0)), 0.1) * dt
				dist = e.hold_px + amp * sin(e.weave)
			else:
				dist = e.hold_px
			dist = clamp_hold(state, e.w, e.side, dist)
	place(state, e, dist)


## Counts every enemy's gun down and fires the ones whose time came (a telegraph shows for the last
## telegraph_s seconds of a destroyer's or heavy tank's countdown and the enemy holds still).
static func fire(state: TankState, aux: TankAux, dt: float, events: Array[Dictionary]) -> void:
	for e in state.enemies.duplicate():
		if e.mode != TankIds.EM_HOLD and e.mode != TankIds.EM_TELEGRAPH:
			continue
		var def := def_of(state, e)
		var gun: Dictionary = def.get("gun", {})
		var tele := float(def.get("telegraph_s", 0.0))
		e.gun_s -= dt
		if tele > 0.0 and e.gun_s > 0.0 and e.gun_s <= tele:
			e.mode = TankIds.EM_TELEGRAPH
			e.telegraph_s = e.gun_s
		if e.gun_s > 0.0:
			continue
		e.gun_s = float(gun.get("every_s", 5.0))
		e.telegraph_s = 0.0
		e.mode = TankIds.EM_HOLD
		var from := muzzle(aux, e, def)
		launch(
			state,
			aux,
			from,
			TankIds.SHELL_ENEMY,
			float(gun.get("damage", 4.0)),
			float(gun.get("hit", 0.6)),
			false,
			e.id,
			e.code,
			events
		)
		_after_shot(state, aux, e, def)


## Destroyers move after each shot: alternately closer by move_after_shot_px and back.
static func _after_shot(state: TankState, aux: TankAux, e: TankEnemyState, def: Dictionary) -> void:
	var shift := float(def.get("move_after_shot_px", 0.0))
	if shift <= 0.0:
		return
	var n := int(aux.enemy_shots.get(e.id, 0)) + 1
	aux.enemy_shots[e.id] = n
	var edge := clamp_hold(state, e.w, e.side, 1.0e9)
	e.hold_px = edge if n % 2 == 0 else edge - shift
	e.mode = TankIds.EM_MOVE


## The enemy's muzzle in world art px (its sprite frame faces left; one behind the tank mirrors).
static func muzzle(aux: TankAux, e: TankEnemyState, def: Dictionary) -> Vector2:
	var m := aux.geo.enemy_muzzle(str(def.get("sprite", "")))
	var top := float(TankConst.GROUND_Y - e.h)
	if e.side > 0:
		return Vector2(e.x_px + m.x, top + m.y)
	return Vector2(e.x_px + e.w - m.x, top + m.y)


## An enemy shot from `from`: rolls the hit with the session RNG (x evasive_hit_mult while the
## driver is in band; never when `force_miss`), aims at the tank's centre (a hit) or a point 20-40
## px short of its nearer end on the ground (a miss), led for the hull's own speed, and sends a
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
	var chance := hit_chance
	if hull.evasive:
		chance *= c.num("tanks", "drive.evasive_hit_mult", 0.7)
	var rng := state.rng
	var hit := not force_miss and rng != null and rng.randf() < chance
	var origin := TankTargets.hull_origin(state)
	var center := origin + Vector2(float(hull.hull_w) * 0.5, float(hull.hull_h) * 0.5)
	var hull_v := TankConst.m_to_px(hull.speed_mps)
	var speed := c.num("enemies", "shell_speed_px_s", 300.0)
	var target := center
	if not hit:
		var span: Array = c.value("enemies", "miss_px", [20, 40])
		var off := rng.randf_range(float(span[0]), float(span[1])) if rng != null else 30.0
		var toward := 1.0 if center.x >= from.x else -1.0
		var near_x := origin.x if toward > 0.0 else origin.x + float(hull.hull_w)
		target = Vector2(near_x - toward * off, float(TankConst.GROUND_Y))
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

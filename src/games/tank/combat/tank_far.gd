class_name TankFar
extends RefCounted
## v4: the far frame's enemies (light, medium, destroyer, heavy; owner: rules). They stand 800-2400 m
## off, one axis: `range_m` from the hull's front. Range is independent of the road: they pace the
## tank, hold or manoeuvre, and nothing ever comes from behind. No stationary guns: a holding force
## is heavies and destroyers on the move at long range, retiring and shifting.
##
## Entry takes 10 s from hold_m + enter_m (the view fades them in from the haze). At its hold a light
## weaves and leaves past linger_s (EM_RETIRE: gone at TankConst.FAR_SPAWN_M with no credit), a medium
## or a heavy shifts on a timer, a destroyer after each shot, and a heavy backs off in steps when it
## takes damage. A shift never takes hold_m below the kind's hold_m[0]: the 6 s evade floor (telegraph
## + flight at Hard) rests on it.


## A new far enemy of `type`, or null at the caps. `hold_m` < 0 rolls it from the kind's hold_m;
## `gun_line`: part of a holding force (never retires). Appends it to the state.
static func spawn(
	state: TankState, aux: TankAux, type: String, hold_m: float, gun_line: bool, encounter: int
) -> TankEnemyState:
	var c := state.content
	if state.enemies.size() >= int(c.num("tanks", "caps.enemies", 16.0)):
		return null
	var def := c.enemy_def(type)
	var e := TankEnemyState.new()
	e.id = state.take_id()
	e.code = TankIds.enemy_code(type)
	var size: Array = def.get("size_px", [0, 0])
	e.w = int(size[0])
	e.h = int(size[1])
	e.hp_max = (
		float(def.get("hp", 30)) * c.enemy_scale(state.hull.tank) * TankDifficulty.mult(state, "hp")
	)
	e.hp = e.hp_max
	e.gun_line = gun_line
	e.encounter = encounter
	var rng := state.rng
	var span: Array = def.get("hold_m", [1000, 1000])
	if hold_m >= 0.0:
		e.hold_m = hold_m
	else:
		e.hold_m = (
			rng.randf_range(float(span[0]), float(span[1])) if rng != null else float(span[0])
		)
	e.range_m = minf(e.hold_m + float(def.get("enter_m", 0.0)), TankConst.FAR_SPAWN_M)
	e.mode = TankIds.EM_ENTER
	e.lane = _free_lane(state)
	# The weave starts at the hold in either direction, so reaching the hold never jumps.
	if float(def.get("weave_m", 0.0)) > 0.0 and rng != null and rng.randf() < 0.5:
		e.weave = PI
	var tele := float(def.get("telegraph_s", 0.0))
	var every := float((def.get("gun", {}) as Dictionary).get("every_s", 5.0))
	var roll := rng.randf_range(0.5, 1.0) if rng != null else 1.0
	e.gun_s = tele + roll * maxf(every - tele, 0.0)
	_roll_shift(state, aux, e, def)
	state.enemies.append(e)
	return e


## The least used depth lane 0-3 (ties lowest). The lanes are the view's alone.
static func _free_lane(state: TankState) -> int:
	var used := [0, 0, 0, 0]
	for o in state.enemies:
		if not o.is_near():
			used[clampi(o.lane, 0, 3)] += 1
	var best := 0
	for l in 4:
		if used[l] < used[best]:
			best = l
	return best


static func _roll_shift(state: TankState, aux: TankAux, e: TankEnemyState, def: Dictionary) -> void:
	var span: Variant = def.get("shift_every_s")
	if not (span is Array):
		return
	var lo := float(span[0])
	aux.enemy_shift[e.id] = state.rng.randf_range(lo, float(span[1])) if state.rng != null else lo


## One tick of `e`'s motion. Returns true when it left the field (no credit).
static func move(
	state: TankState, aux: TankAux, e: TankEnemyState, def: Dictionary, dt: float
) -> bool:
	match e.mode:
		TankIds.EM_ENTER:
			var v := float(def.get("enter_mps", 20.0))
			e.range_m = maxf(e.range_m - v * dt, e.hold_m)
			e.rate_mps = -v
			if e.range_m <= e.hold_m:
				e.mode = TankIds.EM_HOLD
				e.rate_mps = 0.0
		TankIds.EM_MOVE, TankIds.EM_BACKOFF:
			var was := e.range_m
			e.range_m = move_toward(e.range_m, e.hold_m, float(def.get("move_mps", 5.0)) * dt)
			e.rate_mps = (e.range_m - was) / dt
			if is_equal_approx(e.range_m, e.hold_m):
				e.range_m = e.hold_m
				e.mode = TankIds.EM_HOLD
				e.rate_mps = 0.0
		TankIds.EM_RETIRE:
			e.rate_mps = 2.0 * float(def.get("move_mps", 10.0))
			e.range_m += e.rate_mps * dt
			return e.range_m >= TankConst.FAR_SPAWN_M
		_:
			_hold(state, aux, e, def, dt)
	return false


## Holding or telegraphing: the weave; holding, also the shift timer and the light's linger.
static func _hold(
	state: TankState, aux: TankAux, e: TankEnemyState, def: Dictionary, dt: float
) -> void:
	var amp := float(def.get("weave_m", 0.0))
	if amp > 0.0:
		var w := TAU / maxf(float(def.get("weave_s", 9.0)), 0.1)
		e.weave += w * dt
		e.range_m = e.hold_m + amp * sin(e.weave)
		e.rate_mps = amp * w * cos(e.weave)
	else:
		e.range_m = e.hold_m
		e.rate_mps = 0.0
	if e.mode != TankIds.EM_HOLD:
		return
	if _lingered(aux, e, def, dt):
		return
	if not aux.enemy_shift.has(e.id):
		return
	var left := float(aux.enemy_shift[e.id]) - dt
	aux.enemy_shift[e.id] = left
	if left <= 0.0:
		shift(state, e, def)
		_roll_shift(state, aux, e, def)


## A raider (linger_s) leaves after that long at its hold; never one of a holding force.
static func _lingered(aux: TankAux, e: TankEnemyState, def: Dictionary, dt: float) -> bool:
	var linger := float(def.get("linger_s", 0.0))
	if linger <= 0.0 or e.gun_line:
		return false
	var age := float(aux.enemy_age.get(e.id, 0.0)) + dt
	aux.enemy_age[e.id] = age
	if age < linger:
		return false
	aux.enemy_leaving[e.id] = true
	e.mode = TankIds.EM_RETIRE
	e.telegraph_s = 0.0
	TankEvade.forget(aux, e.id)
	return true


## A manoeuvre: hold_m moves shift_m either way (sign rolled), inside [hold_m[0], hold_m[1] + shift_m].
static func shift(state: TankState, e: TankEnemyState, def: Dictionary) -> void:
	var by := float(def.get("shift_m", 0.0))
	if by <= 0.0:
		return
	var span: Array = def.get("hold_m", [e.hold_m, e.hold_m])
	var sign_v := -1.0 if state.rng != null and state.rng.randf() < 0.5 else 1.0
	var want := clampf(e.hold_m + sign_v * by, float(span[0]), float(span[1]) + by)
	if not is_equal_approx(want, e.hold_m):
		e.hold_m = want
		e.mode = TankIds.EM_MOVE


## A heavy takes backoff_every_damage: it falls back backoff_m, up to retire_to_m. Its hull reverses;
## the sprite never flips.
static func back_off(state: TankState, e: TankEnemyState) -> void:
	var def := TankEnemies.def_of(state, e)
	var farther := minf(
		e.hold_m + float(def.get("backoff_m", 0.0)), float(def.get("retire_to_m", e.hold_m))
	)
	if farther > e.hold_m + 1e-6:
		e.hold_m = farther
		e.mode = TankIds.EM_BACKOFF


## Counts `e`'s gun down and fires when its time comes. A telegraphed shot (telegraph_s x
## difficulty.telegraph; a light's first shot at its hold is its flank shot) shows for the last
## seconds of the countdown while the enemy holds, always in full: a countdown that ran down while it
## moved restarts the telegraph. It counts while moving or retiring but fires only at its hold;
## nothing counts while it rolls in or backs off.
static func fire(
	state: TankState, aux: TankAux, e: TankEnemyState, def: Dictionary, dt: float, events: Array
) -> void:
	if e.mode == TankIds.EM_ENTER or e.mode == TankIds.EM_BACKOFF:
		_drop_telegraph(aux, e)
		return
	var gun: Dictionary = def.get("gun", {})
	var flank := is_flank(aux, e, def)
	var shot: Dictionary = def.get("flank", {}) if flank else gun
	var raw := float(shot.get("telegraph_s", 0.0)) if flank else float(def.get("telegraph_s", 0.0))
	var tele := raw * TankDifficulty.mult(state, "telegraph")
	e.gun_s = maxf(e.gun_s - dt, 0.0)
	if e.mode == TankIds.EM_MOVE or e.mode == TankIds.EM_RETIRE:
		_drop_telegraph(aux, e)
		return
	if tele > 0.0:
		if e.mode != TankIds.EM_TELEGRAPH and e.gun_s <= tele:
			# A countdown that ran down while the enemy could not telegraph restarts the telegraph
			# in full; one that just reached it keeps its time (within a tick).
			if e.gun_s < tele - dt - 1e-6:
				e.gun_s = tele
			e.mode = TankIds.EM_TELEGRAPH
		if e.mode == TankIds.EM_TELEGRAPH:
			e.telegraph_s = e.gun_s
			TankEvade.accumulate(state, aux, e.id, dt, TankEvade.need_s(state, TankIds.SHELL_ENEMY))
	if e.gun_s > 0.0:
		return
	e.gun_s = float(gun.get("every_s", 5.0))
	e.telegraph_s = 0.0
	e.mode = TankIds.EM_HOLD
	if flank:
		aux.enemy_flank_done[e.id] = true
	TankEnemies.launch_far(
		state,
		aux,
		e.range_m,
		TankIds.SHELL_ENEMY,
		float(shot.get("damage", 4.0)),
		TankEnemies.chance(state, float(shot.get("hit", 0.6))),
		tele > 0.0,
		e.id,
		e.code,
		events
	)
	if bool(def.get("shift_after_shot", false)):
		shift(state, e, def)


static func _drop_telegraph(aux: TankAux, e: TankEnemyState) -> void:
	if e.telegraph_s > 0.0:
		TankEvade.forget(aux, e.id)
	e.telegraph_s = 0.0


## True while `e`'s next shot is its flank shot: its kind has one and it has not fired it yet.
static func is_flank(aux: TankAux, e: TankEnemyState, def: Dictionary) -> bool:
	return def.get("flank") is Dictionary and not aux.enemy_flank_done.has(e.id)

class_name TankRoam
extends RefCounted
## Free roam (brief 2.10; owner: roam): the valley road driven back and forth, the turn, patrols,
## strongpoints, the engagement halt, time up and its overtime bound, and the crew's points. Pure:
## randomness only through state.rng (ctx.rng), time only through dt; content from
## content/tank/roam/valley.json (TankContent "valley").
##
## The rules keep working in the travel frame (TankRoamState): the tank drives toward +x in rules px
## as in a mission, map_m is the hull centre's place on the road and TankHullState.dir which way the
## frame's +x points along it. A turn (the driver's `turn` intent, 30 s cooldown, or the Autopilot at
## a map end after 3 s) stops the tank for 8 s; at its midpoint flip() mirrors the travel frame about
## the hull's centre (enemies change sides, shells and obstacles mirror, the turret keeps pointing
## the same way along the road), so every map point keeps its place.
##
## One tick: TankRules.step calls pre() after the riders are read (the work clock, the turn, the
## map ends, time up, strongpoints, patrols), TankDrive moves the hull (halted(), stop_ahead_m()
## and moved()), and post() runs last (points from this tick's events, kilometres, the strongpoints
## that fell, the engagement halt for the next tick, the fight past time up and the phase's end).
##
## Patrols every 50-110 s of WORK time (valley.json patrols): ahead (75%) or behind, a kind drawn by
## weight (heavy only past 10 min of WORK time with no heavy alive), counts scaled by the tank, trimmed
## to 6 enemies on the field; none after time up. Strongpoints: one dug-in tank per spot of the map,
## on the field only while its spot is near the screen, back 10 min after it falls. The tank halts
## while a strongpoint ahead is within engage_px or a heavy tank within engage_heavy_px. Time up at
## the roam phase's min_s: no new patrols or strongpoints; a fight in progress (an enemy within
## fight_px) may run on; then the phase's objective is done and the director ends it for every rider
## in one step (at the latest OVERTIME_MARGIN_S before max_s), the cool-down follows and the module
## finishes "time_up".

## How long before max_s a fight past time up is cut so that the director's end_phase lands first.
const OVERTIME_MARGIN_S := 1.0
## A strongpoint joins the field this far beyond the screen's edges (rules px) and leaves it past
## DESPAWN_PX (hysteresis).
const SPAWN_PX := 16.0
const DESPAWN_PX := 64.0
const EPS := 1e-6

# --- Setup ------------------------------------------------------------------------------------------


## The session start (TankRules.new_state): a free-roam content activates roam, draws the map's
## seed and the first patrol's wait from state.rng (the host; a client gets the seed from the first
## snapshot) and puts the hull's centre at valley.json start_m, facing east.
static func prepare(state: TankState) -> void:
	var c := state.content
	if c == null or not c.is_roam():
		return
	var r := state.roam
	r.active = true
	state.hull.dir = TankIds.DIR_RIGHT
	r.map_m = float(c.value("valley", "start_m", 160.0))
	if state.rng != null:
		r.map_seed = int(state.rng.randi() & 0x3FFFFFFF) + 1
		r.patrol_s = _draw(state, c.value("valley", "patrols.every_s", [50, 110]))
	ensure_map(state)


## The map for the state's seed, built on first use (the host at setup, a client once a snapshot
## carried the seed); null in missions or before the seed is known.
static func ensure_map(state: TankState) -> TankRoamMap:
	var r := state.roam
	if not r.active or r.map_seed == 0 or state.content == null:
		return null
	if state.roam_map == null or state.roam_map.map_seed != r.map_seed:
		state.roam_map = TankRoamMap.build(state.content.valley(), r.map_seed)
		var n := state.roam_map.strongpoints.size()
		if r.strong_back_s.size() != n:
			r.strong_back_s.resize(n)
			r.strong_back_s.fill(0.0)
		if r.strong_id.size() != n:
			r.strong_id.resize(n)
			r.strong_id.fill(0)
	return state.roam_map


static func _num(state: TankState, path: String, default: float) -> float:
	return state.content.num("valley", path, default)


static func _draw(state: TankState, span: Variant) -> float:
	var a: Array = span if span is Array and (span as Array).size() == 2 else [50, 110]
	if state.rng == null:
		return float(a[0])
	return state.rng.randf_range(float(a[0]), float(a[1]))


# --- Before the drive ------------------------------------------------------------------------------


static func pre(
	state: TankState, inputs: TankInputs, aux: TankAux, dt: float, events: Array[Dictionary]
) -> void:
	var r := state.roam
	if not r.active or ensure_map(state) == null:
		return
	if state.seg.seg == TankIds.SEG_ROAM and state.seg.kind == Wl.WORK:
		r.work_s += dt
	_turn(state, inputs, aux, dt, events)
	_ends(state, dt)
	_forced_turn(state, events)
	_time_up(state, events)
	_strongpoints(state, aux, dt)
	_patrols(state, aux, dt)


## The turn (brief 2.10): the running stop counts down and flips the travel frame at its midpoint;
## otherwise the driver's `turn` intent (owned by the Drive seat; the Autopilot's is
## tagged auto) starts one when no turn runs, the cooldown is over and the tank is not broken down.
static func _turn(
	state: TankState, inputs: TankInputs, aux: TankAux, dt: float, events: Array[Dictionary]
) -> void:
	var r := state.roam
	r.turn_cd_s = maxf(r.turn_cd_s - dt, 0.0)
	if r.turn_s > 0.0:
		r.turn_s = maxf(r.turn_s - dt, 0.0)
		if not r.flipped and r.turn_s <= _num(state, "turn.stop_s", 8.0) * 0.5 + EPS:
			flip(state, aux)
			r.flipped = true
		return
	for ri in inputs.riders:
		for n in ri.intents:
			if str(n.get("k", "")) != TankIds.INTENT_TURN:
				continue
			if not can_turn(state):
				return
			var slot := -1 if bool(n.get("auto", false)) else ri.slot
			start_turn(state, slot, events)
			return


## A driver who plays by hand and leaves the "Turn around" prompt standing: the crew turns on its
## own once the tank has stood turn.forced_wait_s at the turning place (the Autopilot turns sooner,
## turn.autopilot_wait_s), so a free-roam session never stalls at a road end.
static func _forced_turn(state: TankState, events: Array[Dictionary]) -> void:
	var r := state.roam
	if r.at_end == 0 or state.all_afk:
		return
	if r.end_s < _num(state, "turn.forced_wait_s", 12.0) - EPS or not can_turn(state):
		return
	start_turn(state, -1, events)


## Whether a turn may start now: free roam, no turn running, the cooldown over, not broken down,
## inside a plan phase or the cool-down.
static func can_turn(state: TankState) -> bool:
	var r := state.roam
	return (
		r.active
		and r.turn_s <= 0.0
		and r.turn_cd_s <= 0.0
		and not state.hull.breakdown
		and state.seg.seg != TankIds.SEG_NONE
	)


## Starts a turn: the 8 s stop and the 30 s cooldown, and the `turn` event with the new direction
## (`slot` -1 for the Autopilot).
static func start_turn(state: TankState, slot: int, events: Array[Dictionary]) -> void:
	var r := state.roam
	r.turn_s = _num(state, "turn.stop_s", 8.0)
	r.turn_cd_s = _num(state, "turn.cooldown_s", 30.0)
	r.flipped = false
	r.end_s = 0.0
	state.hull.speed_mps = 0.0
	var cda := state.content.num("tanks", "drive.cda_m2", 0.5)
	var offset := state.content.num("tanks", "drive.mass_offset_kg", 8.0)
	state.hull.speed_model(cda, offset).v_mps = 0.0
	events.append(TankEvents.turn(slot, -state.hull.dir))


## Mirrors the travel frame about the hull's centre (the turn's midpoint): the direction and the
## turret's facing flip, enemies change sides (station keepers re-reserve a held place on their new
## side and move to it; a running telegraph is called off), shells and obstacles mirror.
static func flip(state: TankState, aux: TankAux) -> void:
	var hull := state.hull
	var cx := hull.x_px + float(hull.hull_w) * 0.5
	hull.dir = -hull.dir
	hull.facing = -hull.facing
	hull.traverse_s = 0.0
	aux.manual_target = false
	for e in state.enemies:
		e.x_px = 2.0 * cx - e.x_px - float(e.w)
		e.side = -e.side
		var dist := TankEnemies.distance(state, e)
		aux.enemy_dist[e.id] = dist
		if e.telegraph_s > 0.0 or e.mode == TankIds.EM_TELEGRAPH:
			e.telegraph_s = 0.0
			TankEvade.forget(aux, e.id)
			if e.mode == TankIds.EM_TELEGRAPH:
				e.mode = TankIds.EM_HOLD
		if e.fixed:
			e.hold_px = dist
			continue
		if e.mode == TankIds.EM_LEAVE:
			e.hold_px = 1.0e9 if e.side > 0 else 400.0
			continue
		var want := TankEnemies.clamp_hold(state, e.w, e.side, e.hold_px)
		if e.side > 0:
			# A pursuer behind the hull holds -8 px (its last 24 px at the edge); turned ahead it
			# must not keep that and sit inside the hull's nose: ahead holds start at min_hold_px.
			want = maxf(want, state.content.num("enemies", "lanes.min_hold_px", 60.0))
		TankEnemies.reserve_hold(state, aux, e, want, e.lane)
		if e.mode != TankIds.EM_ENTER:
			e.mode = TankIds.EM_MOVE
	for s in state.shells:
		s.x = 2.0 * cx - s.x
		s.vx = -s.vx
	for o in state.obstacles:
		o.x_px = 2.0 * cx - o.x_px - float(o.w)


## Which map end the tank stands at (the road stops at the turning place in the travel direction)
## and for how long.
static func _ends(state: TankState, dt: float) -> void:
	var r := state.roam
	var map := state.roam_map
	var end := 0
	if state.hull.dir > 0 and r.map_m >= map.hi_m - 0.01:
		end = 1
	elif state.hull.dir < 0 and r.map_m <= map.lo_m + 0.01:
		end = -1
	if end != r.at_end:
		r.end_s = 0.0
	r.at_end = end
	if end != 0 and r.turn_s <= 0.0:
		r.end_s += dt
	else:
		r.end_s = 0.0


## Time up (brief 2.10): the roam phase reached its min_s.
static func _time_up(state: TankState, events: Array[Dictionary]) -> void:
	var r := state.roam
	var sg := state.seg
	if r.time_up or sg.seg != TankIds.SEG_ROAM or sg.min_s <= 0.0:
		return
	if sg.elapsed_s >= sg.min_s - EPS:
		r.time_up = true
		events.append(TankEvents.time_up(r.patrols))


## The roam phase is on and still spawning (WORK, before time up, nobody all AFK).
static func spawning(state: TankState) -> bool:
	return (
		state.roam.active
		and state.seg.seg == TankIds.SEG_ROAM
		and state.seg.kind == Wl.WORK
		and not state.roam.time_up
	)


# --- Strongpoints -----------------------------------------------------------------------------------


## The travel-frame x (rules px) of map point `m` (the hull's centre is at map_m).
static func travel_x(state: TankState, m: float) -> float:
	var hull := state.hull
	var cx := hull.x_px + float(hull.hull_w) * 0.5
	return cx + (m - state.roam.map_m) * float(hull.dir) * TankConst.PX_PER_M


## The map metre of travel-frame x `x` (rules px).
static func map_of(state: TankState, x: float) -> float:
	var hull := state.hull
	var cx := hull.x_px + float(hull.hull_w) * 0.5
	return state.roam.map_m + (x - cx) / TankConst.PX_PER_M * float(hull.dir)


## Strongpoints join the field when their spot nears the screen (never in the drive-out or after
## time up) and leave it, still standing, once it is well off screen; a fallen one counts down its
## return.
static func _strongpoints(state: TankState, aux: TankAux, dt: float) -> void:
	var r := state.roam
	var map := state.roam_map
	var cam := state.camera_x()
	var w := float((state.content.enemy_def(TankIds.ENEMY_DUGIN).get("size_px", [73, 19]))[0])
	for i in map.strongpoints.size():
		if r.strong_back_s[i] > 0.0:
			r.strong_back_s[i] = maxf(r.strong_back_s[i] - dt, 0.0)
			continue
		var left := travel_x(state, map.strongpoints[i]) - w * 0.5
		var id := r.strong_id[i]
		if id != 0:
			var e := state.enemy(id)
			if e == null:
				r.strong_id[i] = 0
			elif left > cam + TankConst.SCREEN_W + DESPAWN_PX or left + w < cam - DESPAWN_PX:
				state.enemies.erase(e)
				TankEnemies.forget(aux, e.id)
				r.strong_id[i] = 0
			continue
		if not spawning(state) or alive(state, aux) >= int(_num(state, "patrols.max_alive", 6)):
			continue
		if left > cam + TankConst.SCREEN_W + SPAWN_PX or left + w < cam - SPAWN_PX:
			continue
		r.strong_id[i] = _spawn_strongpoint(state, aux, left, w)


static func _spawn_strongpoint(state: TankState, aux: TankAux, left: float, w: float) -> int:
	var hull := state.hull
	var side := 1 if left + w * 0.5 >= hull.x_px + float(hull.hull_w) * 0.5 else -1
	var e := TankEnemies.spawn(state, aux, TankIds.ENEMY_DUGIN, side, 0.0, true, false, -1)
	if e == null:
		return 0
	e.x_px = left
	e.mode = TankIds.EM_HOLD
	var dist := TankEnemies.distance(state, e)
	e.hold_px = dist
	aux.enemy_dist[e.id] = dist
	return e.id


## Enemies on the field that count against patrols.max_alive (alive and not breaking off).
static func alive(state: TankState, aux: TankAux) -> int:
	var n := 0
	for e in state.enemies:
		if TankEnemies.holds_position(aux, e):
			n += 1
	return n


# --- Patrols ------------------------------------------------------------------------------------------


static func _patrols(state: TankState, aux: TankAux, dt: float) -> void:
	var r := state.roam
	if not spawning(state):
		return
	r.patrol_s -= dt
	if r.patrol_s > 0.0:
		return
	var room := int(_num(state, "patrols.max_alive", 6)) - alive(state, aux)
	if room <= 0:
		r.patrol_s = _num(state, "patrols.retry_s", 10.0)
		return
	var kind := roll_kind(state)
	var side := 1
	if state.rng != null and state.rng.randf() >= _num(state, "patrols.ahead_share", 0.75):
		side = -1
	if road_ahead_m(state) < _num(state, "patrols.clear_ahead_m", 150.0):
		side = -1
	for u: Variant in kind.get("units", []):
		var cnt: Array = u.get("count", [1, 1])
		var n := (
			state.rng.randi_range(int(cnt[0]), int(cnt[1])) if state.rng != null else int(cnt[0])
		)
		if n <= 0:
			continue
		n = mini(state.content.crew_count(n, state.hull.tank, state.crew), room)
		for _k in n:
			if TankEnemies.spawn(state, aux, str(u.get("enemy", "")), side, -1.0, false, false, -1):
				room -= 1
	r.patrols += 1
	r.patrol_s = _draw(state, state.content.value("valley", "patrols.every_s", [50, 110]))


## A patrol kind (valley.json patrols.kinds) drawn by weight; a kind with a heavy tank only past
## heavy_after_s of WORK time and while no heavy is on the field.
static func roll_kind(state: TankState) -> Dictionary:
	var kinds: Array = state.content.value("valley", "patrols.kinds", [])
	var heavy_ok := state.roam.work_s >= _num(state, "patrols.heavy_after_s", 600.0)
	if heavy_ok:
		for e in state.enemies:
			if e.code == TankIds.enemy_code(TankIds.ENEMY_HEAVY):
				heavy_ok = false
	var pool: Array = []
	var total := 0.0
	for k: Variant in kinds:
		if not heavy_ok and _has_heavy(k):
			continue
		pool.append(k)
		total += float(k.get("weight", 0.0))
	if pool.is_empty():
		return {}
	var x := state.rng.randf() * total if state.rng != null else 0.0
	for k2: Variant in pool:
		x -= float(k2.get("weight", 0.0))
		if x < 0.0:
			return k2
	return pool[pool.size() - 1]


static func _has_heavy(kind: Variant) -> bool:
	for u: Variant in (kind as Dictionary).get("units", []):
		if str(u.get("enemy", "")) == TankIds.ENEMY_HEAVY:
			return true
	return false


## Metres of road ahead of the hull's centre before the turning place.
static func road_ahead_m(state: TankState) -> float:
	var map := state.roam_map
	if map == null:
		return INF
	if state.hull.dir > 0:
		return maxf(map.hi_m - state.roam.map_m, 0.0)
	return maxf(state.roam.map_m - map.lo_m, 0.0)


# --- The drive (TankDrive) ---------------------------------------------------------------------------


## The tank stands still this tick: turning, engaging, or at the turning place ahead.
static func halted(state: TankState) -> bool:
	var r := state.roam
	return r.active and (r.turn_s > 0.0 or r.engaging or road_ahead_m(state) <= 0.01)


## How far (game metres from the current distance) the tank may roll this tick: the turning place
## ahead, and the engagement distance of a strongpoint ahead.
static func stop_ahead_m(state: TankState) -> float:
	if not state.roam.active:
		return INF
	var out := road_ahead_m(state)
	var engage := _num(state, "strongpoints.engage_px", 180.0)
	var front := state.hull.x_px + float(state.hull.hull_w)
	for id in state.roam.strong_id:
		var e := state.enemy(id) if id != 0 else null
		if e == null or e.side < 0 or e.hp <= 0.0:
			continue
		out = minf(out, maxf(e.x_px - front - engage, 0.0) / TankConst.PX_PER_M)
	return out


## The hull moved `dm` game metres this tick (TankDrive): the map place, the odometers.
static func moved(state: TankState, dm: float) -> void:
	var r := state.roam
	if not r.active or dm == 0.0:
		return
	var map := state.roam_map
	r.map_m += dm * float(state.hull.dir)
	if map != null:
		r.map_m = clampf(r.map_m, map.lo_m, map.hi_m)
	r.odo_m += absf(dm)
	if state.seg.seg == TankIds.SEG_ROAM:
		r.work_m += absf(dm)


## The grade under the hull for the speed model (and the director's course_grade).
static func grade_pct(state: TankState, warmup: bool) -> float:
	return TankTerrain.for_roam(
		state.content, state.roam_map, state.roam.map_m, state.hull.dir, warmup
	)


# --- After the step ------------------------------------------------------------------------------------


static func post(state: TankState, aux: TankAux, events: Array[Dictionary]) -> void:
	var r := state.roam
	if not r.active or state.roam_map == null:
		return
	_score(state, events)
	_kilometres(state)
	r.engaging = engaged(state, aux)
	_finish(state, aux)


## Points from this tick's events (brief 2.10): kills by crew fire per type, evaded shots and
## breakdowns; a fallen strongpoint starts its return clock.
static func _score(state: TankState, events: Array[Dictionary]) -> void:
	var r := state.roam
	for ev in events:
		match str(ev.get("type", "")):
			TankEvents.KILL:
				var id := int(ev.get("id", 0))
				var at := r.strong_id.find(id)
				if at >= 0 and id != 0:
					r.strong_id[at] = 0
					r.strong_back_s[at] = _num(state, "strongpoints.respawn_s", 600.0)
				if int(ev.get("by", 0)) == TankEvents.BY_BARRAGE:
					continue
				var type := TankIds.enemy_of(int(ev.get("e", 0)))
				var p := int(_num(state, "points." + type, 0.0)) if type != "" else 0
				r.points += p
				r.kill_points += p
			TankEvents.EVADE:
				if int(ev.get("ok", 0)) != 0:
					var pe := int(_num(state, "points.evade", 5.0))
					r.points += pe
					r.evade_points += pe
			TankEvents.BREAKDOWN:
				var pb := int(_num(state, "points.breakdown", -40.0))
				r.points += pb
				r.breakdown_points += pb


## +per_km for every full kilometre driven in the roam phase.
static func _kilometres(state: TankState) -> void:
	var r := state.roam
	var full := floori(r.work_m / 1000.0 + EPS)
	if full > r.km_paid:
		var p := int(_num(state, "points.per_km", 2.0)) * (full - r.km_paid)
		r.points += p
		r.km_points += p
		r.km_paid = full


## The tank halts to engage (brief 2.10 "Engage"): a strongpoint ahead within engage_px (+1 px for
## the tick the drive stopped at it) or a heavy tank within engage_heavy_px on either side.
static func engaged(state: TankState, aux: TankAux) -> bool:
	if state.hull.breakdown or state.in_cooldown():
		return false
	var engage := _num(state, "strongpoints.engage_px", 180.0) + 1.0
	var heavy_px := _num(state, "engage_heavy_px", 400.0)
	var heavy := TankIds.enemy_code(TankIds.ENEMY_HEAVY)
	for e in state.enemies:
		if e.hp <= 0.0 or not TankEnemies.holds_position(aux, e):
			continue
		var d := TankEnemies.distance(state, e)
		if e.code == heavy and d <= heavy_px:
			return true
		if e.side > 0 and state.roam.strong_id.has(e.id) and d <= engage:
			return true
	return false


## A fight is in progress (brief 2.10 time up): an enemy alive within fight_px of the hull.
static func fighting(state: TankState, aux: TankAux) -> bool:
	var px := _num(state, "fight_px", 400.0)
	for e in state.enemies:
		if e.hp > 0.0 and TankEnemies.holds_position(aux, e):
			if TankEnemies.distance(state, e) <= px:
				return true
	return false


## Past time up: overtime while a fight is in progress; the roam phase's objective is done once no
## fight runs or OVERTIME_MARGIN_S before max_s, and the director ends it for every rider.
static func _finish(state: TankState, aux: TankAux) -> void:
	var r := state.roam
	var sg := state.seg
	if sg.seg != TankIds.SEG_ROAM or not r.time_up or sg.objective_done:
		r.overtime = r.overtime and sg.seg == TankIds.SEG_ROAM and not sg.objective_done
		return
	var fight := fighting(state, aux)
	r.overtime = fight
	var late := sg.max_s > 0.0 and sg.elapsed_s >= sg.max_s - OVERTIME_MARGIN_S - EPS
	if not fight or late:
		sg.objective_done = true
		r.overtime = false


# --- Results -----------------------------------------------------------------------------------------


## Points per minute of WORK time (the grade's measure).
static func points_per_min(state: TankState) -> float:
	var mins := state.roam.work_s / 60.0
	return float(state.roam.points) / mins if mins > EPS else 0.0


## The roam grade (brief 2.8): S >= 9, A >= 7, B >= 5, C >= 3 points per WORK minute, else D.
static func grade_of(c: TankContent, per_min: float) -> String:
	for g: String in ["S", "A", "B", "C"]:
		if per_min >= c.num("valley", "grades.%s" % g, INF):
			return g
	return "D"

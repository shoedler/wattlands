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
## the hull's centre: the obstacles mirror, every map point keeps its place, and everything that moves
## leaves the field with no credit (v4: the enemy stands ahead of the tank, never behind it).
##
## One tick: TankRules.step calls pre() after the riders are read (the work clock, the turn, the
## map ends, time up, strongpoints, patrols), TankDrive moves the hull (halted(), stop_ahead_m()
## and moved()), and post() runs last (points from this tick's events, kilometres, the strongpoints
## that fell, the engagement halt for the next tick, the fight past time up and the phase's end).
##
## Patrols every 50-110 s of WORK time (valley.json patrols): a kind drawn by weight (heavy only past
## 10 min of WORK time with no heavy alive), far kinds in the far panel, near kinds from the bushes,
## counts scaled by the crew and difficulty.count, trimmed to 6 enemies on the field; none with too
## little road ahead and none after time up. Strongpoints: a holding force of one (strongpoints.enemy)
## per spot of the map, on the field once its spot is within strongpoints.spawn_m ahead in the travel
## direction, back 10 min after it falls. The tank halts while one stands or a heavy holds within
## engage_heavy_m. Time up at the roam phase's min_s: no new patrols or strongpoints; a fight in
## progress (a far enemy within fight_m, or a near threat) may run on; then the phase's objective is
## done and the director ends it for every rider in one step (at the latest OVERTIME_MARGIN_S before
## max_s), the cool-down follows and the module finishes "time_up". Under a tow (TankEncounters.lose)
## nothing spawns.

## How long before max_s a fight past time up is cut so that the director's end_phase lands first.
const OVERTIME_MARGIN_S := 1.0
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
	_patrols(state, aux, dt, events)


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


## Whether a turn may start now: free roam, no turn running, the cooldown over, not broken down or
## under tow, inside a plan phase or the cool-down.
static func can_turn(state: TankState) -> bool:
	var r := state.roam
	return (
		r.active
		and r.turn_s <= 0.0
		and r.turn_cd_s <= 0.0
		and not state.hull.out_of_action()
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


## Mirrors the travel frame about the hull's centre (the turn's midpoint): the direction flips, the
## obstacles mirror, and every enemy and shell leaves the field with no credit: nothing is ever behind
## the tank, so a patrol that was ahead is simply gone and the next comes from the new ahead.
static func flip(state: TankState, aux: TankAux) -> void:
	var hull := state.hull
	var cx := hull.x_px + float(hull.hull_w) * 0.5
	hull.dir = -hull.dir
	TankEncounters.clear_field(state, aux)
	field_cleared(state)
	for o in state.obstacles:
		o.x_px = 2.0 * cx - o.x_px - float(o.w)


## The field went clear (a flip, a lost tank): no strongpoint stands any more and the next patrol's
## wait starts over.
static func field_cleared(state: TankState) -> void:
	var r := state.roam
	if not r.active:
		return
	r.strong_id.fill(0)
	r.patrol_s = _draw(state, state.content.value("valley", "patrols.every_s", [50, 110]))


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


## The roam phase is on and still spawning (WORK, before time up, not under tow).
static func spawning(state: TankState) -> bool:
	return (
		state.roam.active
		and state.seg.seg == TankIds.SEG_ROAM
		and state.seg.kind == Wl.WORK
		and not state.roam.time_up
		and state.hull.tow_s <= 0.0
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


## A strongpoint joins the field once its spot lies within strongpoints.spawn_m ahead in the travel
## direction (never in the drive-out, under tow or after time up, never behind the tank): a holding
## force of one strongpoints.enemy in the far panel, not part of a gun line. A fallen one counts down
## its return.
static func _strongpoints(state: TankState, aux: TankAux, dt: float) -> void:
	if state.hull.tow_s > 0.0:
		return
	var r := state.roam
	var map := state.roam_map
	var reach := _num(state, "strongpoints.spawn_m", 500.0)
	var type := str(state.content.value("valley", "strongpoints.enemy", TankIds.ENEMY_HEAVY))
	for i in map.strongpoints.size():
		if r.strong_back_s[i] > 0.0:
			r.strong_back_s[i] = maxf(r.strong_back_s[i] - dt, 0.0)
			continue
		if r.strong_id[i] != 0:
			if state.enemy(r.strong_id[i]) == null:
				r.strong_id[i] = 0
			continue
		if not spawning(state) or alive(state, aux) >= int(_num(state, "patrols.max_alive", 6)):
			continue
		var ahead := (map.strongpoints[i] - r.map_m) * float(state.hull.dir)
		if ahead < 0.0 or ahead > reach:
			continue
		var e := TankFar.spawn(state, aux, type, -1.0, false, -1)
		if e != null:
			r.strong_id[i] = e.id


## Enemies on the field that count against patrols.max_alive (alive and not breaking off).
static func alive(state: TankState, aux: TankAux) -> int:
	var n := 0
	for e in state.enemies:
		if TankEnemies.holds_position(aux, e):
			n += 1
	return n


# --- Patrols ------------------------------------------------------------------------------------------


## A patrol comes when its wait ran out, always ahead: far kinds in the far panel, near kinds from the
## bushes. With too little road ahead (patrols.clear_ahead_m) or a full field it retries later.
static func _patrols(state: TankState, aux: TankAux, dt: float, events: Array[Dictionary]) -> void:
	var r := state.roam
	if not spawning(state):
		return
	r.patrol_s -= dt
	if r.patrol_s > 0.0:
		return
	var room := int(_num(state, "patrols.max_alive", 6)) - alive(state, aux)
	if room <= 0 or road_ahead_m(state) < _num(state, "patrols.clear_ahead_m", 150.0):
		r.patrol_s = _num(state, "patrols.retry_s", 10.0)
		return
	var kind := roll_kind(state)
	var mult := TankDifficulty.mult(state, "count")
	for u: Variant in kind.get("units", []):
		var cnt: Array = u.get("count", [1, 1])
		var n := (
			state.rng.randi_range(int(cnt[0]), int(cnt[1])) if state.rng != null else int(cnt[0])
		)
		if n <= 0:
			continue
		n = mini(state.content.crew_count(n, state.hull.tank, state.crew, mult), room)
		for _k in n:
			if _spawn_unit(state, aux, str(u.get("enemy", "")), events) != null:
				room -= 1
	r.patrols += 1
	r.patrol_s = _draw(state, state.content.value("valley", "patrols.every_s", [50, 110]))


static func _spawn_unit(
	state: TankState, aux: TankAux, type: String, events: Array[Dictionary]
) -> TankEnemyState:
	if TankIds.NEAR_KINDS.has(type):
		return TankNear.spawn(state, aux, type, -1, events)
	return TankFar.spawn(state, aux, type, -1.0, false, -1)


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
## ahead.
static func stop_ahead_m(state: TankState) -> float:
	if not state.roam.active:
		return INF
	return road_ahead_m(state)


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


## Points from this tick's events (brief 2.10): kills by crew fire per type, evaded shots, breakdowns
## and lost tanks; a fallen strongpoint starts its return clock.
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
			TankEvents.BREAKDOWN, TankEvents.TANK_LOST:
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


## The tank halts to engage (brief 2.10 "Engage"): a strongpoint stands, or a heavy tank holds within
## engage_heavy_m.
static func engaged(state: TankState, aux: TankAux) -> bool:
	if state.hull.out_of_action() or state.in_cooldown():
		return false
	var reach := _num(state, "engage_heavy_m", 2000.0)
	var heavy := TankIds.enemy_code(TankIds.ENEMY_HEAVY)
	for e in state.enemies:
		if e.hp <= 0.0 or not TankEnemies.holds_position(aux, e):
			continue
		if state.roam.strong_id.has(e.id) or (e.code == heavy and e.range_m <= reach):
			return true
	return false


## A fight is in progress (brief 2.10 time up): a far enemy within fight_m not retiring, or a near
## threat that has not fled.
static func fighting(state: TankState, aux: TankAux) -> bool:
	var reach := _num(state, "fight_m", 2200.0)
	for e in state.enemies:
		if e.hp > 0.0 and TankEnemies.holds_position(aux, e):
			if e.is_near() or e.range_m <= reach:
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

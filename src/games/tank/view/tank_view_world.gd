class_name TankViewWorld
extends TankViewSeats
## TankView's world layer: near enemies and wrecks, the cues that start things, and the view-only emitters.

# --- Enemies and wrecks ---------------------------------------------------------------------------------


func enemy_kind(e: TankEnemyState) -> String:
	return TankIds.enemy_of(e.code)


## Depth lanes on the near stage: each live near threat in the lane the rules hold it in.
func _lanes(state: TankState) -> Dictionary:
	var out := {}
	for e in state.enemies:
		if e.mode != TankIds.EM_DEAD and e.is_near():
			out[e.id] = clampi(e.lane, 0, LANES - 1)
	return out


func _track_enemies(state: TankState) -> void:
	lanes = _lanes(state)
	enemy_rects.clear()
	enemy_feet.clear()
	for e in state.enemies:
		if not lanes.has(e.id):
			continue
		var foot := near_foot(e)
		var x := enemy_x(e)
		enemy_feet[e.id] = foot
		enemy_rects[e.id] = _rect_at(enemy_kind(e), foot)
		_seen[e.id] = {"x": x + float(e.w) * 0.5, "kind": enemy_kind(e), "lane": lanes[e.id]}
		var rec := _near_rec(e)
		rec["travel"] = float(rec["travel"]) + absf(x - float(rec["last"])) * S
		rec["last"] = x
		rec["recoil"] = maxf(float(rec["recoil"]) - dt * NEAR_RECOIL_DECAY, 0.0)
	for id: int in _seen.keys():
		if state.enemy(id) == null:
			_seen.erase(id)
	for id: int in _near.keys():
		if state.enemy(id) == null:
			_near.erase(id)


func _near_rec(e: TankEnemyState) -> Dictionary:
	var rec: Dictionary = _near.get(e.id, {})
	if rec.is_empty():
		rec = {"travel": 0.0, "recoil": 0.0, "last": enemy_x(e)}
		_near[e.id] = rec
	return rec


## A near threat's foot on the stage: over its rules x, on its lane of the road (the relief included).
func near_foot(e: TankEnemyState) -> Vector2:
	var x := sx(enemy_x(e) + float(e.w) * 0.5)
	return Vector2(x, near_ground(x, clampi(e.lane, 0, LANES - 1)))


## The ground under near lane `lane` at stage x `x` (TankEnemyDraw's pose.ground).
func near_ground(x: float, lane: int) -> float:
	return ground_y(x) + lane_foot(lane) - GROUND


## A near threat's pose (SPEC_TANK 5.4): running away with its turret traversed back at us (turret_sx -1),
## laid on the hull. Its tracks run with its own speed on the road, its gun kicks on a shot.
func near_pose(e: TankEnemyState) -> Dictionary:
	var rec: Dictionary = _near.get(e.id, {})
	var lane := clampi(e.lane, 0, LANES - 1)
	var foot: Vector2 = enemy_feet.get(e.id, Vector2.ZERO)
	var front := tank_pos.x + headlight_x()
	var elev := rad_to_deg(atan2(40.0, maxf(foot.x - front, 20.0)))
	return {
		"travel": float(rec.get("travel", 0.0)),
		"turret_sx": -1.0,
		"elev_deg": minf(elev, NEAR_ELEV_MAX),
		"recoil": float(rec.get("recoil", 0.0)) * NEAR_RECOIL_PX,
		"dim": 1.0 - TankWorldDraw.lane_dim(lane),
		"haze": TankWorldDraw.lane_fog(lane),
		"flash": 0.0,
		"ground": Callable(self, "near_ground").bind(lane),
		"wrecked": false,
		"bogies_wrecked": [] as Array[bool],
		"flip": false,
		"time": time,
		"halo": NEAR_HALO,
	}


## Where a near threat's rounds leave its gun (stage px).
func near_muzzle(e: TankEnemyState) -> Vector2:
	var foot: Vector2 = enemy_feet.get(e.id, near_foot(e))
	return TankEnemyDraw.muzzle(enemy_kit, enemy_kind(e), foot, near_pose(e))


func _rect_at(kind: String, foot: Vector2) -> Rect2:
	var sz: Vector2 = enemy_kit.kind(kind)["size"]
	return Rect2(foot - Vector2(roundf(sz.x * 0.5), sz.y), sz)


## The rect of a `kind` standing in lane `lane` at stage x `cx`, at the flat.
func lane_rect(kind: String, cx: float, lane: int) -> Rect2:
	return _rect_at(kind, Vector2(roundf(cx), lane_foot(lane)))


static func lane_foot(lane: int) -> float:
	return LANE_FOOT[clampi(lane, 0, LANES - 1)]


func wreck_age(w: Dictionary) -> float:
	return game.state.t - float(w["t"])


func wreck_collapse(w: Dictionary) -> float:
	return clampf((wreck_age(w) - WRECK_HULK_S) / WRECK_COLLAPSE_S, 0.0, 1.0)


func wreck_fire(w: Dictionary) -> float:
	return clampf(1.0 - wreck_age(w) / WRECK_BURN_S, 0.0, 1.0)


func _age_wrecks(state: TankState) -> void:
	var keep: Array[Dictionary] = []
	for w in wrecks:
		var age := state.t - float(w["t"])
		if age < 0.0 or age > WRECK_GONE_S or sx(float(w["x"])) < -260.0:
			continue
		keep.append(w)
	wrecks = keep


func boss_visible(state: TankState) -> bool:
	return state.boss.phase != TankIds.BOSS_NONE and state.boss.phase != TankIds.BOSS_WITHDRAWN


# --- Cues -----------------------------------------------------------------------------------------------


func _on_cue(kind: String, data: Dictionary) -> void:
	if _cues.size() >= CUE_QUEUE_MAX:
		_cues.pop_front()
	_cues.append({"kind": kind, "data": data})


func _process_cues(state: TankState) -> void:
	var n := 0
	while not _cues.is_empty() and n < MAX_CUES_PER_FRAME:
		var c: Dictionary = _cues.pop_front()
		apply_cue(state, str(c["kind"]), c["data"])
		n += 1


## One event's effects (shots, hits, kills, the evade, breakdowns).
func apply_cue(state: TankState, kind: String, data: Dictionary) -> void:
	match kind:
		TankEvents.SHOT:
			_cue_shot(state, data)
		TankEvents.HIT:
			_cue_hit(state, data)
		TankEvents.KILL:
			_cue_kill(state, data)
		TankEvents.SPLASH:
			_cue_splash(data)
		TankEvents.EVADE:
			if int(data.get("ok", 0)) == 1:
				play_evade(evade_kind(state, int(data.get("s", -1))))
		TankEvents.BREAKDOWN:
			shake = 1.0
			fx.boom(at_sprite(rig.exhaust) + Vector2(30, 40), 18.0, 8)
		TankEvents.AMBUSH:
			_cue_ambush(state, int(data.get("id", 0)))
		TankEvents.TANK_LOST:
			_cue_tank_lost()
		TankEvents.STAGE_RESTART:
			_cue_restart()


## How the evade looks, from the evade event's `s`: the loader's boiler blows a smoke screen; the
## drive (or an unknown slot) lurches the tank.
func evade_kind(state: TankState, slot: int) -> String:
	var st := state.station_of(slot) if slot >= 0 else null
	if st != null and st.engine == TankIds.ENGINE_STEAM:
		return "smoke"
	return "lurch"


func _cue_shot(state: TankState, data: Dictionary) -> void:
	var sh := int(data.get("sh", 0))
	var slot := int(data.get("s", -1))
	if slot >= 0 and sh in [TankIds.SHELL_LIGHT, TankIds.SHELL_HEAVY, TankIds.SHELL_OVER]:
		fire("main")
	elif slot >= 0 and sh == TankIds.SHELL_BOW:
		# The Secondaries' rounds come from TankFeedState.rounds (_feed_rounds); without a feed
		# station a bow shot is one round.
		if seat_station(state, "sec") == null:
			fire("bow")
	elif slot < 0:
		var src := int(data.get("src", 0))
		var e := state.enemy(src)
		if e != null and e.is_near():
			_near_fired(e)
		else:
			far.on_fired(state, src, sh)


## A near threat's round: the recoil, a small flash back along its reversed gun.
func _near_fired(e: TankEnemyState) -> void:
	if not enemy_feet.has(e.id):
		return
	_near_rec(e)["recoil"] = 1.0
	var mz := near_muzzle(e)
	fx.flash(mz, 10.0, 0.1, Color(1.0, 0.62, 0.3), Vector2.LEFT)
	fx.light_scene(mz, 0.15, Color(1.0, 0.62, 0.3))


## A near threat bursts from the bushes: leaves thrown up where it is now (it may not be tracked yet).
func _cue_ambush(state: TankState, id: int) -> void:
	var e := state.enemy(id)
	if e == null or not e.is_near():
		return
	var at := near_foot(e) + Vector2(0, -8)
	fx.spark_burst(at, LEAF_BURST, LEAF, LEAF_SPEED, 0.0)
	var from := _bush_top(at)
	for i in LEAF_DRIFT:
		_throw_leaf(from if i % 2 == 0 else at)
	_shedding.append({"at": from, "left": LEAF_SHED_S})
	for k in 6:
		fx.puff(
			at + Vector2(fx.rng.randf_range(-16, 16), 6.0),
			Vector2(fx.rng.randf_range(-24, 4), fx.rng.randf_range(-12, -3)),
			1.6,
			Vector2(3.0, 15.0),
			0.3,
			NEAR_DUST,
			1.0
		)


## One leaf off the bush at `at`, thrown up and back, in the bush's colours.
func _throw_leaf(at: Vector2) -> void:
	var j := fx.rng.randf()
	fx.leaf(
		at + Vector2(fx.rng.randf_range(-20, 20), fx.rng.randf_range(-14, 4)),
		Vector2(fx.rng.randf_range(-46, 26), fx.rng.randf_range(-44, -6)),
		LEAF_DRIFT_S * (0.5 + j * 0.5),
		LEAF_DARK.lerp(LEAF_LIT, j)
	)


## The middle of the bush nearest stage point `at` (or `at`, with none near it).
func _bush_top(at: Vector2) -> Vector2:
	var best := LEAF_BUSH_PX
	var out := at
	for b in TankWorldDraw.bushes_at(self):
		var x := float(b["x"])
		if absf(x - at.x) < best:
			best = absf(x - at.x)
			out = Vector2(x, roundf(ground_y(x)) - TankWorldDraw.BUSH_VERGE - 18.0)
	return out


## The tank is lost: a boom in its hull, the scene dims for a moment. Its tow runs from hull.tow_s.
func _cue_tank_lost() -> void:
	shake = 1.0
	tow_dim_s = TOW_DIM_S
	fx.boom(at_sprite(rig.size * 0.5), 30.0, 12)
	fx.light_scene(at_sprite(rig.size * 0.5), 0.7, Color(1.0, 0.5, 0.2))


## The stage starts over: what was on the road is forgotten, the picture fades up from black.
func _cue_restart() -> void:
	restart_fade_s = RESTART_FADE_S
	tow_dim_s = 0.0
	history.clear()
	clock.reset()
	_last_tick = -1
	_cam_primed = false
	wrecks.clear()
	far.wrecks.clear()
	_seen.clear()
	_near.clear()
	_shell_seen.clear()


## While hull.tow_s runs the tank creeps back with its tracks reversed; its dim and fade run down.
func _tow_frame(state: TankState, step_dt: float) -> void:
	if state.hull.tow_s > 0.0:
		var was := tow_px
		tow_px = minf(tow_px + TOW_PX_S * step_dt, TOW_MAX_PX)
		travel -= tow_px - was
	else:
		tow_px = 0.0
	tow_dim_s = maxf(tow_dim_s - step_dt, 0.0)
	restart_fade_s = maxf(restart_fade_s - step_dt, 0.0)


func _cue_hit(state: TankState, data: Dictionary) -> void:
	var on := int(data.get("on", -1))
	var id := int(data.get("id", 0))
	var dmg := float(data.get("dmg", 0))
	if on == TankEvents.ON_TANK:
		shake = clampf(0.4 + dmg / 12.0, 0.4, 1.0)
		var p := at_sprite(Vector2(headlight_x() - 30.0, 140.0))
		fx.boom(p + Vector2(fx.rng.randf_range(-60, 10), fx.rng.randf_range(-40, 10)), 14.0, 4)
		return
	if on == TankEvents.ON_ENEMY and enemy_rects.has(id):
		var r: Rect2 = enemy_rects[id]
		fx.boom(r.get_center() + Vector2(fx.rng.randf_range(-8, 8), 0), 16.0, 4)
		return
	if on == TankEvents.ON_ENEMY and far.rects.has(id):
		far.on_enemy_hit(id)
		return
	if on == TankEvents.ON_BOSS and state.boss.phase != TankIds.BOSS_NONE:
		far.on_boss_hit(TankBossState.part_of(id))
		return
	var x := float(data.get("x", 0))
	if x != 0.0:
		fx.boom(Vector2(sx(x), GROUND - 18.0), 16.0, 4)


## A far shell landed on nothing: ours throws up earth in the far panel at its range; theirs on the road
## ahead (`r` metres squeezed into the near panel's span).
func _cue_splash(data: Dictionary) -> void:
	var r := float(data.get("r", 0))
	if int(data.get("f", 0)) == 1:
		far.on_splash(r)
		return
	var ahead := minf(r * SPLASH_PX_PER_M, TankConst.NEAR_SPAN_PX * 0.95)
	var x := minf(
		sx(hull_x + float(game.state.hull.hull_w) + ahead), TankFarMap.near_end_x(canvas.x) - 6.0
	)
	fx.boom(Vector2(x, ground_y(x) - 6.0), 12.0, 4)


func _cue_kill(state: TankState, data: Dictionary) -> void:
	var id := int(data.get("id", 0))
	if int(data.get("e", 0)) == TankIds.BOSS_CODE:
		far.on_boss_kill()
		return
	if far.on_kill(state, id) or not _seen.has(id):
		return
	var w: Dictionary = (_seen[id] as Dictionary).duplicate()
	w["t"] = state.t
	wrecks.append(w)
	while wrecks.size() > MAX_WRECKS:
		wrecks.pop_front()
	if enemy_rects.has(id):
		var r: Rect2 = enemy_rects[id]
		fx.boom(r.get_center(), 18.0, 6)
		fx.light_scene(r.get_center(), 0.4, Color(1.0, 0.5, 0.2))


# --- Emitters (view-only) --------------------------------------------------------------------------------


## A bow round's way (a unit vector): to the near threat they fire at, the barrel's tilt aside; else along the bore.
func bow_shot(k: int) -> Vector2:
	if bow_target == Vector2.ZERO:
		return bow_vector(k)
	return bow_muzzle(k).direction_to(bow_target)


func _emit(state: TankState, feed: Dictionary, step_dt: float) -> void:
	var hull := state.hull
	var rd := rider_on("drive")
	var w := 0.0
	if rd != null:
		w = (feed.get(rd.peer, Vector2(rd.raw_w, rd.cadence_rpm)) as Vector2).x
	_smoke_acc += step_dt * (3.0 + w / 30.0)
	var ex := at_sprite(rig.exhaust)
	var soot := clampf(w / 400.0, 0.0, 1.0)
	while _smoke_acc >= 1.0:
		_smoke_acc -= 1.0
		var j := fx.rng.randf()
		fx.puff(
			ex + Vector2(j * 3.0 - 1.5, 0),
			Vector2(-12.0 - j * 10.0, -14.0 - j * 6.0 - soot * 6.0),
			6.0 + j * 2.0,
			Vector2(6.0, 52.0 + j * 22.0),
			0.12 + 0.1 * soot,
			Color(0.42, 0.42, 0.44).lerp(Color(0.2, 0.18, 0.16), soot * 0.7).lerp(
				Color(0.48, 0.41, 0.35), j * 0.4
			),
			0.3
		)
	# Steam from the boiler's stack while the loader pedals, the safety valve over band.
	var lr := rig.seat_room("loader")
	var pw := machine_power("loader")
	var cad := float(cadences.get("loader", 0.0))
	_steam_acc += step_dt * (cad / 30.0 + (6.0 if pw > 1.18 else 0.0))
	while _steam_acc >= 1.0:
		_steam_acc -= 1.0
		var over := pw > 1.18
		fx.puff(
			at_sprite(Vector2(lr.position.x + 24.0, 114.0)) + Vector2(fx.rng.randf_range(-2, 2), 0),
			Vector2(-6.0, -22.0 - (14.0 if over else 0.0)),
			2.2,
			Vector2(3.0, 16.0 if over else 10.0),
			0.16 if over else 0.08,
			Color(0.78, 0.8, 0.82),
			0.3
		)
	# Dust and grit from the tracks at speed (thick while the tank turns).
	var px_s := hull.speed_mps * TankConst.PX_PER_M * S
	_dust_acc += step_dt * clampf(px_s / 8.0, 0.0, 6.0)
	_dust_acc += step_dt * 12.0 * turn_dust(state)
	while _dust_acc >= 1.0:
		_dust_acc -= 1.0
		var i := fx.rng.randi_range(0, 2)
		fx.puff(
			wheel_contact(i) + Vector2(fx.rng.randf_range(-10, 10), -1.0),
			Vector2(fx.rng.randf_range(-14, -4), fx.rng.randf_range(-6, -2)),
			1.4,
			Vector2(2.0, 9.0),
			0.18,
			Color(0.3, 0.25, 0.2),
			1.0
		)
	_emit_near(state, step_dt)
	_kick_acc += step_dt * clampf(px_s / 6.0, 0.0, 10.0)
	var sp := TankRig.vec((rig.gear["sprocket"] as Dictionary)["c"])
	while _kick_acc >= 1.0:
		_kick_acc -= 1.0
		var kick := at_sprite(Vector2(sp.x + fx.rng.randf_range(-6.0, 8.0), rig.ground - 2.0))
		fx.puff(
			kick,
			Vector2(fx.rng.randf_range(-22, -8), fx.rng.randf_range(-10, -3)),
			0.9,
			Vector2(1.5, 6.0),
			0.16,
			Color(0.42, 0.36, 0.28),
			1.0
		)
	for wk in wrecks:
		var fire_k := wreck_fire(wk)
		if fire_k > 0.0 and fx.rng.randf() < step_dt * 6.0 * (0.3 + fire_k):
			var hp := TankWorldDraw.wreck_hatch(self, wk)
			if hp.x > -40.0 and hp.x < canvas.x + 40.0:
				var j2 := fx.rng.randf()
				fx.puff(
					hp + Vector2(j2 * 2.0 - 1.0, -2.0),
					Vector2(-3.0 - j2 * 3.0, -20.0 - j2 * 6.0),
					4.0,
					Vector2(2.0, 14.0 + j2 * 8.0),
					0.26,
					Color(0.2, 0.19, 0.18).lerp(Color(0.12, 0.11, 0.11), j2),
					1.0
				)
	if hull.tow_s > 0.0:
		_tow_smoke_acc += step_dt * TOW_SMOKE_S
		while _tow_smoke_acc >= 1.0:
			_tow_smoke_acc -= 1.0
			var j3 := fx.rng.randf()
			fx.puff(
				ex + Vector2(20.0 + j3 * 160.0, 14.0 - j3 * 10.0),
				Vector2(-8.0 - j3 * 8.0, -20.0 - j3 * 10.0),
				7.0 + j3 * 3.0,
				Vector2(8.0, 44.0 + j3 * 20.0),
				0.42,
				Color(0.09, 0.08, 0.08).lerp(Color(0.16, 0.14, 0.13), j3),
				0.3
			)
	if hull.breakdown and fx.rng.randf() < step_dt * 4.0:
		fx.puff(
			ex + Vector2(20, 10),
			Vector2(-6, -16),
			4.0,
			Vector2(6.0, 30.0),
			0.35,
			Color(0.1, 0.09, 0.09)
		)
		if fx.rng.randf() < 0.3:
			var dr := rig.seat_room("drive")
			fx.spark_burst(at_sprite(dr.get_center()), 4, Color(1, 0.7, 0.3), 40.0, 0.0)


## The near threats running: smoke streaming back from the exhaust toward us, dust kicked up low at the rear wheels,
## and leaves off the bush one is bursting from.
func _emit_near(state: TankState, step_dt: float) -> void:
	_emit_leaves(state, step_dt)
	var crowd := float(mini(enemy_feet.size(), NEAR_EMIT_MAX))
	_near_smoke_acc += step_dt * NEAR_EXHAUST_S * crowd
	_near_dust_acc += step_dt * NEAR_DUST_S * crowd
	if enemy_feet.is_empty():
		_near_smoke_acc = 0.0
		_near_dust_acc = 0.0
		return
	var ids: Array = enemy_feet.keys()
	while _near_smoke_acc >= 1.0:
		_near_smoke_acc -= 1.0
		_near_exhaust(state, ids[fx.rng.randi_range(0, ids.size() - 1)])
	while _near_dust_acc >= 1.0:
		_near_dust_acc -= 1.0
		_near_dust(state, ids[fx.rng.randi_range(0, ids.size() - 1)])


## While a threat is coming out of the bushes, the bush keeps throwing leaves; one it has left goes on shedding a while.
func _emit_leaves(state: TankState, step_dt: float) -> void:
	for i in range(_shedding.size() - 1, -1, -1):
		var b: Dictionary = _shedding[i]
		b["left"] = float(b["left"]) - step_dt
		b["at"] = (b["at"] as Vector2) - Vector2(scroll_px, 0.0)
		if float(b["left"]) <= 0.0:
			_shedding.remove_at(i)
		elif fx.rng.randf() < step_dt * LEAF_RATE * 0.5:
			_throw_leaf(b["at"])
	for id: int in enemy_feet:
		var e := state.enemy(id)
		if e == null or e.mode != TankIds.EM_ENTER:
			continue
		var from := _bush_top((enemy_feet[id] as Vector2) + Vector2(0, -8))
		if fx.rng.randf() < step_dt * LEAF_RATE:
			_throw_leaf(from)


func _near_exhaust(state: TankState, id: int) -> void:
	var e := state.enemy(id)
	if e == null:
		return
	var row := enemy_kit.kind(enemy_kind(e))
	var sz: Vector2 = row["size"]
	var at: Vector2 = row.get("exhaust", sz * Vector2(0.12, 0.45))
	var j := fx.rng.randf()
	var from: Vector2 = (enemy_feet[id] as Vector2) - Vector2(sz.x * 0.5, float(row["ground"])) + at
	if e.mode == TankIds.EM_PAUSE:
		fx.puff(
			from,
			Vector2(-8.0 - j * 8.0, -9.0 - j * 5.0),
			1.2 + j * 0.5,
			Vector2(1.5, 8.0),
			0.3,
			NEAR_EXHAUST,
			0.45
		)
		fx.send_under_last(false)
		return
	fx.wisp(
		from + Vector2(0.0, fx.rng.randf_range(-1.5, 1.5)),
		Vector2(-NEAR_STREAK_V * (0.75 + j * 0.5), -2.0 - j * 7.0),
		NEAR_STREAK_S * (0.7 + j * 0.6),
		NEAR_STREAK_LEN * (0.6 + j * 0.8),
		0.5,
		NEAR_EXHAUST
	)
	fx.send_under_last(true)


func _near_dust(state: TankState, id: int) -> void:
	var e := state.enemy(id)
	if e == null:
		return
	if e.mode == TankIds.EM_PAUSE and fx.rng.randf() > NEAR_DUST_PAUSED:
		return
	var sz: Vector2 = enemy_kit.kind(enemy_kind(e))["size"]
	var foot: Vector2 = enemy_feet[id]
	dust_fx.puff(
		foot + Vector2(-sz.x * 0.5 + fx.rng.randf_range(0.0, sz.x * 0.3), -1.0),
		Vector2(fx.rng.randf_range(-58, -22), fx.rng.randf_range(-7, -2)),
		0.9,
		Vector2(3.0, 12.0),
		0.24,
		NEAR_DUST,
		0.6
	)


## Shells on the near stage this frame: [{at, dir, friendly, type}]. A near shell eases from the art
## muzzle onto the rules' path over its first 260 px; a far one shows only on its near stretches
## (_far_shell_near).
func shells_drawn(state: TankState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var alive := {}
	for s in state.shells:
		alive[s.id] = true
		if s.far:
			var row := _far_shell_near(s)
			if not row.is_empty():
				out.append(row)
			continue
		var wp := shell_pos(s)
		var p := Vector2(sx(wp.x), sy(wp.y))
		var info: Dictionary = _shell_seen.get(s.id, {})
		if info.is_empty():
			var start := p
			var src := state.enemy(s.source)
			if s.friendly:
				start = muzzle() if s.type != TankIds.SHELL_BOW else bow_muzzle(0)
			elif src != null and enemy_feet.has(src.id):
				start = near_muzzle(src)
			info = {"first": p, "off": start - p}
			_shell_seen[s.id] = info
		var first: Vector2 = info["first"]
		var k := clampf(1.0 - first.distance_to(p) / 260.0, 0.0, 1.0)
		var v := Vector2(s.vx, s.vy).normalized()
		if v == Vector2.ZERO:
			v = Vector2.RIGHT if s.friendly else Vector2.LEFT
		out.append(
			{
				"at": p + (info["off"] as Vector2) * k,
				"dir": v,
				"friendly": s.friendly,
				"type": s.type
			}
		)
	for id: int in _shell_seen.keys():
		if not alive.has(id):
			_shell_seen.erase(id)
	return out


## A far shell on the near stage (SPEC_TANK 4.4), or {}: ours for its first LEAVE_S, from the muzzle along
## the barrel off the near edge; theirs for its last ARRIVE_S, from the near edge onto the tank or, on a
## peer that knows it will miss (will_hit is host only), the road ahead.
func _far_shell_near(s: TankShellState) -> Dictionary:
	var edge := TankFarMap.near_end_x(canvas.x)
	var left := shell_left(s)
	var from: Vector2
	var to: Vector2
	var k: float
	if s.friendly:
		k = TankShellPath.leave_k(TankShellPath.flight_s(s.left_s, s.vy, _far_g) - left)
		if k < 0.0:
			return {}
		var info: Dictionary = _shell_seen.get(s.id, {})
		if info.is_empty():
			info = {"from": muzzle(), "dir": barrel_vector()}
			_shell_seen[s.id] = info
		from = info["from"]
		var d: Vector2 = info["dir"]
		to = from + d * (edge + 8.0 - from.x) / maxf(d.x, 0.1)
	else:
		k = TankShellPath.arrive_k(left)
		if k < 0.0:
			return {}
		from = Vector2(edge + 8.0, INCOMING_Y)
		to = _incoming_aim(s)
	var at := from.lerp(to, k)
	return {"at": at, "dir": (to - from).normalized(), "friendly": s.friendly, "type": s.type}


## Where an incoming far shell strikes on the near stage.
func _incoming_aim(s: TankShellState) -> Vector2:
	var client := game.ctx != null and game.ctx.role == Wl.CLIENT
	if s.will_hit or client:
		return at_sprite(Vector2(headlight_x(), 0.0) + INCOMING_HIT)
	var h := TankDraw.hash01(float(s.id) * 0.73)
	var x := tank_pos.x + headlight_x() + lerpf(INCOMING_MISS_PX.x, INCOMING_MISS_PX.y, h)
	x = minf(x, TankFarMap.near_end_x(canvas.x) - 6.0)
	return Vector2(x, ground_y(x) - 2.0)

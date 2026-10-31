class_name TankAim
extends RefCounted
## The auto-aim (brief 2.4 Gun; v4): which target and which elevation. Owner: rules (combat).
## Priority: a tank destroyer in its telegraph, the Behemoth's bogies, heavy, medium (or a destroyer
## not telegraphing), light, obstacle; nearer first. A far target's elevation is the far frame's lower
## arc with lead on its range rate; near arcs (barricades, drill wrecks) solve in the near frame, where
## the hull frame moves with the shells. A target the gun cannot reach is skipped. A near threat is
## never the main gun's (only the Secondaries hit them), and the turret never traverses: nothing stands
## behind the hull.


## The main gun's muzzle in world art px at `elev_deg` facing `facing`.
static func muzzle_world(state: TankState, aux: TankAux, elev_deg: float, facing: int) -> Vector2:
	return TankTargets.hull_origin(state) + aux.geo.muzzle(state.hull.tank, elev_deg, facing)


## The elevation in degrees that sends a shell through `aim` (world px) when the target moves at
## `rel_vel` px/s relative to the hull, firing facing `facing`; NAN when it cannot be reached
## inside the gun's limits. The muzzle depends on the elevation, so the solution is iterated.
static func solve(
	state: TankState, aux: TankAux, aim: Vector2, rel_vel: Vector2, facing: int
) -> float:
	var c := state.content
	var v0 := c.num("tanks", "gun.shell_speed_px_s", 360.0)
	var g := c.num("tanks", "gun.gravity_px_s2", 300.0)
	var lo := c.num("tanks", "gun.elev_min_deg", -12.0)
	var hi := c.num("tanks", "gun.elev_max_deg", 30.0)
	var elev := 0.0
	for _i in 3:
		var m := muzzle_world(state, aux, elev, facing)
		var rel := aim - m
		var e := TankBallistics.solve_lead(
			rel.x * facing, -rel.y, rel_vel.x * facing, -rel_vel.y, v0, g
		)
		if is_nan(e):
			return NAN
		elev = e
	if elev < lo - 1e-6 or elev > hi + 1e-6:
		return NAN
	return elev


## The aim points tried for a target, best first: the box centre, then its far upper part (a shell
## on a flat arc can reach the part of a low box it descends into), then its near lower corner (a
## tall box too far for a lob at its centre, such as the Behemoth's turret).
static func aim_points(t: TankTarget, facing: int) -> Array[Vector2]:
	var r := t.rect
	var out: Array[Vector2] = [r.get_center()]
	var far_x := r.end.x - 3.0 if facing > 0 else r.position.x + 3.0
	out.append(Vector2(far_x, r.position.y + minf(4.0, r.size.y * 0.5)))
	var near_x := r.position.x + 3.0 if facing > 0 else r.end.x - 3.0
	out.append(Vector2(near_x, r.end.y - minf(4.0, r.size.y * 0.5)))
	return out


## The elevation for `t` facing `facing` (the first aim point that can be reached), or NAN;
## `aim_out` receives the point used.
static func solve_target(
	state: TankState, aux: TankAux, t: TankTarget, facing: int, aim_out: Array[Vector2]
) -> float:
	if t.far:
		return _solve_far(state, t)
	var hull_v := Vector2(TankConst.m_to_px(state.hull.speed_mps), 0.0)
	for p in aim_points(t, facing):
		var e := solve(state, aux, p, t.vel - hull_v, facing)
		if not is_nan(e):
			aim_out[0] = p
			return e
	var lo := state.content.num("tanks", "gun.elev_min_deg", -12.0)
	if grazes(state, aux, t, facing, t.vel - hull_v, lo):
		aim_out[0] = t.center()
		return lo
	return NAN


## A far target's elevation: the lower arc with lead, inside the gun's limits, else NAN.
static func _solve_far(state: TankState, t: TankTarget) -> float:
	var c := state.content
	var e := TankBallistics.far_lead(
		t.range_m,
		t.rate_mps,
		c.num("tanks", "gun.far.v0_mps", 560.0),
		c.num("tanks", "gun.far.g_mps2", 70.0)
	)
	if is_nan(e):
		return NAN
	var lo := c.num("tanks", "gun.elev_min_deg", -12.0)
	var hi := c.num("tanks", "gun.elev_max_deg", 30.0)
	return e if e >= lo - 1e-6 and e <= hi + 1e-6 else NAN


## Whether a shell fired at `elev_deg` (the gun's lowest elevation, for a target too close and low
## for any aim point) comes down into the top of the target's box: the flat arc enters the box
## through its upper side.
static func grazes(
	state: TankState, aux: TankAux, t: TankTarget, facing: int, rel_vel: Vector2, elev_deg: float
) -> bool:
	var c := state.content
	var v0 := c.num("tanks", "gun.shell_speed_px_s", 360.0)
	var g := c.num("tanks", "gun.gravity_px_s2", 300.0)
	var m := muzzle_world(state, aux, elev_deg, facing)
	var a := deg_to_rad(elev_deg)
	var k := g / (2.0 * v0 * v0 * cos(a) * cos(a))
	var h := m.y - t.rect.position.y
	var disc := tan(a) * tan(a) - 4.0 * k * h
	if disc < 0.0:
		return false
	var dx := (tan(a) + sqrt(disc)) / (2.0 * k)
	var lead := rel_vel.x * TankBallistics.flight_time(dx, v0, elev_deg)
	var x := m.x + facing * dx
	var lo := t.rect.position.x + lead + 2.0
	var hi := t.rect.end.x + lead - 2.0
	return x >= lo and x <= hi


## The auto-aim's target: the manual one while it stands and can be reached, else the best by
## priority. `drill_ok`: the depot's drill wrecks are targets (aim and fire drills). Sets
## `elev_out[0]` to the elevation to it and `facing_out[0]` to the facing (always ahead); null when
## nothing can be aimed at.
static func pick(
	state: TankState, aux: TankAux, drill_ok: bool, elev_out: Array[float], facing_out: Array[int]
) -> TankTarget:
	var cam := state.camera_x()
	var muzzle := muzzle_world(state, aux, 0.0, state.hull.facing)
	var skip := {}
	var aim: Array[Vector2] = [Vector2.ZERO]
	if aux.manual_target:
		var m := TankTargets.by_id(aux, state.hull.target_id)
		if m == null or m.near or (m.drill and not drill_ok) or not in_reach(state, m):
			aux.manual_target = false
		else:
			var e := solve_target(state, aux, m, TankIds.FACE_RIGHT, aim)
			if not is_nan(e):
				elev_out[0] = e
				facing_out[0] = TankIds.FACE_RIGHT
				return m
			aux.manual_target = false
	for _n in aux.targets.size():
		var best: TankTarget = null
		var best_key := INF
		for t in aux.targets:
			if skip.has(t.id) or t.near or (t.drill and not drill_ok):
				continue
			if not TankTargets.engageable(t, cam) or not in_reach(state, t):
				continue
			var off := t.sort_key() if t.far else absf(t.sort_key() - muzzle.x)
			var key := float(t.tier) * 100000.0 + off
			if key < best_key:
				best_key = key
				best = t
		if best == null:
			return null
		var e := solve_target(state, aux, best, TankIds.FACE_RIGHT, aim)
		if not is_nan(e):
			elev_out[0] = e
			facing_out[0] = TankIds.FACE_RIGHT
			return best
		skip[best.id] = true
	return null


## Whether the main gun can see `t` (the Lights seat): a far target up to gun.far.max_range_m while
## the searchlights are lit, and up to arc.dark_range_m in the dark. Near arcs (barricades, drill
## wrecks) are always within reach.
static func in_reach(state: TankState, t: TankTarget) -> bool:
	if not t.far:
		return true
	var c := state.content
	var reach := c.num("tanks", "gun.far.max_range_m", 2500.0)
	if not TankGun.searchlights_lit(state):
		reach = minf(reach, c.num("tanks", "arc.dark_range_m", 2300.0))
	return t.range_m <= reach + 1e-6


## The auto-aim's choice for this tick, computed once per step (aux.aim_valid is cleared at the
## start of each step): the target (null if none) with `aux.aim_elev` and `aux.aim_facing`.
static func current(state: TankState, aux: TankAux) -> TankTarget:
	if aux.aim_valid:
		return aux.aim_target
	var elev: Array[float] = [0.0]
	var face: Array[int] = [state.hull.facing]
	aux.aim_target = pick(state, aux, TankSegments.drill_targets(state), elev, face)
	aux.aim_elev = elev[0]
	aux.aim_facing = face[0]
	aux.aim_valid = true
	return aux.aim_target

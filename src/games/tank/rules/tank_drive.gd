class_name TankDrive
extends RefCounted
## The tracks (brief 2.4 Drive; owner: rules): BRIEF 3.11's speed model (SpeedModel with the driving
## rider's mass + 8 kg, CdA 0.5 m^2, the terrain grade under the tank) on the driver's P_eff, the
## world scrolling at 0.4 x game speed (8 art px per game metre) and the obstacles that stop the
## tank. v2 removed the Ram, its stall and the boss dodge (brief 2.4); sprints are "Surge to evade"
## (TankEvade) and Overpressure, which do nothing in WARMUP phases, ERG phases or the first 300 s
## of the plan (TankConst.FIRST_S): ability_ok().


## Whether the rider's own phase lets its sprints work (evade, Overpressure): a WORK phase in SIM
## mode and past the first 300 s of the plan.
static func ability_ok(ri: TankRiderInput) -> bool:
	return (
		ri != null
		and ri.phase_kind == Wl.WORK
		and ri.phase_mode == Wl.SIM
		and not ri.in_first_window()
	)


static func step(state: TankState, inputs: TankInputs, dt: float) -> void:
	var hull := state.hull
	var d := TankHullRules.driver(state)
	var ri: TankRiderInput = inputs.rider(d.peer) if d != null and d.slot >= 0 else null
	var rule := TankStations.rider_rule(state, ri) if ri != null else null
	if d != null:
		d.sprinting = rule != null and rule.holds()
	hull.evasive = d != null and d.slot >= 0 and d.in_band
	_move(state, d, ri, dt)


# --- Movement ------------------------------------------------------------------------------------


## Whether the segment lets the tank roll right now.
static func _may_move(state: TankState) -> bool:
	var sg := state.seg
	match sg.seg:
		TankIds.SEG_DEPOT:
			return TankSegments.depot_driving(state)
		TankIds.SEG_ADVANCE, TankIds.SEG_SKIRMISH:
			return not sg.objective_done and state.hull.distance_m < sg.length_m
		TankIds.SEG_COOLDOWN:
			return true
	return false


static func _move(state: TankState, d: TankDieselState, ri: TankRiderInput, dt: float) -> void:
	var c := state.content
	var hull := state.hull
	var sm := hull.speed_model(
		c.num("tanks", "drive.cda_m2", 0.5), c.num("tanks", "drive.mass_offset_kg", 8.0)
	)
	if ri != null:
		sm.rider_mass_kg = ri.rider_mass_kg
	hull.grade_pct = TankTerrain.for_segment(
		c, state.seg.segment_index, hull.distance_m, state.seg.kind == Wl.WARMUP
	)
	var power := 0.0
	if d != null:
		power = d.p_eff_w
		if d is TankGearboxState:
			var g := d as TankGearboxState
			if g.lever != TankIds.LEVER_DRIVE or g.move_s > 0.0:
				power = 0.0
	var rolls := _may_move(state) and not hull.breakdown and not state.all_afk
	hull.holding = not rolls and not hull.breakdown and state.seg.seg != TankIds.SEG_CHECKPOINT
	if state.seg.seg == TankIds.SEG_CHECKPOINT or state.seg.seg == TankIds.SEG_BOSS:
		hull.holding = true
	hull.blocked_by = 0
	if not rolls:
		sm.v_mps = 0.0
		hull.speed_mps = 0.0
		return
	var v := sm.step(dt, power, hull.grade_pct)
	var dist := hull.distance_m + v * dt
	var stop_at := INF
	var seg := state.seg.seg
	if seg == TankIds.SEG_ADVANCE or seg == TankIds.SEG_SKIRMISH:
		stop_at = state.seg.length_m
	var blocker := 0
	var standoff := c.num("tanks", "props.standoff_px", 260.0)
	for o in state.obstacles:
		if o.cleared or not blocks(o):
			continue
		var limit := (o.x_px - float(hull.hull_w) - standoff) / TankConst.PX_PER_M
		if limit >= hull.distance_m - 1e-6 and limit < stop_at:
			stop_at = limit
			blocker = o.id
	if dist >= stop_at:
		dist = stop_at
		sm.v_mps = 0.0
		v = 0.0
		hull.blocked_by = blocker
	hull.speed_mps = v
	hull.distance_m = dist
	hull.x_px = TankConst.m_to_px(dist)


## True for the obstacles that stop the tank (wire and wreck barricades).
static func blocks(o: TankObstacleState) -> bool:
	return (
		o.code == TankIds.obstacle_code(TankIds.OBST_WIRE)
		or o.code == TankIds.obstacle_code(TankIds.OBST_WRECK)
	)

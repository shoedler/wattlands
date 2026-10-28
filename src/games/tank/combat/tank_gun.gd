class_name TankGun
extends RefCounted
## The main turret (brief 2.4 Gun, v3 "Combat changes"; owner: rules; the bow guns are TankBow).
## The gunner is the dynamo (the Gun seat; an empty Gun seat leaves the gun where it is: it neither
## lays, chambers nor fires). Elevation -12..+30 degrees (tanks.json gun) at 8 degrees/s with a full
## bank (2 at 0), a traverse takes 2.5 s (8 s at 0) and flips the facing when it completes; the bank
## pays 0.5 per degree and 15 per traverse. v3: the gun fires from the Loader's ready rack. With no
## round chambered and a shell in the rack, the gun goes to the loading elevation (gun.load_elev_deg)
## and chambers the oldest shell there in steam.chamber_s (1 s; TankSteamState.chamber_s counts it
## down), then auto-aim re-lays. Auto-aim (default) lays once a round is chambered and fires within
## 0.5 degrees; the rider's nudges pause it for 5 s. Dark (the Lights seat empty or not in band) the
## gun reaches only the headlight's range and its dispersion is x arc.dark_dispersion_mult (TankAim).
## Shells inherit the hull's velocity, so a moving tank's shell keeps the tank's pace.


static func step(
	state: TankState, inputs: TankInputs, dt: float, events: Array[Dictionary]
) -> void:
	var aux := TankAux.of(state)
	var gs := TankStations.gunner(state)
	if gs == null or gs.slot < 0:
		return
	var c := state.content
	var hull := state.hull
	var ri := inputs.rider(gs.peer)
	hull.aim_pause_s = maxf(hull.aim_pause_s - dt, 0.0)
	var powered := not hull.breakdown and not state.all_afk
	var elev_rate := 0.0
	var trav_rate := 0.0
	var elev_pair: Array = c.value("tanks", "dynamo.elev_deg_s", [2, 8])
	if powered and gs is TankDynamoState and not (gs as TankDynamoState).stalled:
		elev_rate = TankStations.by_bank(state, elev_pair)
		trav_rate = 1.0
	if ri != null and powered:
		for n in ri.intents:
			_intent(state, aux, gs, n, trav_rate, events)
	var tgt := TankAim.current(state, aux)
	if tgt != null:
		if not aux.manual_target:
			hull.target_id = tgt.id
	elif not aux.manual_target:
		hull.target_id = 0
	var auto := hull.aim_pause_s <= 0.0
	var chambering := powered and elev_rate > 0.0 and _chamber(state, aux, dt)
	if chambering:
		hull.elev_target_deg = c.num("tanks", "gun.load_elev_deg", 0.0)
	elif auto and tgt != null and powered and hull.loaded != TankIds.SHELL_NONE:
		hull.elev_target_deg = aux.aim_elev
		if hull.facing != aux.aim_facing and hull.traverse_s <= 0.0 and trav_rate > 0.0:
			_start_traverse(state, gs)
	# Slew.
	var lo := c.num("tanks", "gun.elev_min_deg", -12.0)
	var hi := c.num("tanks", "gun.elev_max_deg", 30.0)
	hull.elev_target_deg = clampf(hull.elev_target_deg, lo, hi)
	var step := elev_rate * dt
	var d := clampf(hull.elev_target_deg - hull.elev_deg, -step, step)
	if absf(d) > 0.0:
		hull.elev_deg += d
		if gs is TankDynamoState:
			TankStations.drain(state, c.num("tanks", "dynamo.per_degree", 0.5) * absf(d))
	if hull.traverse_s > 0.0 and trav_rate > 0.0:
		hull.traverse_s = maxf(hull.traverse_s - dt * trav_rate, 0.0)
		if hull.traverse_s <= 0.0:
			hull.facing = -hull.facing
			hull.traverse_s = 0.0
	# Auto fire.
	if auto and tgt != null and powered and can_fire(hull) and on_target(state, aux):
		if not tgt.drill or TankSegments.fire_drill(state):
			fire(state, aux, gs, tgt.drill, events)


## The searchlights are lit (the arc room's `lit`: the Lights rider in band, brief 2.4).
static func searchlights_lit(state: TankState) -> bool:
	var arc := state.station(TankIds.ENGINE_ARC) as TankArcState
	return arc != null and arc.lit


## Chambering (v3): with no round chambered and a shell in the rack the gun must sit at the loading
## elevation; there TankSteamState.chamber_s counts steam.chamber_s down and, at 0, the rack's oldest
## shell is chambered (TankHullState.loaded). Returns true while the gun is busy chambering (going
## to the loading elevation or in its chamber_s), so auto-aim leaves it there.
static func _chamber(state: TankState, aux: TankAux, dt: float) -> bool:
	var hull := state.hull
	var st := TankStations.loader(state)
	if st == null:
		return false
	st.chamber = hull.loaded != TankIds.SHELL_NONE
	if st.chamber or aux.rack_types.is_empty():
		st.chamber_s = 0.0
		return false
	var c := state.content
	var at_load := (
		absf(hull.elev_deg - c.num("tanks", "gun.load_elev_deg", 0.0))
		<= c.num("tanks", "gun.aim_tol_deg", 0.5)
	)
	if not at_load or hull.traverse_s > 0.0:
		st.chamber_s = c.num("tanks", "steam.chamber_s", 1.0)
		return true
	if st.chamber_s <= 0.0:
		st.chamber_s = c.num("tanks", "steam.chamber_s", 1.0)
	st.chamber_s = maxf(st.chamber_s - dt, 0.0)
	if st.chamber_s > 0.0:
		return true
	hull.loaded = TankStations.take_from_rack(state)
	st.chamber = hull.loaded != TankIds.SHELL_NONE
	st.loaded = st.rack >= TankConst.RACK_MAX and not st.over
	return false


## Whether a loaded shell can leave the barrel now: loaded, the breech cycle over, no traverse.
static func can_fire(hull: TankHullState) -> bool:
	return hull.loaded != TankIds.SHELL_NONE and hull.breech_s <= 0.0 and hull.traverse_s <= 0.0


## The gun faces the auto-aim's target and its elevation is within aim_tol_deg of the solution.
static func on_target(state: TankState, aux: TankAux) -> bool:
	if aux.aim_target == null:
		return false
	var hull := state.hull
	var tol := state.content.num("tanks", "gun.aim_tol_deg", 0.5)
	return (
		hull.facing == aux.aim_facing
		and hull.traverse_s <= 0.0
		and absf(hull.elev_deg - aux.aim_elev) <= tol
	)


static func _intent(
	state: TankState,
	aux: TankAux,
	gs: TankStationState,
	n: Dictionary,
	trav_rate: float,
	events: Array[Dictionary]
) -> void:
	var c := state.content
	var hull := state.hull
	match str(n.get("k", "")):
		TankIds.INTENT_AIM:
			hull.elev_target_deg = clampf(
				hull.elev_deg + float(int(n.get("d", 0))) * c.num("tanks", "gun.nudge_deg", 1.0),
				c.num("tanks", "gun.elev_min_deg", -12.0),
				c.num("tanks", "gun.elev_max_deg", 30.0)
			)
			hull.aim_pause_s = c.num("tanks", "gun.manual_pause_s", 5.0)
		TankIds.INTENT_TARGET:
			_cycle_target(state, aux, int(n.get("d", 1)))
		TankIds.INTENT_TRAVERSE:
			if hull.traverse_s <= 0.0 and trav_rate > 0.0:
				_start_traverse(state, gs)
				# A turret turned by hand stays where it was sent for a while, like a nudge. The
				# Autopilot's own traverse ("auto") is not a rider's choice and never blinds the aim.
				if not bool(n.get("auto", false)):
					hull.aim_pause_s = c.num("tanks", "gun.manual_pause_s", 5.0)
		TankIds.INTENT_FIRE:
			if can_fire(hull):
				var tgt := TankTargets.by_id(aux, hull.target_id)
				fire(state, aux, gs, tgt != null and tgt.drill, events)


## Cycles the target to the next one to the right (d = 1) or left (-1) of the current one, among
## the targets on screen the gun can reach; the choice stays until it falls.
static func _cycle_target(state: TankState, aux: TankAux, d: int) -> void:
	var cam := state.camera_x()
	var drill := TankSegments.drill_targets(state)
	var list: Array[TankTarget] = []
	for t in aux.targets:
		if (t.drill and not drill) or (not TankTargets.engageable(t, cam)):
			continue
		list.append(t)
	if list.is_empty():
		return
	list.sort_custom(func(a: TankTarget, b: TankTarget) -> bool: return a.center().x < b.center().x)
	var at := -1
	for i in list.size():
		if list[i].id == state.hull.target_id:
			at = i
	var next := (
		0 if at < 0 and d > 0 else (list.size() - 1 if at < 0 else posmod(at + d, list.size()))
	)
	state.hull.target_id = list[next].id
	aux.manual_target = true
	state.hull.aim_pause_s = 0.0


## Starts a traverse (the facing flips when it completes); the bank pays per_traverse.
static func _start_traverse(state: TankState, gs: TankStationState) -> void:
	var c := state.content
	var pair: Array = c.value("tanks", "dynamo.traverse_s", [8, 2.5])
	if gs is TankDynamoState:
		state.hull.traverse_s = TankStations.by_bank(state, pair)
		TankStations.drain(state, c.num("tanks", "dynamo.per_traverse", 15.0))
	else:
		state.hull.traverse_s = float(pair[1])


## Fires the shell in the breech from the muzzle at the current elevation plus this tick's
## dispersion (a draw from the session RNG). `drill`: a depot drill shot counts for nothing.
static func fire(
	state: TankState, aux: TankAux, gs: TankStationState, drill: bool, events: Array[Dictionary]
) -> bool:
	var c := state.content
	var hull := state.hull
	if state.shells.size() >= int(c.num("tanks", "caps.shells", 24.0)):
		return false
	var shell := hull.loaded
	var bank := 100.0
	if gs is TankDynamoState:
		bank = (gs as TankDynamoState).bank
	var disp := TankBallistics.dispersion_deg(c, bank)
	if not searchlights_lit(state):
		disp *= c.num("tanks", "arc.dark_dispersion_mult", 2.0)
	var err := state.rng.randf_range(-disp, disp) if state.rng != null else 0.0
	var v0 := c.num("tanks", "gun.shell_speed_px_s", 360.0)
	var muzzle := TankAim.muzzle_world(state, aux, hull.elev_deg, hull.facing)
	var vel := TankBallistics.velocity(v0, hull.elev_deg + err, hull.facing)
	vel.x += TankConst.m_to_px(hull.speed_mps)
	var s := TankShellState.new()
	s.id = state.take_id()
	s.type = shell
	s.x = muzzle.x
	s.y = muzzle.y
	s.vx = vel.x
	s.vy = vel.y
	s.friendly = true
	s.target_id = hull.target_id
	s.damage = TankDamage.shell_damage(c, shell)
	s.source = gs.slot
	state.shells.append(s)
	hull.loaded = TankIds.SHELL_NONE
	var st := TankStations.loader(state)
	if st != null:
		st.chamber = false
		st.chamber_s = c.num("tanks", "steam.chamber_s", 1.0) if st.rack > 0 else 0.0
	events.append(TankEvents.shot(gs.slot, shell, s.id))
	if not drill:
		state.score.shots += 1
		var r := state.rider_at(gs.slot)
		if r != null:
			r.shots += 1
			r.shells_by_type[int(TankRiderState.SHELL_INDEX[shell])] += 1
	return true

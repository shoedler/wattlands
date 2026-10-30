class_name SiegeStations
extends RefCounted
## Station output and the three weapons (brief 2.4 "Output", "Stations"). Pure, deterministic.
##
## Output: m = sum(P_eff x od) / 250 W over the riders delivering to the station (od from
## SiegeOverdrive.multiplier), x1.4 after its upgrade 1, capped at 4.0. Unpowered: the Reserve
## flywheel holds the last m for 10 s, the Aqueduct drive gives every idle weapon 0.25. Outside a
## wave, in a Breach and in the cool-down every station is still (m 0), perks included. The mine's
## m is shown only (it pays by P_eff, SiegeEconomy); the tar works pump is SiegeTarWorks.
##
## A weapon (ballista, onager, arrow organ):
##   - winds while powered: wind += dt x m / wind_s (the arrow organ: the next rack reloads in
##     rack_s x 3 / racks); an unpowered weapon keeps its winding and stops winding;
##   - picks a target every retarget_s (or when its target dies or leaves the band): the live
##     enemy in its range band with the highest preference (stations.json "prefer" per type),
##     nearest the gate on ties (the onager: the most HP inside its splash); it keeps its target
##     unless a better-preferred type is in range;
##   - turns toward the lead-predicted aim point at slew_dps while powered;
##   - fires when wound and aligned within align_deg (2): SiegeAim.lead solves the launch, and
##     SiegeProjectiles.fire raises the `shot` event and flies the projectiles.
## Upgrade 2 widens the band (x1.25) and lifts the stone's and arrows' top speed (v_max_upgraded)
## so the far edge can be reached; upgrade 3: the ballista's iron head ignores armour, the onager's
## splash grows to 6.5 m, the arrow organ gets a fourth rack.


static func step(
	state: SiegeState, tb: SiegeCombatTable, dt: float, events: Array[Dictionary]
) -> void:
	var mine := state.station(SiegeIds.STATION_MINE)
	mine.level = state.mine_level
	mine.m = 0.0
	if tb.live:
		mine.m = output(state, tb, mine, dt, false)
	elif state.shop_open() and state.breach_s <= 0.0:
		mine.m = break_output(state, tb)
	mine.arm = fmod(mine.arm + dt * mine.m, 1.0)
	for id in SiegeIds.WEAPONS:
		_weapon(state, tb, state.station(id), dt, events)


## The mine's m in a break, when every delivering rider's output goes to it (brief 2.4): the
## sum of their P_eff / 250 W, capped. Shown only; SiegeEconomy pays by P_eff.
static func break_output(state: SiegeState, tb: SiegeCombatTable) -> float:
	var sum := 0.0
	for r in state.riders:
		if r.delivering():
			sum += maxf(r.p_eff_w, 0.0)
	return minf(sum / tb.ref_w, tb.m_cap)


## The output multiplier m of station `st` this tick (also keeps the Reserve flywheel's hold).
## `weapon`: the Aqueduct drive applies.
static func output(
	state: SiegeState, tb: SiegeCombatTable, st: SiegeStationState, dt: float, weapon: bool
) -> float:
	var sum := 0.0
	for r in state.riders:
		if r.target == st.id and r.delivering():
			sum += maxf(r.p_eff_w, 0.0) * SiegeOverdrive.multiplier(state, r, r.raw_w)
	if sum > 0.0:
		var m := sum / tb.ref_w
		if st.level >= 1 and st.id != SiegeIds.STATION_MINE:
			m *= tb.out_mult
		m = minf(m, tb.m_cap)
		if tb.reserve:
			st.hold_m = m
			st.hold_s = tb.hold_s
		return m
	if tb.reserve and st.hold_s > 0.0:
		st.hold_s = maxf(snappedf(st.hold_s - dt, 0.001), 0.0)
		return st.hold_m
	if tb.aqueduct and weapon:
		return tb.aq_m
	return 0.0


## Seconds a full winding takes at m = 1 (the arrow organ: one rack's reload).
static func wind_time(state: SiegeState, st: SiegeStationState) -> float:
	var def := state.content.station_def(st.id)
	if st.id == SiegeIds.STATION_ARROWS:
		return float(def.get("rack_s", 1.5)) * float(def.get("racks", 3)) / float(racks(state, st))
	return float(def.get("wind_s", 5.0))


## The arrow organ's racks (3, or 4 after upgrade 3).
static func racks(state: SiegeState, st: SiegeStationState) -> int:
	var def := state.content.station_def(SiegeIds.STATION_ARROWS)
	return int(def.get("special_racks" if st.level >= 3 else "racks", 3))


## The aim spec SiegeAim.lead uses for weapon `id` at its level.
static func aim_spec(state: SiegeState, id: int) -> Dictionary:
	var def := state.content.station_def(id)
	var spec := def.duplicate()
	if state.station(id).level >= 2 and def.has("v_max_upgraded"):
		spec["v_max"] = def["v_max_upgraded"]
	if id == SiegeIds.STATION_ARROWS:
		spec["fallback"] = true
	return spec


static func _weapon(
	state: SiegeState,
	tb: SiegeCombatTable,
	st: SiegeStationState,
	dt: float,
	events: Array[Dictionary]
) -> void:
	if not tb.live:
		st.m = 0.0
		st.hold_s = 0.0
		st.target_id = 0
		return
	st.m = output(state, tb, st, dt, true)
	if st.m <= 0.0:
		return
	var def := state.content.station_def(st.id)
	st.wind = minf(st.wind + dt * st.m / wind_time(state, st), 1.0)
	st.arm = st.wind
	var e := _target(state, tb, st, def, dt)
	if e == null:
		return
	var path := state.path
	var pivot := path.station_pos[st.id]
	var dz := float(def.get("aim_dz_m", 0.0))
	var want := SiegePath.yaw_to(pivot, SiegeAim.aim_point(path, e, st.flight_s, dz))
	var diff := wrapf(want - st.yaw_deg, -180.0, 180.0)
	var turn := float(def.get("slew_dps", 10.0)) * dt
	st.yaw_deg = wrapf(st.yaw_deg + clampf(diff, -turn, turn), -180.0, 180.0)
	var align := state.content.st_num("align_deg", 2.0)
	if st.wind < 1.0 - 1e-9 or absf(wrapf(want - st.yaw_deg, -180.0, 180.0)) > align:
		return
	var spec := aim_spec(state, st.id)
	var rounds := int(state.content.st_num("lead_rounds", 3))
	var sol := SiegeAim.lead(
		path, pivot, path.station_muzzle_m[st.id], e, spec, st.flight_s, rounds
	)
	if sol.is_empty():
		st.target_id = 0
		st.retarget_s = 0.0
		st.skip_id = e.id
		return
	st.skip_id = 0
	st.yaw_deg = float(sol["yaw"])
	st.flight_s = float(sol["t"])
	st.wind = 0.0
	st.arm = 0.0
	var n := 1
	if st.id == SiegeIds.STATION_ARROWS:
		n = int(def.get("per_rack", 12))
		st.rack = (st.rack + 1) % racks(state, st)
	SiegeProjectiles.fire(state, tb, st.id, sol, n, e.id, events)


## The station's target now: the current one while it is alive, in the band and not outranked;
## otherwise a fresh pick (every retarget_s). Null when nothing is in range.
static func _target(
	state: SiegeState, tb: SiegeCombatTable, st: SiegeStationState, def: Dictionary, dt: float
) -> SiegeEnemyState:
	st.retarget_s -= dt
	var cur := state.enemy(st.target_id)
	if cur != null and (not cur.alive() or not state.in_band(st.id, cur.pos)):
		cur = null
	if cur != null and st.retarget_s > 0.0:
		return cur
	st.retarget_s = state.content.st_num("retarget_s", 1.0)
	var best := pick(state, tb, st.id, def)
	var pref: Dictionary = def.get("prefer", {})
	if cur != null and (best == null or _pref(pref, cur.type) >= _pref(pref, best.type)):
		best = cur
	st.target_id = best.id if best != null else 0
	return best


## The best target for weapon `id` now (see the class notes), or null.
static func pick(
	state: SiegeState, tb: SiegeCombatTable, id: int, def: Dictionary
) -> SiegeEnemyState:
	var pref: Dictionary = def.get("prefer", {})
	var splash := float(def.get("splash_m", 0.0)) if id == SiegeIds.STATION_ONAGER else 0.0
	var skip := state.station(id).skip_id
	var best: SiegeEnemyState = null
	var best_score := -INF
	for e in state.enemies:
		if not e.alive() or e.id == skip or not state.in_band(id, e.pos):
			continue
		var score := _pref(pref, e.type) * 1000.0
		if splash > 0.0:
			var cluster := 0.0
			for o in tb.near(state.enemies, e.pos.x, e.pos.y, splash):
				cluster += o.hp
			score += minf(cluster, 999.0)
		else:
			score += e.prog_m
		if score > best_score:
			best = e
			best_score = score
	return best


static func _pref(pref: Dictionary, type: int) -> float:
	return float(pref.get(SiegeIds.ENEMY_NAMES[type], 1.0))

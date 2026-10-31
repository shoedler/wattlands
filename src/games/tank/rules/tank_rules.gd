class_name TankRules
extends RefCounted
## Pure, deterministic rules (BRIEF 3.6; brief 2.4): step(state, inputs, dt) reads only its
## arguments and draws randomness only from state.rng (ctx.rng). Owner: rules.
##
## One tick, in this order: follow the group's phase and set a new segment up (TankSegments), seat
## the riders (TankSeats: seat intents, moves land at once), read the riders (who can evade,
## who sprints), spawn the Advance's encounters, drive (TankDrive: speed model, obstacles), move the
## enemies and the Behemoth (its telegraph and main gun through TankEvade), rebuild the target
## list, run the seats' machines (TankStations: the Gun's bank, the Loader's rack, the Lights), the
## main gun (TankGun: chambering from the rack, laying, firing), the bow guns (TankBow: the
## Secondaries seat's rounds), the enemies' guns (telegraphs through TankEvade), the shells in
## flight (TankShells), the repair and the berm (TankHullRules) and the objectives. v3: an empty
## seat does nothing (no power: no drive, gun, reloads, searchlights or bow guns). Events come
## back in that order. Everything is split by topic over rules/ and combat/; the signatures here
## (new_state, step, in_band) are the module's contract. Free roam (brief 2.10, TankRoam) adds its
## turn, time up, strongpoints and patrols before the drive, and its points, engagement halt and
## time-up finish at the end. v4: a lost tank's tow counts down right after the riders are read; when
## it ends the stage restarts (TankEncounters.restart), the plan's phase and clock untouched.


## A fresh state (TankState.create) for `players` (ctx.players order) on `mission`, with the
## Loader's ready rack holding tanks.json steam.rack_start heavy shells.
static func new_state(
	content: TankContent, players: Array[PlayerSlot], mission: String, rng: RandomNumberGenerator
) -> TankState:
	var s := TankState.create(content, players, mission, rng)
	TankStations.fill_rack(s, int(content.num("tanks", "steam.rack_start", 0.0)))
	TankRoam.prepare(s)
	return s


## Advances the state by dt (always Wl.SIM_DT); returns the events raised (TankEvents), in order.
static func step(state: TankState, inputs: TankInputs, dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	state.tick = inputs.tick
	state.t = inputs.t
	if state.content == null:
		return events
	var aux := TankAux.of(state)
	aux.aim_valid = false
	TankSegments.track(state, inputs, aux, events)
	TankSeats.step(state, inputs, events)
	_update_riders(state, inputs, dt)
	state.hull.breech_s = maxf(state.hull.breech_s - dt, 0.0)
	if state.hull.tow_s > 0.0:
		state.hull.tow_s = maxf(state.hull.tow_s - dt, 0.0)
		if state.hull.tow_s <= 0.0:
			TankEncounters.restart(state, aux, events)
	TankRoam.pre(state, inputs, aux, dt, events)
	TankEncounters.advance(state, aux, events)
	TankEncounters.near_step(state, aux, events)
	TankEncounters.depot_wrecks(state, aux)
	TankDrive.step(state, inputs, dt)
	TankEnemies.move(state, aux, dt, events)
	TankBoss.step(state, aux, dt, events)
	TankTargets.build(state, aux)
	TankStations.step(state, inputs, dt, events)
	TankGun.step(state, inputs, dt, events)
	TankBow.step(state, inputs, dt, events)
	TankEnemies.fire(state, aux, dt, events)
	TankShells.step(state, aux, dt, events)
	TankHullRules.repair(state, dt, events)
	TankHullRules.dig(state, inputs, dt)
	TankSegments.objectives(state, inputs)
	TankRoam.post(state, aux, events)
	return events


## The rider's in-band rule (brief 2.3 "In band"), on this tick's input. `station` is the room the
## rider works (null treated as none: never in band). Never in band on reserve or in rescue. The
## rule follows the rider's own phase kind (ADR "Plan shape details"): every WARMUP and RECOVERY
## kind (the depot, the drill's skirmish, checkpoints) is cadence >= 60 only, never a power rule.
static func in_band(state: TankState, r: TankRiderInput, station: TankStationState) -> bool:
	if station == null or r.on_reserve() or r.rescue or state.content == null:
		return false
	var c := state.content
	var seg := state.seg.seg
	if seg == TankIds.SEG_COOLDOWN or seg == TankIds.SEG_NONE:
		return false
	var kind := r.phase_kind if r.phase_kind != "" else state.seg.kind
	if kind == Wl.COOLDOWN:
		return false
	if kind == Wl.WARMUP or kind == Wl.RECOVERY:
		return r.cadence_rpm >= c.num("tanks", "in_band.recovery_cadence_rpm", 60.0)
	# 0.3.1: while the rider's trainer still rides another seat's mode (its switch waits, BRIEF 4.5),
	# the seat works from the rider's power against its own band: an ERG seat at 95% of its planned
	# target (the unverified factor included), a SIM seat by the SIM rules below.
	var seat_mode := TankSeats.seat_mode(state, station.engine)
	if seat_mode != "" and r.phase_mode != "" and seat_mode != r.phase_mode:
		if seat_mode == Wl.ERG:
			var pct := TankSeatPlan.seat_target_pct(c, state.seg.segment_index, station.engine)
			var want_w := pct / 100.0 * r.ftp * (1.0 if r.ftp_verified else 0.85)
			return (
				want_w > 0.0
				and r.power_w >= c.num("tanks", "in_band.erg_power_frac", 0.95) * want_w
				and r.cadence_rpm >= c.num("tanks", "in_band.erg_cadence_rpm", 60.0)
			)
	elif r.mode == Wl.ERG:
		return (
			r.applied_target_w > 0.0
			and r.power_w >= c.num("tanks", "in_band.erg_power_frac", 0.95) * r.applied_target_w
			and r.cadence_rpm >= c.num("tanks", "in_band.erg_cadence_rpm", 60.0)
		)
	if station is TankSteamState:
		var steam := station as TankSteamState
		if steam.loaded or steam.cycling:
			return r.cadence_rpm >= c.num("tanks", "in_band.steam_cycle_cadence_rpm", 50.0)
		return TankConst.steam_building(r.power_w, r.ftp)
	var band: Array = c.value("tanks", "in_band.sim_ftp_pct", [76, 105])
	return r.ftp_pct >= float(band[0]) and r.ftp_pct <= float(band[1])


## The rider's current effort target in % FTP (TankRiderState.target_pct, v2), the denominator of
## the HUD's and the view's power ratio: the applied ERG target when the telemetry carries one (the
## governor's, rescue and the unverified factor included), else the phase's planned ERG target,
## else in SIM the seat's band centre (brief 2.3 In band): WARMUP-kind phases tanks.json
## power_ratio.warmup_sim_pct; the Loader loading TankConst.STEAM_BUILD_PCT, idle (v3: the rack
## full) power_ratio.steam_loaded_pct; Drive, Secondaries and the rest the middle of
## in_band.sim_ftp_pct (90.5). 0 when the rider has no phase (neither mode known).
static func target_pct(state: TankState, r: TankRiderInput, station: TankStationState) -> float:
	if r.mode == Wl.ERG and r.applied_target_w > 0.0:
		return r.applied_pct()
	if r.phase_mode == Wl.ERG and r.planned_pct > 0.0:
		return r.planned_pct
	if r.phase_mode != Wl.SIM and r.mode != Wl.SIM:
		return 0.0
	var c := state.content
	if r.in_warmup():
		return c.num("tanks", "power_ratio.warmup_sim_pct", 60.0) if c != null else 60.0
	if station is TankSteamState:
		var steam := station as TankSteamState
		if steam.loaded or steam.cycling:
			return c.num("tanks", "power_ratio.steam_loaded_pct", 60.0) if c != null else 60.0
		return TankConst.STEAM_BUILD_PCT
	var band: Array = c.value("tanks", "in_band.sim_ftp_pct", [76, 105]) if c != null else [76, 105]
	return (float(band[0]) + float(band[1])) / 2.0


static func _update_riders(state: TankState, inputs: TankInputs, dt: float) -> void:
	var reserve_w := 60.0
	if state.content != null:
		reserve_w = state.content.num("tanks", "in_band.reserve_p_eff_w", 60.0)
	state.all_afk = not inputs.riders.is_empty()
	for ri in inputs.riders:
		if not ri.on_reserve():
			state.all_afk = false
	for st in state.stations:
		# An empty seat has no power (v3): nothing runs on it.
		st.p_eff_w = 0.0
		st.in_band = false
		st.reserve = false
		st.unpowered = state.all_afk
	for ri in inputs.riders:
		var r := state.rider(ri.peer)
		if r == null:
			continue
		var st := state.station_of(r.slot)
		r.raw_w = ri.power_w
		r.cadence_rpm = ri.cadence_rpm
		r.ftp_pct = ri.ftp_pct
		r.target_pct = target_pct(state, ri, st)
		r.rescue = ri.rescue
		r.afk = ri.afk
		r.connected = ri.connected
		r.in_band = in_band(state, ri, st)
		var rule := r.sprint_rule(state.content.num("tanks", "evade.sprint_window_s", 3.0))
		rule.update(state.t, ri.power_w)
		r.sprinting = rule.holds()
		r.can_evade = TankEvade.can_evade(state, ri)
		if not r.is_bot and not r.autopilot:
			for n in ri.intents:
				if TankIntents.is_deliberate(n):
					r.fallback = false
		if st != null:
			st.reserve = ri.on_reserve()
			st.in_band = r.in_band
			st.unpowered = state.all_afk
			st.p_eff_w = 0.0 if state.all_afk else (reserve_w if st.reserve else ri.p_eff_w)
			r.engine_s[TankRiderState.ENGINE_INDEX.get(st.engine, 0)] += dt
		if state.seg.kind == Wl.WORK:
			r.work_s += dt
			if r.in_band:
				r.band_s += dt

class_name SiegeRules
extends RefCounted
## Castellum Rotae's pure rules (brief 2.4): step(state, inputs, dt) at dt 0.05 s, reading only
## its arguments (state.rng is the only randomness; no clock).
##
## step() order (SiegeOverdrive and the module rely on 2 and 4):
##   1. tick, t; each rider's telemetry, rescue, afk and connected from inputs (slot order); a
##      rescue or AFK that starts ends a running Overdrive (SiegeOverdrive.cancel).
##   2. A new phase index: close the old phase (wave_end for a wave; drop the queue; enemies
##      retreat; projectiles in flight are dropped; SiegeOverdrive.cancel(END_PHASE) for running
##      Overdrives; Autopilot's per-break buys reset), open the new one (wave_start for a wave,
##      with its budget B and its siege engines; the stations' wave damage restarts); after the
##      shift's last wave, state.done = true (the module emits finished("complete")).
##   3. Intents in slot order, each rider's in arrival order: route (SiegeRouting), buy
##      (SiegeShop), overdrive (SiegeOverdrive.try_start).
##   4. Autopilot for riders in a fallback: route once a second in slot order; shop picks in
##      breaks (<= 2 per break).
##   5. Mine pay, wave-time stats, then SiegeCombat.step (spawns, movement, the tar works,
##      station output m with SiegeOverdrive.multiplier, aim and fire, pads, projectiles, gate,
##      Breach).
##   6. SiegeOverdrive.step_rider and od_prompt per rider, reconnect timers, the team watts mean.
##   7. Return the events in emission order (SiegeEvents dictionaries).
##
## Routing and the shop are separate files (SiegeRouting, SiegeShop); the economy is
## SiegeEconomy; combat is src/games/siege/combat/. A rider's reconnect timer runs down at the
## end of the tick, so a route intent gives exactly reconnect_s (2 s = 40 ticks) without output.


## The session's starting state (SiegeState.create).
static func new_state(
	content: SiegeContent,
	slots: Array[PlayerSlot],
	scaling_mode: String,
	rng: RandomNumberGenerator
) -> SiegeState:
	return SiegeState.create(content, slots, scaling_mode, rng)


## Advances `state` by `dt` (always Wl.SIM_DT); returns the events raised, in order.
static func step(state: SiegeState, inputs: SiegeInputs, dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	state.tick = inputs.tick
	state.t = inputs.t
	_sync(state, inputs, events)
	events.append_array(_phase(state, inputs))
	_intents(state, inputs, events)
	SiegeRouting.autopilot(state, inputs, events)
	SiegeShop.autopilot(state, inputs, events)
	_economy(state, inputs, dt)
	events.append_array(SiegeCombat.step(state, inputs, dt))
	_finish(state, inputs, dt, events)
	return events


## A slot's planned P_eff in watts at `pct` % FTP (brief 2.4): pct x FTP x u x r, with u = 0.85
## while unverified and r = 250 / FTP (FAIR_FTP), 1 (RAW) or the rider's latest P_eff / power
## (WKG). No weight is ever read.
static func planned_p_eff_w(state: SiegeState, r: SiegeRiderState, pct: float) -> float:
	var u := 1.0 if r.ftp_verified else state.content.num("unverified_factor", 0.85)
	var rf := 1.0
	match state.scaling_mode:
		Wl.FAIR_FTP:
			rf = state.content.num("ref_w", 250.0) / maxf(r.ftp, 1.0)
		Wl.WKG:
			rf = r.r_wkg
	return pct / 100.0 * r.ftp * u * rf


## The wave's threat budget B (brief 2.4): c_budget x sum(planned P_eff / 250 W) x (wave_s - 60)
## / 60, from each rider's mean planned target in the phase, times the shift's budget_factor.
static func budget(state: SiegeState, inputs: SiegeInputs) -> float:
	var sum := 0.0
	for inp in inputs.riders:
		var r := state.rider(inp.peer)
		if r != null:
			sum += (
				planned_p_eff_w(state, r, inp.phase_mean_pct)
				/ state.content.num("budget_ref_w", 250.0)
			)
	var span := maxf(
		inputs.phase.duration_s - float(state.content.waves.get("stop_before_end_s", 60.0)), 0.0
	)
	return state.content.num("c_budget", 10.0) * budget_factor(state.content) * sum * span / 60.0


## The shift's own factor on B (waves.json budget_factor[<content id>], 1 when absent; ADR
## "endurance budget factor").
static func budget_factor(content: SiegeContent) -> float:
	var f: Variant = (content.waves.get("budget_factor", {}) as Dictionary).get(content.shift_id)
	return float(f) if (f is float or f is int) and float(f) > 0.0 else 1.0


## Step 1: telemetry and safety flags.
static func _sync(state: SiegeState, inputs: SiegeInputs, events: Array[Dictionary]) -> void:
	var min_w := state.content.num("wkg_min_power_w", 50.0)
	for inp in inputs.riders:
		var r := state.rider(inp.peer)
		if r == null:
			continue
		if (
			r.od_state == SiegeIds.OD_ACTIVE
			and ((inp.rescue and not r.rescue) or (inp.afk and not r.afk))
		):
			events.append_array(
				SiegeOverdrive.cancel(
					state, r, SiegeOverdrive.END_RESCUE if inp.rescue else SiegeOverdrive.END_AFK
				)
			)
		r.p_eff_w = inp.p_eff_w
		r.raw_w = inp.power_w
		r.cadence_rpm = inp.cadence_rpm
		r.rescue = inp.rescue
		r.afk = inp.afk
		r.connected = inp.connected
		if inp.power_w >= min_w and inp.power_w > 0.0:
			r.r_wkg = inp.p_eff_w / inp.power_w


## Step 2: a new phase closes the old one and opens the next.
static func _phase(state: SiegeState, inputs: SiegeInputs) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ph := inputs.phase
	if ph.index != state.phase_index:
		if state.in_wave():
			if state.role == SiegeIds.ROLE_WAVE:
				state.wave_gate_hp.append(ceili(state.gate_hp))
				state.wave_gate_frac.append(state.gate_hp / maxf(state.gate_max, 1.0))
			events.append(
				SiegeEvents.wave_end(
					state.phase_index,
					state.wave_no,
					state.gate_hp,
					state.gate_max,
					state.wave.leaks
				)
			)
			if state.role == SiegeIds.ROLE_WAVE and state.wave_no >= state.waves_total:
				state.done = true
		for r in state.riders:
			events.append_array(SiegeOverdrive.cancel(state, r, SiegeOverdrive.END_PHASE))
			r.ap_buys = 0
		_retreat_all(state)
		state.phase_index = ph.index
		state.role = ph.role
		state.wave_no = ph.number
		state.phase_kind = ph.kind
		state.wave = SiegeWaveState.new()
		if ph.is_wave():
			state.wave.budget = budget(state, inputs)
			if ph.role == SiegeIds.ROLE_WARMUP_WAVE:
				state.wave.budget *= SiegeTune.wave_num(state.content, "warmup.budget_frac", 0.4)
			state.wave.budget_left = state.wave.budget
			for st in state.stations:
				st.damage_wave = 0.0
			SiegeSpawner.begin_wave(state, ph)
			events.append(
				SiegeEvents.wave_start(ph.index, ph.role, ph.number, ph.waves, state.wave.budget)
			)
	state.phase_elapsed_s = ph.elapsed_s
	state.phase_duration_s = ph.duration_s
	state.phase_remaining_s = ph.remaining_s
	return events


## A phase ends: the queue and the projectiles in flight are dropped and every live enemy
## retreats for retreat_s, then vanishes without bounty or damage (a docked tower's boarders
## leave with it).
static func _retreat_all(state: SiegeState) -> void:
	state.queue.clear()
	SiegeProjectiles.clear(state)
	var secs := float(state.content.enemies.get("retreat_s", 3.0))
	for e in state.enemies:
		if e.st != SiegeIds.EN_RETREAT:
			e.st = SiegeIds.EN_RETREAT
			e.retreat_s = secs
	state.tar.boarded = false
	for st in state.stations:
		st.target_id = 0


## Step 3: intents in slot order, each rider's in arrival order.
static func _intents(state: SiegeState, inputs: SiegeInputs, events: Array[Dictionary]) -> void:
	for inp in inputs.riders:
		var r := state.rider(inp.peer)
		if r == null:
			continue
		for it in inp.intents:
			match str(it.get("k", "")):
				SiegeIds.INTENT_ROUTE:
					SiegeRouting.intent(state, r, it, events)
				SiegeIds.INTENT_BUY:
					SiegeShop.intent(state, r, it, events)
				SiegeIds.INTENT_OVERDRIVE:
					SiegeOverdrive.try_start(state, r, inputs.phase, it)


## Step 5a: the mine pays riders whose output reaches it (all output goes there in breaks;
## nothing in a Breach), the planned kJ for par, and the wave time per station.
static func _economy(state: SiegeState, inputs: SiegeInputs, dt: float) -> void:
	var rate := SiegeEconomy.mine_rate(state)
	var counting := not inputs.phase.is_cooldown() and inputs.phase.index >= 0 and not state.done
	var wave := state.in_wave() and not inputs.phase.is_cooldown()
	for inp in inputs.riders:
		var r := state.rider(inp.peer)
		if r == null:
			continue
		if counting:
			state.planned_kj += planned_p_eff_w(state, r, inp.planned_pct) * dt / 1000.0
		if not r.delivering():
			continue
		var to_mine := r.target == SiegeIds.STATION_MINE or not wave
		if wave:
			r.station_s[r.target] += dt
			if to_mine:
				r.wave_mine_s += dt
			else:
				r.wave_weapon_s += dt
		if counting and to_mine and state.breach_s <= 0.0:
			SiegeEconomy.pay_mine(state, r, inp.p_eff_w, dt, rate)


## Step 6: Overdrive clocks and prompt, reconnect timers and the team watts' 1 s mean.
static func _finish(
	state: SiegeState, inputs: SiegeInputs, dt: float, events: Array[Dictionary]
) -> void:
	var team := 0.0
	for inp in inputs.riders:
		var r := state.rider(inp.peer)
		if r == null:
			continue
		events.append_array(SiegeOverdrive.step_rider(state, r, inp.power_w, dt))
		r.od_prompt = SiegeOverdrive.prompt(state, r, inputs.phase)
		r.reconnect_s = maxf(snappedf(r.reconnect_s - dt, 0.001), 0.0)
		if r.connected and not r.afk:
			team += inp.power_w
	state.team_w_window.append(team)
	while state.team_w_window.size() > Wl.SIM_HZ:
		state.team_w_window.pop_front()
	var sum := 0.0
	for w in state.team_w_window:
		sum += w
	state.team_w = sum / state.team_w_window.size()

class_name SiegeRules
extends RefCounted
## Generator Siege's pure rules (brief 2.4): step(state, inputs, dt) at dt 0.05 s, reading only
## its arguments (state.rng is the only randomness; no clock). Owner: B1 "rules".
##
## G0 status: a minimal, correct skeleton (phase roles and wave events, the generator economy,
## the budget's planned P_eff, the team watts mean, Overdrive wiring, the end of the shift).
## B1 completes routing, the shop, the gate and Breach, combat (SiegeCombat), Autopilot calls
## (SiegeAutopilot, B2) and the zero-input fallback, keeping these signatures.
##
## step() order (B1 keeps it; SiegeOverdrive and the module rely on 2 and 4):
##   1. tick, t; each rider's telemetry, rescue, afk and connected from inputs (slot order).
##   2. A new phase index: close the old phase (wave_end for a wave; drop the queue; enemies
##      retreat; SiegeOverdrive.cancel(END_PHASE) for running Overdrives; Autopilot's per-break
##      buys reset), open the new one (wave_start for a wave, with its budget B); after the
##      shift's last wave, state.done = true (the module emits finished("complete")).
##   3. Rescue / AFK starting while an Overdrive runs: SiegeOverdrive.cancel(END_RESCUE/END_AFK).
##   4. Intents in slot order, each rider's in arrival order: route, buy, overdrive
##      (SiegeOverdrive.try_start; at most one start per rider per tick).
##   5. Autopilot for riders in a fallback (route once a second in slot order; shop picks in
##      breaks, <= 2 per break).
##   6. Reconnect timers, generator pay, tower output m (with SiegeOverdrive.multiplier), combat
##      (spawns, movement, fire, zones, gate, Breach), SiegeOverdrive.step_rider and od_prompt,
##      stats (wave time per target, planned kJ, team watts).
##   7. Return the events in emission order (SiegeEvents dictionaries).


## The session's starting state (SiegeState.create; B1 may add to it).
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
		if inp.power_w >= state.content.num("wkg_min_power_w", 50.0) and inp.power_w > 0.0:
			r.r_wkg = inp.p_eff_w / inp.power_w
	events.append_array(_phase(state, inputs))
	for inp in inputs.riders:
		var r := state.rider(inp.peer)
		if r == null:
			continue
		for it in inp.intents:
			if str(it.get("k", "")) == SiegeIds.INTENT_OVERDRIVE:
				SiegeOverdrive.try_start(state, r, inputs.phase, it)
	_economy(state, inputs, dt)
	events.append_array(SiegeCombat.step(state, inputs, dt))
	for inp in inputs.riders:
		var r := state.rider(inp.peer)
		if r == null:
			continue
		events.append_array(SiegeOverdrive.step_rider(state, r, inp.power_w, dt))
		r.od_prompt = SiegeOverdrive.prompt(state, r, inputs.phase)
	return events


## A slot's planned P_eff in watts at `pct` % FTP (brief 2.4): pct x FTP x u x r, with u = 0.85
## while unverified and r = 250 / FTP (FAIR_FTP), 1 (RAW) or the rider's latest P_eff / power
## (WKG). No weight is ever read.
static func planned_p_eff_w(state: SiegeState, r: SiegeRiderState, pct: float) -> float:
	var u := 1.0 if r.ftp_verified else state.content.num("unverified_factor", 0.85)
	var rf := 1.0
	match state.scaling_mode:
		Wl.FAIR_FTP:
			rf = state.content.num("tower_ref_w", 250.0) / maxf(r.ftp, 1.0)
		Wl.WKG:
			rf = r.r_wkg
	return pct / 100.0 * r.ftp * u * rf


## The wave's threat budget B (brief 2.4): c_budget x sum(planned P_eff / 250 W) x (wave_s - 60)
## / 60, from each rider's mean planned target in the phase.
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
	return state.content.num("c_budget", 10.0) * sum * span / 60.0


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
		state.queue.clear()
		state.phase_index = ph.index
		state.role = ph.role
		state.wave_no = ph.number
		state.phase_kind = ph.kind
		state.wave = SiegeWaveState.new()
		if ph.is_wave():
			state.wave.budget = budget(state, inputs)
			if ph.role == SiegeIds.ROLE_WARMUP_WAVE:
				state.wave.budget *= float(
					(state.content.waves.get("warmup", {}) as Dictionary).get("budget_frac", 0.4)
				)
			state.wave.budget_left = state.wave.budget
			var n := mini(SiegeIds.ROAD_COUNT, state.riders.size())
			for i in n:
				state.wave.active_roads.append(i if n == SiegeIds.ROAD_COUNT else [1, 0, 2][i])
			events.append(
				SiegeEvents.wave_start(
					ph.index,
					ph.role,
					ph.number,
					ph.waves,
					state.wave.budget,
					state.wave.active_roads
				)
			)
	state.phase_elapsed_s = ph.elapsed_s
	state.phase_duration_s = ph.duration_s
	state.phase_remaining_s = ph.remaining_s
	return events


static func _economy(state: SiegeState, inputs: SiegeInputs, dt: float) -> void:
	var mult := (
		state.content.num("generator.denarii_per_kj", 1.0)
		* (1.0 + state.content.num("generator.level_bonus", 0.2) * state.gen_level)
	)
	var counting := not inputs.phase.is_cooldown() and inputs.phase.index >= 0 and not state.done
	var team := 0.0
	for inp in inputs.riders:
		var r := state.rider(inp.peer)
		if r == null:
			continue
		team += inp.power_w if r.delivering() else 0.0
		if counting:
			state.planned_kj += planned_p_eff_w(state, r, inp.planned_pct) * dt / 1000.0
		var to_gen := r.target == SiegeIds.TARGET_GEN or not inputs.phase.is_wave()
		if counting and r.delivering() and to_gen:
			var pay := maxf(inp.p_eff_w, 0.0) * dt / 1000.0 * mult
			r.denarii += pay
			r.gen_denarii += pay
			state.team_earned += pay
	state.team_w_window.append(team)
	while state.team_w_window.size() > Wl.SIM_HZ:
		state.team_w_window.pop_front()
	var sum := 0.0
	for w in state.team_w_window:
		sum += w
	state.team_w = sum / state.team_w_window.size()

class_name TankHudModel
extends RefCounted
## What the Tank Controls show, as plain data computed from TankGame.state (pure and static, so
## tests read it without drawing): the station card of the local rider's engine (diesel speed,
## distance to the halt line and berm; dynamo bank, target and elevation; steam dial with the
## 40 / 100 / 150% marks and the loaded shell; Bulwark lever with its auto marker and hoist
## progress), the objective line ("Gun line 2/4") and the boss bars. It only reads the state.

const STEAM_MARKS: Array[float] = [40.0, 100.0, 150.0]
const STEAM_DIAL_MAX := 150.0
const DEFAULT_BERM_MAX := 40.0
const DEFAULT_HOIST_J := 4000.0
const RAM_WINDOW_S := 10.0
const RAM_COOLDOWN_S := 30.0
const OVERPRESSURE_WINDOW_S := 5.0
## Shell type -> its name key.
const SHELL_KEYS := {
	TankIds.SHELL_LIGHT: "TANK_SHELL_LIGHT",
	TankIds.SHELL_HEAVY: "TANK_SHELL_HEAVY",
	TankIds.SHELL_OVER: "TANK_SHELL_OVER",
	TankIds.SHELL_BOW: "TANK_SHELL_SECONDARY",
}


## The station card of `peer`: {"kind": engine or "none", ...} (keys per engine, see below).
static func card(state: TankState, peer: int) -> Dictionary:
	var r := state.rider(peer)
	if r == null or r.engine == "":
		return {"kind": "none"}
	var st := state.station(r.engine)
	if st == null:
		return {"kind": "none"}
	var out := {"kind": r.engine, "reserve": st.reserve, "unpowered": st.unpowered or state.all_afk}
	match r.engine:
		TankIds.ENGINE_DIESEL:
			out.merge(_drive(state, st as TankDieselState, r))
		TankIds.ENGINE_BULWARK:
			out.merge(_drive(state, st as TankDieselState, r))
			out.merge(_gearbox(state, st as TankGearboxState))
		TankIds.ENGINE_DYNAMO:
			out.merge(_dynamo(state, st as TankDynamoState))
		TankIds.ENGINE_STEAM:
			out.merge(_steam(state, st as TankSteamState))
	return out


## Speed, distance to the halt line, berm and Ram of the driver (diesel and Bulwark).
static func _drive(state: TankState, st: TankDieselState, r: TankRiderState) -> Dictionary:
	var hl := state.hull
	var berm_max := (
		state.content.num("tanks", "berm.max_hp", DEFAULT_BERM_MAX)
		if state.content != null
		else DEFAULT_BERM_MAX
	)
	return {
		"speed_kmh": hl.speed_mps * 3.6,
		"halt_m": halt_distance_m(state),
		"berm": hl.berm_hp,
		"berm_max": berm_max,
		"show_berm": state.gun_line.active,
		"ram_ok": ability_ok(state, r),
		"dodge": state.seg.seg == TankIds.SEG_BOSS,
		"ram_s": st.ram_s,
		"ram_cd_s": st.ram_cd_s,
		"ram_frac": clampf(st.ram_s / RAM_WINDOW_S, 0.0, 1.0),
		"ram_cd_frac": clampf(st.ram_cd_s / RAM_COOLDOWN_S, 0.0, 1.0),
		"sprinting": st.sprinting,
		"stalled": hl.stall_s > 0.0,
		"holding": hl.holding,
	}


## Whether the Ram (the dodge at the boss) can work for `r` now, from the replicated state only:
## a WORK phase that is an Advance or the boss (the SIM phases; a gun line, a checkpoint and the
## depot are ERG or WARMUP), past the first 300 s of the plan, the tank running and the rider
## pedalling. This is TankDrive.ability_ok as far as a client can see it: PhaseState lives on the
## host, so a client reads the plan clock as the game clock when the host's value is not in the
## state (they differ only when a plan starts late).
static func ability_ok(state: TankState, r: TankRiderState) -> bool:
	if state == null or r == null or state.seg.kind != Wl.WORK:
		return false
	if state.seg.seg != TankIds.SEG_ADVANCE and state.seg.seg != TankIds.SEG_BOSS:
		return false
	if state.hull.breakdown or state.all_afk or r.afk or r.rescue or not r.connected:
		return false
	var plan_s := state.seg.plan_elapsed_s if state.seg.plan_elapsed_s > 0.0 else state.t
	return not TankConst.in_first_window(plan_s)


## The Bulwark's lever, its auto marker and the hoist's progress toward a heavy shell.
static func _gearbox(state: TankState, g: TankGearboxState) -> Dictionary:
	var hoist_j := (
		state.content.num("tanks", "gearbox.hoist_j", DEFAULT_HOIST_J)
		if state.content != null
		else DEFAULT_HOIST_J
	)
	return {
		"lever": g.lever,
		"lever_to": g.lever_to,
		"move_s": g.move_s,
		"auto": g.auto,
		"dig": state.gun_line.active,
		"hoist_frac": clampf(g.hoist_j / maxf(hoist_j, 1.0), 0.0, 1.0),
		"shell": shell_key(state.hull.loaded),
	}


static func _dynamo(state: TankState, d: TankDynamoState) -> Dictionary:
	return {
		"bank": d.bank,
		"bank_frac": clampf(d.bank / 100.0, 0.0, 1.0),
		"target_pct": bank_target_pct(state, d.bank),
		"elev_deg": state.hull.elev_deg,
		"facing": state.hull.facing,
		"stalled": d.stalled,
		"stabilizing": d.stabilizing,
		"hoist_s": d.hoist_s,
		"shell": shell_key(state.hull.loaded),
	}


static func _steam(state: TankState, s: TankSteamState) -> Dictionary:
	return {
		"pressure": s.pressure_pct,
		"dial_frac": clampf(s.pressure_pct / STEAM_DIAL_MAX, 0.0, 1.0),
		"marks": STEAM_MARKS,
		"window_s": s.window_s,
		"window_frac": clampf(s.window_s / OVERPRESSURE_WINDOW_S, 0.0, 1.0),
		"over": s.over,
		"over_frac": clampf((s.pressure_pct - 100.0) / 50.0, 0.0, 1.0),
		"loaded": s.loaded,
		"cycling": s.cycling,
		"shell":
		shell_key(state.hull.loaded) if s.loaded or state.hull.loaded != TankIds.SHELL_NONE else "",
	}


## The strings key of a shell type ("" for none).
static func shell_key(shell: int) -> String:
	return str(SHELL_KEYS.get(shell, ""))


## The dynamo's ERG target in % FTP for `bank` (stations.json bank: base + span x (1 - bank / 100)),
## kept inside the plan's range for the segment's dynamo entry when there is one.
static func bank_target_pct(state: TankState, bank: float) -> float:
	var c := state.content
	var base := c.num("stations", "bank.base_pct", 55.0) if c != null else 55.0
	var span := c.num("stations", "bank.span_pct", 45.0) if c != null else 45.0
	var pct := base + span * (1.0 - clampf(bank, 0.0, 100.0) / 100.0)
	if c != null and state.seg.seg != "":
		var entry := c.plan_entry(TankIds.ENGINE_DYNAMO, state.seg.seg)
		var rng: Variant = entry.get("range_pct")
		if rng is Array and (rng as Array).size() >= 2:
			pct = clampf(pct, float(rng[0]), float(rng[1]))
	return pct


## Metres left to the halt line in an Advance (-1 elsewhere). The Advance's length comes from the
## mission (clients never get it in the snapshot); x_px == m_to_px(distance_m) during an Advance.
static func halt_distance_m(state: TankState) -> float:
	if state.seg.seg != TankIds.SEG_ADVANCE or state.content == null:
		return -1.0
	var seg := state.content.segment(state.seg.phase_index)
	var length_m := float(seg.get("length_m", 0.0))
	if length_m <= 0.0:
		return -1.0
	return maxf(length_m - state.hull.x_px / TankConst.PX_PER_M, 0.0)


## The objective line: {"key": strings key, "args": Array, "warn": bool}; {} in the cool-down.
static func objective(state: TankState) -> Dictionary:
	if state.in_cooldown() or state.seg.seg == "":
		return {}
	if state.seg.regroup:
		return {"key": "TANK_OBJ_REGROUP", "args": [], "warn": true}
	match state.seg.seg:
		TankIds.SEG_DEPOT:
			return {"key": "TANK_OBJ_DEPOT", "args": [], "warn": false}
		TankIds.SEG_ADVANCE:
			var m := halt_distance_m(state)
			return {"key": "TANK_OBJ_ADVANCE", "args": [int(ceilf(maxf(m, 0.0)))], "warn": false}
		TankIds.SEG_GUN_LINE:
			var total := state.gun_line.guns_total
			return {
				"key": "TANK_OBJ_GUN_LINE",
				"args": [clampi(total - state.gun_line.guns_left, 0, total), total],
				"warn": false
			}
		TankIds.SEG_CHECKPOINT:
			return {"key": "TANK_OBJ_CHECKPOINT", "args": [], "warn": false}
		TankIds.SEG_BOSS:
			return {"key": "TANK_OBJ_BOSS", "args": [], "warn": false}
		TankIds.SEG_SKIRMISH:
			return {"key": "TANK_OBJ_SKIRMISH", "args": [], "warn": false}
	return {}


## The boss bars: {"show": false} before the Behemoth, else the fractions of its three bogies (rear
## to front) and its turret, whether its main gun is telegraphing and its phase.
static func boss_bars(state: TankState) -> Dictionary:
	var b := state.boss
	if b.phase == TankIds.BOSS_NONE:
		return {"show": false}
	var scale_k := 1.0
	var bogie_max := b.bogie_max
	var turret_max := b.turret_max
	if state.content != null:
		scale_k = state.content.enemy_scale(state.hull.tank)
		bogie_max = float(state.content.boss_def().get("bogie_hp", 100)) * scale_k
		turret_max = float(state.content.boss_def().get("turret_hp", 300)) * scale_k
	var bogies: Array[float] = []
	for hp in b.bogie_hp:
		bogies.append(clampf(hp / maxf(bogie_max, 1.0), 0.0, 1.0))
	return {
		"show": true,
		"bogies": bogies,
		"turret": clampf(b.turret_hp / maxf(turret_max, 1.0), 0.0, 1.0),
		"telegraph": b.telegraph_s > 0.0,
		# The warning triangle blinks four times a second on game time while the gun telegraphs.
		"blink": b.telegraph_s > 0.0 and int(floorf(state.t * 4.0)) % 2 == 0,
		"phase": b.phase,
		"dead": b.phase == TankIds.BOSS_DEAD,
	}

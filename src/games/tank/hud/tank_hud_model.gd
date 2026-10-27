class_name TankHudModel
extends RefCounted
## What Diesel Domestiques' own HUD shows, as plain data computed from TankGame.state (pure and
## static, so tests read it without drawing; brief 2.3, 2.4, 3.6): the local rider's band and their
## one instruction line (HOLD / SPIN / SURGE / LATCH / RESERVE), the crew row's cards in room order,
## the telegraphing shooters, the mission plate's stage strip and objective, the halt distance and
## the boss bars. It only reads the state.

## The sprint rule's threshold (brief 2.4: >= 1.2 x FTP over the last 3 s, raw W).
const SPRINT_FTP := 1.2
## The first 300 s of the plan: no sprint prompt (brief 2.3).
const FIRST_S := 300.0
## In band for the engine windows (TankMech: 0.84-1.17 of the rider's target).
const RATIO_HI := 1.17
const RATIO_MAX := 1.6
## The target before the host has set one: the middle of the SIM band (TankMech.rider_power).
const FALLBACK_TARGET_PCT := 90.5
## The diesel's and Bulwark's SIM band in % FTP (tanks.json in_band.sim_ftp_pct).
const SIM_BAND_PCT: Array = [76.0, 105.0]
## Steam "building" at >= 90 % FTP; a loaded or cycling loader only needs cadence >= 50.
const STEAM_PCT := 90.0
const LOADER_RPM := 50.0
const DEFAULT_RPM := 60.0
## ERG riders: the display band around the applied target (in band from 95 %).
const ERG_LO := 0.95
const ERG_HI := 1.05
## Telegraph lengths when the content has none (brief 2.4: destroyer 4 s, heavy 3 s, light 2.5 s,
## the Behemoth's main gun 6 s).
const TELEGRAPH_S := {
	TankIds.ENEMY_DESTROYER: 4.0,
	TankIds.ENEMY_HEAVY: 3.0,
	TankIds.ENEMY_LIGHT: 2.5,
	"boss": 6.0,
}
## Instruction kinds.
const DO_NONE := ""
const DO_HOLD := "hold"
const DO_SPIN := "spin"
const DO_SURGE := "surge"
const DO_LATCH := "latch"
const DO_RESERVE := "reserve"
## The machine TankMech paints for each engine.
const MECH := {
	TankIds.ENGINE_DIESEL: "diesel",
	TankIds.ENGINE_BULWARK: "diesel",
	TankIds.ENGINE_DYNAMO: "dynamo",
	TankIds.ENGINE_STEAM: "steam",
	TankIds.ENGINE_ARC: "arc",
}


## The power the engine windows show for `r` at `watts` raw W: watts over the rider's target
## (1 = on target; in band 0.84-1.17): raw W / (TankRiderState.target_pct / 100 x FTP). Before the
## host has set a target (target_pct 0), the middle of the SIM tempo band (90.5 % FTP) stands in.
static func power_ratio(r: TankRiderState, watts: float) -> float:
	if r == null or r.ftp <= 0.0:
		return 0.0
	var target := r.target_pct if r.target_pct > 0.0 else FALLBACK_TARGET_PCT
	return clampf(watts / (target / 100.0 * r.ftp), 0.0, RATIO_MAX)


## -1 under the band, 0 in it, +1 over it (the crew row's strip): the rider's in-band flag first,
## else the engine ratio.
static func band_state(in_band: bool, ratio: float) -> int:
	if in_band:
		return 0
	return 1 if ratio > RATIO_HI else -1


## The crew row: one card per manned room, rear to front (state.stations order): {engine, mech,
## peer, slot, w, cad, ratio, state (band_state), in_band, local, reserve}. The local rider's
## watts and cadence come from `local` ({"w", "cad"}) when given (their own telemetry).
static func crew_cards(state: TankState, local_peer: int, local: Dictionary = {}) -> Array:
	var out: Array = []
	if state == null:
		return out
	for st in state.stations:
		var r := state.rider_at(st.slot) if st.slot >= 0 else null
		if r == null:
			continue
		var is_local := r.peer == local_peer
		var w := float(local.get("w", r.raw_w)) if is_local else r.raw_w
		var cad := float(local.get("cad", r.cadence_rpm)) if is_local else r.cadence_rpm
		var away := r.afk or not r.connected or st.reserve
		if away or state.all_afk:
			cad = 0.0
		var ratio := power_ratio(r, w)
		(
			out
			. append(
				{
					"engine": st.engine,
					"mech": str(MECH.get(st.engine, "diesel")),
					"peer": r.peer,
					"slot": r.slot,
					"w": w,
					"cad": cad,
					"ratio": ratio,
					"in_band": r.in_band,
					"state": band_state(r.in_band, ratio),
					"local": is_local,
					"reserve": away,
				}
			)
		)
	return out


## The trainer mode the plan gives `engine` in the current segment (the mission's plan entry; SIM
## for the drive and the boiler, ERG otherwise, when the entry has none).
static func plan_mode(state: TankState, engine: String) -> String:
	if state.content != null and state.seg.seg != "":
		var e := state.content.plan_entry(engine, state.seg.seg)
		if e.has("mode"):
			return str(e["mode"])
	match engine:
		TankIds.ENGINE_DIESEL, TankIds.ENGINE_BULWARK, TankIds.ENGINE_STEAM:
			return Wl.SIM
	return Wl.ERG


## Game seconds since the plan started as a client can see it (the host's plan clock when the
## state has it, else the game clock).
static func plan_s(state: TankState) -> float:
	return state.seg.plan_elapsed_s if state.seg.plan_elapsed_s > 0.0 else state.t


## Whether `r` can evade a telegraphed shot now (brief 2.4): a WORK phase in SIM (`mode`, the
## rider's trainer mode), past the first 300 s, the rider pedalling on their own station.
static func can_evade(state: TankState, r: TankRiderState, mode: String) -> bool:
	if state == null or r == null or state.seg.kind != Wl.WORK or mode != Wl.SIM:
		return false
	if state.all_afk or r.afk or r.rescue or not r.connected:
		return false
	return plan_s(state) >= FIRST_S


## Every shooter whose gun telegraphs now: [{id (the boss: 0), boss, left, total}], enemies in
## state order, then the Behemoth.
static func telegraphs(state: TankState) -> Array:
	var out: Array = []
	if state == null:
		return out
	for e in state.enemies:
		if e.mode == TankIds.EM_DEAD or e.telegraph_s <= 0.0:
			continue
		var kind := TankIds.enemy_of(e.code)
		var total := float(TELEGRAPH_S.get(kind, 3.0))
		if state.content != null:
			total = float(state.content.enemy_def(kind).get("telegraph_s", total))
		var tot := maxf(total, e.telegraph_s)
		out.append({"id": e.id, "boss": false, "left": e.telegraph_s, "total": tot})
	var b := state.boss
	var up := b.phase == TankIds.BOSS_PHASE_1 or b.phase == TankIds.BOSS_PHASE_2
	if up and b.telegraph_s > 0.0:
		var total_b := float(TELEGRAPH_S["boss"])
		if state.content != null:
			var main: Dictionary = state.content.boss_def().get("main", {})
			total_b = float(main.get("telegraph_s", total_b))
		var tot_b := maxf(total_b, b.telegraph_s)
		out.append({"id": 0, "boss": true, "left": b.telegraph_s, "total": tot_b})
	return out


## The shortest telegraph left (s; 0 when none).
static func telegraph_left(state: TankState) -> float:
	var left := 0.0
	for t: Dictionary in telegraphs(state):
		var l := float(t["left"])
		if left <= 0.0 or l < left:
			left = l
	return left


## The local rider's power band in W (x low, y high; y 0 = open-ended, "lo+"; ZERO = none) for
## their engine now (brief 2.3 In band): the published SIM band (`published`, the HudLayer's) or
## 76-105 % FTP for the drive in SIM; >= 90 % FTP for the boiler building; the applied ERG target
## (`target_w`) +/- 5 % for an ERG rider; none for a cadence-only rule (the depot, checkpoints, a
## loaded or cycling loader).
static func band_w(
	state: TankState, r: TankRiderState, mode: String, target_w: float, published: Vector2
) -> Vector2:
	if state == null or r == null or state.seg.kind != Wl.WORK:
		return Vector2.ZERO
	if mode == Wl.ERG:
		if target_w > 0.0:
			return Vector2(ERG_LO * target_w, ERG_HI * target_w)
		return Vector2.ZERO
	match r.engine:
		TankIds.ENGINE_DIESEL, TankIds.ENGINE_BULWARK:
			if published.y > 0.0:
				return published
			var b: Array = SIM_BAND_PCT
			if state.content != null:
				b = state.content.value("tanks", "in_band.sim_ftp_pct", SIM_BAND_PCT)
			return Vector2(float(b[0]) / 100.0 * r.ftp, float(b[1]) / 100.0 * r.ftp)
		TankIds.ENGINE_STEAM:
			var stm := state.station(TankIds.ENGINE_STEAM) as TankSteamState
			if stm != null and (stm.loaded or stm.cycling):
				return Vector2.ZERO
			return Vector2(STEAM_PCT / 100.0 * r.ftp, 0.0)
	return published if published.y > 0.0 else Vector2.ZERO


## The one instruction line for the local rider: {kind (DO_*), key, args, urgent, left_s}.
## `nums`: {"mode": the trainer mode, "cad": cadence, "band": band_w(), "cband": the published
## cadence band (ZERO = none)}. In order: nothing in the cool-down; RESERVE while the station runs
## on reserve; SURGE nnn+ W with the time left while the steam window is open or, for a rider who
## can evade, while a shooter telegraphs; SPIN 50+ RPM for a loaded or cycling loader; LATCH with
## the boiler at 100 % and nothing latched; SPIN nn+ RPM where the rule is cadence (the depot,
## checkpoints, an ERG rider under the cadence floor); else HOLD lo-hi W (or lo+ W).
static func instruction(state: TankState, r: TankRiderState, nums: Dictionary) -> Dictionary:
	if state == null or r == null or r.engine == "" or state.in_cooldown():
		return _line(DO_NONE, "", [], 0.0)
	var st := state.station_of(r.slot)
	if r.afk or not r.connected or (st != null and st.reserve) or state.all_afk:
		return _line(DO_RESERVE, "TANK_HUD_DO_RESERVE", [], 0.0)
	var mode := str(nums.get("mode", plan_mode(state, r.engine)))
	var sprint := str(roundi(SPRINT_FTP * r.ftp))
	var stm := st as TankSteamState
	var work := state.seg.kind == Wl.WORK
	if work and stm != null and stm.window_s > 0.0:
		return _line(DO_SURGE, "TANK_HUD_DO_SURGE", [sprint], stm.window_s)
	var left := telegraph_left(state)
	if left > 0.0 and can_evade(state, r, mode):
		return _line(DO_SURGE, "TANK_HUD_DO_SURGE", [sprint], left)
	var cb: Vector2 = nums.get("cband", Vector2.ZERO)
	var floor_rpm := str(roundi(cb.x if cb.y > 0.0 else DEFAULT_RPM))
	if work and stm != null and (stm.loaded or stm.cycling):
		var lr := str(roundi(cb.x if cb.y > 0.0 else LOADER_RPM))
		return _line(DO_SPIN, "TANK_HUD_DO_SPIN", [lr], 0.0)
	if work and stm != null and stm.pressure_pct >= 100.0 and not stm.over:
		return _line(DO_LATCH, "TANK_HUD_DO_LATCH", [], 0.0)
	var band: Vector2 = nums.get("band", Vector2.ZERO)
	var cad := float(nums.get("cad", r.cadence_rpm))
	var under_floor := mode == Wl.ERG and cad < float(floor_rpm)
	if not work or under_floor or band.x <= 0.0:
		return _line(DO_SPIN, "TANK_HUD_DO_SPIN", [floor_rpm], 0.0)
	if band.y <= 0.0:
		return _line(DO_HOLD, "TANK_HUD_DO_HOLD_MIN", [str(roundi(band.x))], 0.0)
	var lo := str(roundi(band.x))
	return _line(DO_HOLD, "TANK_HUD_DO_HOLD", [lo, str(roundi(band.y))], 0.0)


static func _line(kind: String, key: String, args: Array, left: float) -> Dictionary:
	return {"kind": kind, "key": key, "args": args, "urgent": kind == DO_SURGE, "left_s": left}


## The mission plate: {title (the segment's label key), left_s (to the nominal end, or to the
## latest end of an open-ended segment), blocks [{type, len}] (every segment by its nominal
## length), index, progress (0..1 of the nominal length), obj_key / obj_value (the gun line's
## guns, or Regroup), warn, next (the next segment's label key)}; {} without content.
static func mission(state: TankState) -> Dictionary:
	if state == null or state.content == null:
		return {}
	var i := state.seg.phase_index
	var cur := state.content.segment(i)
	var nxt := state.content.segment(i + 1)
	var blocks: Array = []
	for sg: Dictionary in state.content.segments():
		blocks.append({"type": str(sg.get("type", "")), "len": float(sg.get("duration_s", 60))})
	var dur := float(cur.get("duration_s", 0.0))
	var end_s := float(cur.get("max_s", dur))
	var obj_key := ""
	var obj_value := ""
	if state.seg.seg == TankIds.SEG_GUN_LINE:
		var total := state.gun_line.guns_total
		obj_key = "TANK_HUD_GUNS"
		obj_value = "%d/%d" % [clampi(total - state.gun_line.guns_left, 0, total), total]
	if state.seg.regroup:
		obj_key = "TANK_OBJ_REGROUP"
		obj_value = ""
	return {
		"title": str(cur.get("label", "")),
		"left_s": maxf(end_s - state.seg.elapsed_s, 0.0),
		"blocks": blocks,
		"index": i,
		"progress": clampf(state.seg.elapsed_s / maxf(dur, 1.0), 0.0, 1.0),
		"obj_key": obj_key,
		"obj_value": obj_value,
		"warn": state.seg.regroup,
		"next": str(nxt.get("label", "")),
	}


## The crew's kills (every type).
static func kills(state: TankState) -> int:
	var n := 0
	for k in state.score.kills:
		n += k
	return n


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

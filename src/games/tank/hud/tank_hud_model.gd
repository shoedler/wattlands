class_name TankHudModel
extends RefCounted
## What Diesel Domestiques' own HUD shows, as plain data computed from TankGame.state (pure and
## static, so tests read it without drawing; brief 2.3, 2.4, 3.6): the local rider's band and their
## one instruction line (v3 per seat: HOLD / SURGE / BUILD / OVER / SPIN / RESERVE), the seat panel's
## cards in seat order, the rack, the feed's rate and the Repairs card's numbers,
## the telegraphing shooters and the incoming evadable shell, the difficulty and the losses, the
## mission plate's stage strip and objective, the halt distance and
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
## The Drive seat's SIM band in % FTP (tanks.json in_band.sim_ftp_pct).
const SIM_BAND_PCT: Array = [76.0, 105.0]
## The Loader "building" its rack at >= 90 % FTP; with the rack full it only needs cadence >= 50.
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
## Instruction kinds (v3: per seat). Drive HOLD (SURGE to evade), Gun HOLD (ERG), Loader BUILD
## (OVER inside the Overpressure window, SPIN once the rack is full), Lights HOLD (ERG), Secondaries
## FEED (SPIN with the rounds a minute), Repairs HOLD (ERG); everyone KEEP RIDING under a tow.
const DO_NONE := ""
const DO_HOLD := "hold"
const DO_SPIN := "spin"
const DO_SURGE := "surge"
const DO_BUILD := "build"
const DO_OVER := "over"
const DO_FEED := "feed"
const DO_RESERVE := "reserve"
const DO_TOW := "tow"
## An evadable shell's pips: its longest flight is about 4 s (SPEC_TANK section 2).
const SHELL_PIPS_S := 4.0
## The machine TankMech paints for each seat's engine.
const MECH := {
	TankIds.ENGINE_DIESEL: "diesel",
	TankIds.ENGINE_DYNAMO: "dynamo",
	TankIds.ENGINE_STEAM: "steam",
	TankIds.ENGINE_ARC: "arc",
	TankIds.ENGINE_FEED: "feed",
	TankIds.ENGINE_REPAIR: "repair",
}
## Each seat's trainer mode in its work (the v3 seat table): the seat cards' ERG / SIM tags.
const SEAT_MODE := {
	TankIds.ENGINE_DIESEL: Wl.SIM,
	TankIds.ENGINE_DYNAMO: Wl.ERG,
	TankIds.ENGINE_STEAM: Wl.SIM,
	TankIds.ENGINE_ARC: Wl.ERG,
	TankIds.ENGINE_FEED: Wl.SIM,
	TankIds.ENGINE_REPAIR: Wl.ERG,
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


## The seat panel (v3 seat panel A): one card per seat in TankIds.SEATS order (Drive, Gun, Loader,
## Lights, Secondaries, Repairs), manned or not: {engine, mech, mode (the seat's ERG / SIM), empty,
## slot (-1 empty), peer, w, cad, ratio, state (band_state), in_band, local, bot, reserve, wait_s and
## mode_to (the rider's trainer switch to come, 0.3.1)}. The local rider's watts and cadence come from `local`
## ({"w", "cad"}) when given (their own telemetry).
static func seat_cards(state: TankState, local_peer: int, local: Dictionary = {}) -> Array:
	var out: Array = []
	if state == null:
		return out
	for engine in TankIds.SEATS:
		var c := {
			"engine": engine,
			"mech": str(MECH[engine]),
			"mode": str(SEAT_MODE[engine]),
			"empty": true,
			"slot": -1,
			"peer": 0,
			"w": 0.0,
			"cad": 0.0,
			"ratio": 0.0,
			"in_band": false,
			"state": -1,
			"local": false,
			"bot": false,
			"reserve": false,
			"wait_s": 0.0,
			"mode_to": "",
		}
		var st := state.station(engine)
		var r := state.rider_at(st.slot) if st != null and st.slot >= 0 else null
		if r != null:
			c.merge(_manned(state, st, r, local_peer, local), true)
		out.append(c)
	return out


static func _manned(
	state: TankState, st: TankStationState, r: TankRiderState, local_peer: int, local: Dictionary
) -> Dictionary:
	var is_local := r.peer == local_peer
	var w := float(local.get("w", r.raw_w)) if is_local else r.raw_w
	var cad := float(local.get("cad", r.cadence_rpm)) if is_local else r.cadence_rpm
	var away := r.afk or not r.connected or st.reserve
	if away or state.all_afk:
		cad = 0.0
	var ratio := power_ratio(r, w)
	return {
		"empty": false,
		"slot": r.slot,
		"peer": r.peer,
		"w": w,
		"cad": cad,
		"ratio": ratio,
		"in_band": r.in_band,
		"state": band_state(r.in_band, ratio),
		"local": is_local,
		"bot": r.is_bot,
		"reserve": away,
		"wait_s": r.mode_wait_s,
		"mode_to": r.mode_to,
	}


## The Loader's ready rack (0..TankConst.RACK_MAX; 0 without a Loader room).
static func rack(state: TankState) -> int:
	if state == null:
		return 0
	var stm := state.station(TankIds.ENGINE_STEAM) as TankSteamState
	return clampi(stm.rack, 0, TankConst.RACK_MAX) if stm != null else 0


## The bow guns' rounds a minute now (TankFeedState.rpm; 0 while the Secondaries seat is empty).
static func feed_rpm(state: TankState) -> float:
	if state == null:
		return 0.0
	var fd := state.station(TankIds.ENGINE_FEED) as TankFeedState
	return fd.rpm if fd != null and not fd.is_empty() else 0.0


## The Repairs card (`w` the rider's watts): {working, hull (0..1), rate (hull HP a second now, 0 unless
## working)}: tanks.json repair.hp_per_kj x the difficulty's repair x kW. Raw watts stand in for P_eff,
## which stays on the host. {} without a Repairs room.
static func repair(state: TankState, w: float) -> Dictionary:
	var rp := state.station(TankIds.ENGINE_REPAIR) as TankRepairState if state != null else null
	if rp == null:
		return {}
	var rate := 0.0
	if rp.working and state.content != null:
		var per_kj := state.content.num("tanks", "repair.hp_per_kj", 3.0)
		rate = maxf(w, 0.0) / 1000.0 * per_kj * TankDifficulty.mult(state, "repair")
	var frac := clampf(state.hull.hp / maxf(state.hull.hp_max, 1.0), 0.0, 1.0)
	return {"working": rp.working, "hull": frac, "rate": rate}


## The string key of `engine`'s machine, the one beside the seat's name in my numbers.
static func machine_key(engine: String) -> String:
	if engine == TankIds.ENGINE_REPAIR:
		return "TANK_ENGINE_REPAIR"
	return "TANK_HUD_ENG_" + engine.to_upper()


## The difficulty as a plate shows it: {key (TANK_HUD_DIFF_*), hard}.
static func difficulty(state: TankState) -> Dictionary:
	var level := state.difficulty
	if level == TankIds.DIFF_AUTO or not TankIds.DIFFICULTIES.has(level):
		level = TankIds.DIFF_NORMAL
	return {"key": "TANK_HUD_DIFF_" + level.to_upper(), "hard": level == TankIds.DIFF_HARD}


## The local rider's heart rate (bpm) from their own telemetry (Telemetry.heart_rate_bpm: local
## only, 0 without a sensor); 0 without telemetry.
static func heart_bpm(t: Telemetry) -> int:
	if t == null or t.heart_rate_bpm <= 0:
		return 0
	return t.heart_rate_bpm


## The Secondaries card's rate line, a string key: TANK_HUD_PER_MIN while the bow guns fire;
## TANK_HUD_NO_TARGET while their seat is manned and its rider pedals (`cad` rpm, the card's) with
## the guns powered but nothing in their reach (TankBow keeps them silent, so the rate would read
## 0/min); TANK_HUD_PER_MIN (0/min) while the rider does not pedal or the guns are down (a
## breakdown, every rider AFK); "" for an empty seat or one on reserve (the card says so).
static func feed_label(state: TankState, cad: float) -> String:
	if state == null:
		return ""
	var fd := state.station(TankIds.ENGINE_FEED) as TankFeedState
	if fd == null or fd.is_empty() or fd.reserve:
		return ""
	if fd.rpm > 0.0:
		return "TANK_HUD_PER_MIN"
	if cad > 1.0 and not fd.unpowered and not state.all_afk and not state.hull.breakdown:
		return "TANK_HUD_NO_TARGET"
	return "TANK_HUD_PER_MIN"


## The trainer mode the plan gives `engine` in the current segment (the mission's plan entry; else
## the seat's own mode, SEAT_MODE).
static func plan_mode(state: TankState, engine: String) -> String:
	if state.content != null and state.seg.seg != "":
		var e := state.content.plan_entry(engine, state.seg.seg)
		if e.has("mode"):
			return str(e["mode"])
	return str(SEAT_MODE.get(engine, Wl.ERG))


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
		total *= TankDifficulty.mult(state, "telegraph")
		var tot := maxf(total, e.telegraph_s)
		out.append({"id": e.id, "boss": false, "left": e.telegraph_s, "total": tot})
	var b := state.boss
	var up := b.phase == TankIds.BOSS_PHASE_1 or b.phase == TankIds.BOSS_PHASE_2
	if up and b.telegraph_s > 0.0:
		var total_b := float(TELEGRAPH_S["boss"])
		if state.content != null:
			var main: Dictionary = state.content.boss_def().get("main", {})
			total_b = float(main.get("telegraph_s", total_b))
		total_b *= TankDifficulty.mult(state, "telegraph")
		var tot_b := maxf(total_b, b.telegraph_s)
		out.append({"id": 0, "boss": true, "left": b.telegraph_s, "total": tot_b})
	return out


## The incoming evadable shell nearest its landing: {id, left, total}; {} when none is in the air.
static func evadable_shell(state: TankState) -> Dictionary:
	if state == null:
		return {}
	var out := {}
	for sh in state.shells:
		if not sh.far or not sh.evadable or sh.friendly or sh.left_s <= 0.0:
			continue
		if out.is_empty() or sh.left_s < float(out["left"]):
			out = {"id": sh.id, "left": sh.left_s, "total": maxf(SHELL_PIPS_S, sh.left_s)}
	return out


## The shortest time left to make a shot miss (s; 0 when none): a telegraph, or an evadable shell's
## flight, since the sprint counts through both.
static func telegraph_left(state: TankState) -> float:
	var left := 0.0
	for t: Dictionary in telegraphs(state):
		var l := float(t["left"])
		if left <= 0.0 or l < left:
			left = l
	var sh := evadable_shell(state)
	if not sh.is_empty() and (left <= 0.0 or float(sh["left"]) < left):
		left = float(sh["left"])
	return left


## The local rider's power band in W (x low, y high; y 0 = open-ended, "lo+"; ZERO = none) for
## their seat now (brief 2.3 In band, v3 effort table): the applied ERG target (`target_w`) +/- 5 %
## for an ERG rider (Gun, Lights, any checkpoint); the published SIM band (`published`, the
## HudLayer's) or 76-105 % FTP for Drive in SIM; >= 90 % FTP for the Loader building its rack; the
## published band (else none) for the Secondaries; none outside WORK or for a cadence-only rule (a
## full rack).
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
		TankIds.ENGINE_DIESEL:
			if published.y > 0.0:
				return published
			var b: Array = SIM_BAND_PCT
			if state.content != null:
				b = state.content.value("tanks", "in_band.sim_ftp_pct", SIM_BAND_PCT)
			return Vector2(float(b[0]) / 100.0 * r.ftp, float(b[1]) / 100.0 * r.ftp)
		TankIds.ENGINE_STEAM:
			if rack(state) >= TankConst.RACK_MAX:
				return Vector2.ZERO
			return Vector2(STEAM_PCT / 100.0 * r.ftp, 0.0)
	return published if published.y > 0.0 else Vector2.ZERO


## The one instruction line for the local rider's seat: {kind (DO_*), key, args, urgent, left_s}.
## `nums`: {"mode": the trainer mode, "cad": cadence, "band": band_w(), "cband": the published
## cadence band (ZERO = none)}. In order: nothing in the cool-down; RESERVE while the seat runs on
## reserve; Loader: OVER nnn+ W with the time left while the Overpressure window is open; SURGE
## nnn+ W with the time left for a SIM rider who can evade while a shooter telegraphs;
## Secondaries: SPIN nn+ and the bow guns' rounds a minute (FEED); Loader in WORK: SPIN 50+ RPM
## with the rack full, else BUILD nnn+ W; SPIN nn+ RPM where the rule is cadence (the depot,
## checkpoints, an ERG rider under the cadence floor); else HOLD lo-hi W (Drive, Gun, Lights,
## Repairs). Under a tow (after RESERVE) everyone reads KEEP RIDING: the plan runs on.
static func instruction(state: TankState, r: TankRiderState, nums: Dictionary) -> Dictionary:
	if state == null or r == null or r.engine == "" or state.in_cooldown():
		return _line(DO_NONE, "", [], 0.0)
	var st := state.station_of(r.slot)
	if r.afk or not r.connected or (st != null and st.reserve) or state.all_afk:
		return _line(DO_RESERVE, "TANK_HUD_DO_RESERVE", [], 0.0)
	if state.hull.tow_s > 0.0:
		return _line(DO_TOW, "TANK_HUD_DO_TOW", [], 0.0)
	var mode := str(nums.get("mode", plan_mode(state, r.engine)))
	var sprint := str(roundi(SPRINT_FTP * r.ftp))
	var stm := st as TankSteamState
	var work := state.seg.kind == Wl.WORK
	if work and stm != null and stm.window_s > 0.0:
		return _line(DO_OVER, "TANK_HUD_DO_OVER", [sprint], stm.window_s)
	var left := telegraph_left(state)
	if left > 0.0 and can_evade(state, r, mode):
		return _line(DO_SURGE, "TANK_HUD_DO_SURGE", [sprint], left)
	var cb: Vector2 = nums.get("cband", Vector2.ZERO)
	var floor_rpm := str(roundi(cb.x if cb.y > 0.0 else DEFAULT_RPM))
	if st is TankFeedState:
		var fcad := float(nums.get("cad", r.cadence_rpm))
		if feed_label(state, fcad) == "TANK_HUD_NO_TARGET":
			return _line(DO_FEED, "TANK_HUD_DO_FEED_IDLE", [floor_rpm], 0.0)
		var rate := str(roundi(feed_rpm(state)))
		return _line(DO_FEED, "TANK_HUD_DO_FEED", [floor_rpm, rate], 0.0)
	var band: Vector2 = nums.get("band", Vector2.ZERO)
	if work and stm != null:
		if rack(state) >= TankConst.RACK_MAX or band.x <= 0.0:
			var lr := str(roundi(cb.x if cb.y > 0.0 else LOADER_RPM))
			return _line(DO_SPIN, "TANK_HUD_DO_SPIN", [lr], 0.0)
		return _line(DO_BUILD, "TANK_HUD_DO_BUILD", [str(roundi(band.x))], 0.0)
	var cad := float(nums.get("cad", r.cadence_rpm))
	var under_floor := mode == Wl.ERG and cad < float(floor_rpm)
	if not work or under_floor or band.x <= 0.0:
		return _line(DO_SPIN, "TANK_HUD_DO_SPIN", [floor_rpm], 0.0)
	if band.y <= 0.0:
		return _line(DO_HOLD, "TANK_HUD_DO_HOLD_MIN", [str(roundi(band.x))], 0.0)
	var lo := str(roundi(band.x))
	return _line(DO_HOLD, "TANK_HUD_DO_HOLD", [lo, str(roundi(band.y))], 0.0)


static func _line(kind: String, key: String, args: Array, left: float) -> Dictionary:
	var urgent := kind == DO_SURGE or kind == DO_OVER
	return {"kind": kind, "key": key, "args": args, "urgent": urgent, "left_s": left}


## The mission plate: {title (the segment's label key), left_s (to the nominal end, or to the
## latest end of an open-ended segment), blocks [{type, len}] (every segment by its nominal
## length), index, progress (0..1 of the nominal length), obj_key and obj_args (the holding force,
## or Regroup), warn, next (the next segment's label key), diff_key and hard (difficulty()),
## losses}; {} without content. The cool-down has no segment of its own: the plate names it and
## counts its 180 s down (PlanValidator.COOLDOWN_S).
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
	var obj_args: Array = []
	if state.seg.seg == TankIds.SEG_GUN_LINE and state.gun_line.guns_total > 0:
		var total := state.gun_line.guns_total
		obj_key = "TANK_OBJ_HOLD"
		obj_args = [clampi(total - state.gun_line.guns_left, 0, total), total]
	if state.seg.regroup:
		obj_key = "TANK_OBJ_REGROUP"
		obj_args = []
	var diff := difficulty(state)
	var cooling := state.in_cooldown()
	if cooling:
		end_s = PlanValidator.COOLDOWN_S
	return {
		"title": "TANK_PHASE_COOLDOWN" if cooling else str(cur.get("label", "")),
		"left_s": maxf(end_s - state.seg.elapsed_s, 0.0),
		"blocks": blocks,
		"index": i,
		"progress": clampf(state.seg.elapsed_s / maxf(dur, 1.0), 0.0, 1.0),
		"obj_key": obj_key,
		"obj_args": obj_args,
		"warn": state.seg.regroup,
		"next": str(nxt.get("label", "")),
		"diff_key": diff["key"],
		"hard": diff["hard"],
		"losses": state.score.losses,
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
				"key": "TANK_OBJ_HOLD",
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
		scale_k = state.content.enemy_scale(state.hull.tank) * TankDifficulty.mult(state, "hp")
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

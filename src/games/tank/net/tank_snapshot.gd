class_name TankSnapshot
extends RefCounted
## Encodes TankState into the 10 Hz snapshot (TankSnapshotSchema) and applies one to a client's
## state. Owner: module. Every number is an int; apply() casts with int() again (GAME_SDK 12).
## apply() ends with derive(): the fields the snapshot leaves out that every peer can compute from
## the content and the rows it just got (the segment's kind and length, the distance driven, the
## outcome, the boss and enemy maximum HP, which rider works each room, nothing has power).

const S := preload("res://src/games/tank/contracts/tank_snapshot_schema.gd")
## Obstacle widths in art px by type (art.json sprite sizes), for the obstacles a client creates.
const OBSTACLE_WIDTHS := {
	TankIds.OBST_WIRE: 64,
	TankIds.OBST_WRECK: 72,
	TankIds.OBST_DRILL_WRECK: 72,
	TankIds.OBST_TANK_TRAPS: 64
}


static func encode(state: TankState) -> Dictionary:
	var sg := state.seg
	var hl := state.hull
	var sg_flags := (
		(S.SGF_OBJECTIVE if sg.objective_done else 0)
		| (S.SGF_REGROUP if sg.regroup else 0)
		| (S.SGF_OVERRUN if sg.overrun else 0)
	)
	var tk_flags := (
		(S.TKF_HOLDING if hl.holding else 0)
		| (S.TKF_EVASIVE if hl.evasive else 0)
		| (S.TKF_TRAPS_CLEARED if hl.traps_cleared else 0)
		| (S.TKF_BLOCKED if hl.blocked_by != 0 else 0)
		| (S.TKF_BREAKDOWN if hl.breakdown else 0)
	)
	var r: Array = []
	for rd in state.riders:
		var f := (
			(S.RF_IN_BAND if rd.in_band else 0)
			| (S.RF_RESCUE if rd.rescue else 0)
			| (S.RF_AFK if rd.afk else 0)
			| (S.RF_CONNECTED if rd.connected else 0)
			| (S.RF_CAN_EVADE if rd.can_evade else 0)
			| (S.RF_SPRINTING if rd.sprinting else 0)
		)
		r.append(
			[
				rd.slot,
				TankIds.engine_code(rd.engine),
				roundi(rd.raw_w),
				roundi(rd.cadence_rpm),
				roundi(rd.ftp_pct),
				f,
				S.x10(rd.target_pct)
			]
		)
	var st: Array = []
	for s in state.stations:
		st.append(_station_row(s))
	var e: Array = []
	for en in state.enemies:
		e.append(
			[
				en.id,
				en.code,
				S.x10(en.x_px),
				S.hp(en.hp),
				en.mode,
				en.side,
				S.ms(en.telegraph_s),
				en.lane
			]
		)
	var sh: Array = []
	for s in state.shells:
		sh.append(
			[s.id, s.type, roundi(s.x), roundi(s.y), roundi(s.vx), roundi(s.vy), int(s.friendly)]
		)
	var o: Array = []
	for ob in state.obstacles:
		o.append([ob.id, ob.code, roundi(ob.x_px), ob.light_hits, int(ob.cleared)])
	var bs := state.boss
	var b: Array = [
		bs.phase,
		S.x10(bs.x_px),
		S.hp(bs.bogie_hp[0]),
		S.hp(bs.bogie_hp[1]),
		S.hp(bs.bogie_hp[2]),
		S.hp(bs.turret_hp),
		S.ms(bs.telegraph_s)
	]
	if bs.phase == TankIds.BOSS_NONE:
		b = [0, 0, 0, 0, 0, 0, 0]
	return {
		"v": S.VERSION,
		"tick": state.tick,
		"sg": [TankIds.seg_code(sg.seg), sg.stage, sg.phase_index, S.ms(sg.elapsed_s), sg_flags],
		"tk":
		[
			hl.code,
			S.x10(hl.x_px),
			roundi(hl.speed_mps * 100.0),
			S.x10(hl.grade_pct),
			S.hp(hl.hp),
			roundi(hl.hp_max),
			S.hp(hl.berm_hp),
			0,
			roundi(hl.repair_j / 100.0),
			hl.facing,
			S.x10(hl.elev_deg),
			S.ms(hl.traverse_s),
			hl.loaded,
			S.ms(hl.breech_s),
			hl.target_id,
			tk_flags,
			hl.dir
		],
		"r": r,
		"st": st,
		"e": e,
		"s": sh,
		"o": o,
		"gl":
		[
			int(state.gun_line.active),
			state.gun_line.guns_total,
			state.gun_line.guns_left,
			int(state.gun_line.barrage)
		],
		"b": b,
		"sc":
		[
			state.score.breakdowns,
			state.score.overruns,
			int(state.score.behemoth_killed),
			state.score.crew_kills
		],
	}


static func _station_row(s: TankStationState) -> Array:
	var f := (
		(S.STF_IN_BAND if s.in_band else 0)
		| (S.STF_RESERVE if s.reserve else 0)
		| (S.STF_UNPOWERED if s.unpowered else 0)
	)
	var v: Array = [0, 0, 0, 0, 0]
	if s is TankGearboxState:
		var g := s as TankGearboxState
		f |= (S.STF_SPRINTING if g.sprinting else 0) | (S.STF_AUTO if g.auto else 0)
		v = [
			0,
			0,
			g.lever + 4 * g.lever_to,
			S.ms(g.move_s),
			roundi(g.hoist_j / 10.0)
		]
	elif s is TankDieselState:
		var d := s as TankDieselState
		f |= S.STF_SPRINTING if d.sprinting else 0
		v = [0, 0, 0, 0, 0]
	elif s is TankDynamoState:
		var dy := s as TankDynamoState
		f |= (S.STF_STALLED if dy.stalled else 0) | (S.STF_STABILIZING if dy.stabilizing else 0)
		v = [S.x10(dy.bank), S.ms(dy.hoist_s), 0, 0, 0]
	elif s is TankSteamState:
		var sm := s as TankSteamState
		f |= (S.STF_OVER if sm.over else 0) | (S.STF_LOADED if sm.loaded else 0)
		f |= (S.STF_CYCLING if sm.cycling else 0) | (S.STF_STEAM_SPRINTING if sm.sprinting else 0)
		v = [S.x10(sm.pressure_pct), S.ms(sm.window_s), S.ms(sm.over_s), 0, 0]
	elif s is TankArcState:
		var arc := s as TankArcState
		f |= (S.STF_LIT if arc.lit else 0) | (S.STF_ARC_STALLED if arc.stalled else 0)
		v = [S.pml(arc.duty), 0, 0, 0, 0]
	return [TankIds.engine_code(s.engine), s.slot, f] + v


## Overwrites the [snap] part of a client's `state` from `snap` (ints cast again). Rows the
## snapshot no longer has are removed; new ones are created (enemies, shells, obstacles).
static func apply(state: TankState, snap: Dictionary) -> void:
	state.tick = int(snap.get("tick", state.tick))
	state.t = state.tick * Wl.SIM_DT
	var sg: Array = snap.get("sg", [])
	if sg.size() == S.SG_LEN:
		state.seg.seg = TankIds.seg_of(int(sg[S.SG_SEG]))
		state.seg.stage = int(sg[S.SG_STAGE])
		state.seg.phase_index = int(sg[S.SG_PHASE])
		state.seg.elapsed_s = int(sg[S.SG_ELAPSED_MS]) / 1000.0
		var f := int(sg[S.SG_FLAGS])
		state.seg.objective_done = (f & S.SGF_OBJECTIVE) != 0
		state.seg.regroup = (f & S.SGF_REGROUP) != 0
		state.seg.overrun = (f & S.SGF_OVERRUN) != 0
	var tk: Array = snap.get("tk", [])
	if tk.size() == S.TK_LEN:
		_apply_hull(state.hull, tk)
	for row: Variant in snap.get("r", []):
		var rd := state.rider_at(int(row[S.R_SLOT]))
		if rd == null:
			continue
		rd.engine = TankIds.engine_of(int(row[S.R_ENGINE]))
		rd.raw_w = int(row[S.R_RAW_W])
		rd.cadence_rpm = int(row[S.R_CADENCE])
		rd.ftp_pct = int(row[S.R_FTP_PCT])
		rd.target_pct = int(row[S.R_TARGET_X10]) / 10.0
		var f := int(row[S.R_FLAGS])
		rd.in_band = (f & S.RF_IN_BAND) != 0
		rd.rescue = (f & S.RF_RESCUE) != 0
		rd.afk = (f & S.RF_AFK) != 0
		rd.connected = (f & S.RF_CONNECTED) != 0
		rd.can_evade = (f & S.RF_CAN_EVADE) != 0
		rd.sprinting = (f & S.RF_SPRINTING) != 0
	for row: Variant in snap.get("st", []):
		var s := state.station(TankIds.engine_of(int(row[S.ST_ENGINE])))
		if s != null:
			_apply_station(s, row)
	_apply_enemies(state, snap.get("e", []))
	_apply_shells(state, snap.get("s", []))
	_apply_obstacles(state, snap.get("o", []))
	var gl: Array = snap.get("gl", [])
	if gl.size() == S.GL_LEN:
		state.gun_line.active = int(gl[S.GL_ACTIVE]) != 0
		state.gun_line.guns_total = int(gl[S.GL_TOTAL])
		state.gun_line.guns_left = int(gl[S.GL_LEFT])
		state.gun_line.barrage = int(gl[S.GL_BARRAGE]) != 0
	var b: Array = snap.get("b", [])
	if b.size() == S.B_LEN:
		state.boss.phase = int(b[S.B_PHASE])
		state.boss.x_px = int(b[S.B_X_DPX]) / 10.0
		for i in 3:
			state.boss.bogie_hp[i] = float(int(b[S.B_BOGIE_0 + i]))
		state.boss.turret_hp = float(int(b[S.B_TURRET]))
		state.boss.telegraph_s = int(b[S.B_TELEGRAPH_MS]) / 1000.0
	var sc: Array = snap.get("sc", [])
	if sc.size() == S.SC_LEN:
		state.score.breakdowns = int(sc[S.SC_BREAKDOWNS])
		state.score.overruns = int(sc[S.SC_OVERRUNS])
		state.score.behemoth_killed = int(sc[S.SC_BEHEMOTH]) != 0
		state.score.crew_kills = int(sc[S.SC_CREW_KILLS])
	derive(state)


## The state a snapshot does not carry, from the content and the rows applied: safe to call on any
## state (the host's too; it only fills fields the host's rules keep up to date anyway).
static func derive(state: TankState) -> void:
	for st in state.stations:
		var holder := state.rider_at(st.slot)
		st.peer = holder.peer if holder != null else 0
	var all_afk := not state.riders.is_empty()
	for r in state.riders:
		if not (r.afk or not r.connected):
			all_afk = false
	state.all_afk = all_afk
	state.hull.distance_m = state.hull.x_px / TankConst.PX_PER_M
	var c := state.content
	if c == null:
		return
	_derive_segment(state, c)
	_derive_maxima(state, c)


static func _derive_segment(state: TankState, c: TankContent) -> void:
	var sg := state.seg
	var def: Dictionary = {}
	if sg.seg == TankIds.SEG_COOLDOWN:
		sg.segment_index = -1
		sg.kind = Wl.COOLDOWN
	elif sg.seg != TankIds.SEG_NONE:
		sg.segment_index = sg.phase_index
		def = c.segment(sg.segment_index)
		sg.kind = str(def.get("kind", ""))
	sg.open_ended = def.has("min_s")
	sg.min_s = float(def.get("min_s", 0.0))
	sg.max_s = float(def.get("max_s", 0.0))
	sg.length_m = float(def.get("length_m", 0.0))
	if sg.seg == TankIds.SEG_COOLDOWN:
		state.outcome = _outcome(state, c)
	else:
		state.outcome = ""


## The mission's result once the plan's last segment ended (the rules' rule): victory when the
## Behemoth died, withdrawn when a mission with a boss ended without it, complete without a boss.
static func _outcome(state: TankState, c: TankContent) -> String:
	if state.score.behemoth_killed:
		return TankIds.OUTCOME_VICTORY
	for s: Variant in c.segments():
		if str((s as Dictionary).get("type", "")) == TankIds.SEG_BOSS:
			return TankIds.OUTCOME_WITHDRAWN
	return TankIds.OUTCOME_COMPLETE


static func _derive_maxima(state: TankState, c: TankContent) -> void:
	var scale := c.enemy_scale(state.hull.tank)
	var boss := c.boss_def()
	state.boss.bogie_max = float(boss.get("bogie_hp", state.boss.bogie_max)) * scale
	state.boss.turret_max = float(boss.get("turret_hp", state.boss.turret_max)) * scale
	for en in state.enemies:
		if en.hp_max < en.hp:
			en.hp_max = en.hp


static func _apply_hull(hl: TankHullState, tk: Array) -> void:
	hl.code = int(tk[S.TK_CODE])
	hl.x_px = int(tk[S.TK_X_DPX]) / 10.0
	hl.speed_mps = int(tk[S.TK_SPEED_CMS]) / 100.0
	hl.grade_pct = int(tk[S.TK_GRADE_X10]) / 10.0
	hl.hp = float(int(tk[S.TK_HP]))
	hl.hp_max = float(int(tk[S.TK_HP_MAX]))
	hl.berm_hp = float(int(tk[S.TK_BERM]))
	hl.repair_j = int(tk[S.TK_REPAIR_HJ]) * 100.0
	hl.facing = int(tk[S.TK_FACING])
	hl.elev_deg = int(tk[S.TK_ELEV_X10]) / 10.0
	hl.traverse_s = int(tk[S.TK_TRAVERSE_MS]) / 1000.0
	hl.loaded = int(tk[S.TK_LOADED])
	hl.breech_s = int(tk[S.TK_BREECH_MS]) / 1000.0
	hl.target_id = int(tk[S.TK_TARGET])
	hl.dir = int(tk[S.TK_DIR])
	var f := int(tk[S.TK_FLAGS])
	hl.holding = (f & S.TKF_HOLDING) != 0
	hl.evasive = (f & S.TKF_EVASIVE) != 0
	hl.traps_cleared = (f & S.TKF_TRAPS_CLEARED) != 0
	hl.breakdown = (f & S.TKF_BREAKDOWN) != 0
	if (f & S.TKF_BLOCKED) == 0:
		hl.blocked_by = 0
	elif hl.blocked_by == 0:
		hl.blocked_by = -1


static func _apply_station(s: TankStationState, row: Array) -> void:
	s.slot = int(row[S.ST_SLOT])
	var f := int(row[S.ST_FLAGS])
	s.in_band = (f & S.STF_IN_BAND) != 0
	s.reserve = (f & S.STF_RESERVE) != 0
	s.unpowered = (f & S.STF_UNPOWERED) != 0
	var a := int(row[S.ST_A])
	var b := int(row[S.ST_B])
	var c := int(row[S.ST_C])
	if s is TankGearboxState:
		var g := s as TankGearboxState
		g.sprinting = (f & S.STF_SPRINTING) != 0
		g.auto = (f & S.STF_AUTO) != 0
		g.lever = c & 3
		g.lever_to = c >> 2
		g.move_s = int(row[S.ST_D]) / 1000.0
		g.hoist_j = int(row[S.ST_E]) * 10.0
	elif s is TankDieselState:
		var d := s as TankDieselState
		d.sprinting = (f & S.STF_SPRINTING) != 0
	elif s is TankDynamoState:
		var dy := s as TankDynamoState
		dy.stalled = (f & S.STF_STALLED) != 0
		dy.stabilizing = (f & S.STF_STABILIZING) != 0
		dy.bank = a / 10.0
		dy.hoist_s = b / 1000.0
	elif s is TankSteamState:
		var sm := s as TankSteamState
		sm.over = (f & S.STF_OVER) != 0
		sm.loaded = (f & S.STF_LOADED) != 0
		sm.cycling = (f & S.STF_CYCLING) != 0
		sm.sprinting = (f & S.STF_STEAM_SPRINTING) != 0
		sm.pressure_pct = a / 10.0
		sm.window_s = b / 1000.0
		sm.over_s = c / 1000.0
	elif s is TankArcState:
		var arc := s as TankArcState
		arc.lit = (f & S.STF_LIT) != 0
		arc.stalled = (f & S.STF_ARC_STALLED) != 0
		arc.duty = a / 1000.0


static func _apply_enemies(state: TankState, rows: Array) -> void:
	var out: Array[TankEnemyState] = []
	for row: Variant in rows:
		var id := int(row[S.E_ID])
		var en := state.enemy(id)
		if en == null:
			en = TankEnemyState.new()
			en.id = id
		en.code = int(row[S.E_CODE])
		en.x_px = int(row[S.E_X_DPX]) / 10.0
		en.hp = float(int(row[S.E_HP]))
		en.mode = int(row[S.E_MODE])
		en.side = int(row[S.E_SIDE])
		en.telegraph_s = int(row[S.E_TELEGRAPH_MS]) / 1000.0
		en.lane = int(row[S.E_LANE])
		if state.content != null and en.w == 0:
			var def := state.content.enemy_def(TankIds.enemy_of(en.code))
			var size: Array = def.get("size_px", [0, 0])
			en.w = int(size[0])
			en.h = int(size[1])
			en.hp_max = ceilf(
				float(def.get("hp", 0.0)) * state.content.enemy_scale(state.hull.tank)
			)
		out.append(en)
	state.enemies = out


static func _apply_shells(state: TankState, rows: Array) -> void:
	var out: Array[TankShellState] = []
	for row: Variant in rows:
		var sh := TankShellState.new()
		sh.id = int(row[S.S_ID])
		sh.type = int(row[S.S_TYPE])
		sh.x = int(row[S.S_X])
		sh.y = int(row[S.S_Y])
		sh.vx = int(row[S.S_VX])
		sh.vy = int(row[S.S_VY])
		sh.friendly = int(row[S.S_FRIENDLY]) != 0
		out.append(sh)
	state.shells = out


static func _apply_obstacles(state: TankState, rows: Array) -> void:
	var out: Array[TankObstacleState] = []
	for row: Variant in rows:
		var ob := TankObstacleState.new()
		ob.id = int(row[S.O_ID])
		ob.code = int(row[S.O_CODE])
		ob.w = int(OBSTACLE_WIDTHS.get(TankIds.obstacle_of(ob.code), ob.w))
		ob.x_px = int(row[S.O_X])
		ob.light_hits = int(row[S.O_LIGHT_HITS])
		ob.cleared = int(row[S.O_CLEARED]) != 0
		out.append(ob)
	state.obstacles = out

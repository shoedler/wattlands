class_name TankFixtures
extends RefCounted
## Fixed Tank states, frames and snapshots for view, HUD, net and rules tests (G0 contract).
## Every builder is deterministic (fixed numbers, no RNG), so tests can compare against the JSON
## files next to this script:
##
## state(crew): ashfall_road Stage 2 Advance (phase 4) 60 s in, for crew 1 (Bulwark), 2 (Rampart)
##   or 3 (Citadel): slots 1..crew (FTP 200, 220, 240; slot 1 unverified), stage-2 engines with
##   rotation on, the hull at 72 / 120 HP, a medium ahead holding 300 px, a light rushing from the
##   rear, a tank destroyer in its telegraph, a wreck barricade, three shells in flight, the bank at
##   64, pressure at 72%, the Bulwark's lever on Turret.
## gun_line(crew): Stage 2 gun line (phase 5) 40 s in: a heavy tank in its telegraph and 2 dug-in
##   tanks, the berm at 18 HP, the turret loaded with a heavy shell.
## boss(crew): the boss (phase 10) 150 s in: phase 1, the last bogie (index 2, farthest from the
##   tank) broken, the main gun in its telegraph, the diesel sprinting with a dodge prompt.
## cap(): the Citadel's state(3) with 16 enemies and 24 shells at large coordinates (the 4 KB test).
## frame(crew): an InputFrame for state(crew) (every rider compliant at 90% FTP in SIM, on target
##   in ERG); frames.json holds the same frames as dictionaries for view and HUD tests.
## snapshot_<tank>.json: TankSnapshot.encode(state(crew)) as JSON (ints).

const DIR := "res://tests/games/tank/fixtures"
const FRAMES_PATH := DIR + "/frames.json"
const PEERS: Array[int] = [1, 2, 3]

static var _contents: Dictionary = {}


static func content(mission: String = "ashfall_road") -> TankContent:
	if not _contents.has(mission):
		_contents[mission] = TankContent.from_dicts(TankContent.read_files(mission), mission)
	return _contents[mission]


## The fixture's slots (FTP 200, 220, 240; slot 1 unverified; Autopilot on).
static func slots(crew: int) -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for i in crew:
		var s := PlayerSlot.new()
		s.peer_id = PEERS[i]
		s.name = "Rider %d" % PEERS[i]
		s.apply_look(i)
		s.ftp = 200.0 + 20.0 * i
		s.ftp_verified = i != 1
		s.autopilot = true
		s.p_eff_per_w = 250.0 / s.ftp
		out.append(s)
	return out


## The rider's engine in mission segment `index` with rotation on.
static func engine_at(c: TankContent, crew: int, slot: int, index: int) -> String:
	return TankPlanBuilder.engine_for(c, TankIds.tank_for_crew(crew), slot, index, true)


static func state(crew: int) -> TankState:
	var c := content()
	var s := _base(c, crew, 4, 60.0)
	s.hull.x_px = 3200.0
	s.hull.distance_m = 400.0
	s.hull.speed_mps = 7.4
	s.hull.grade_pct = -1.5
	s.hull.hp = 72.0
	s.hull.hp_max = 120.0
	s.hull.evasive = true
	s.hull.elev_deg = 6.5
	s.hull.target_id = 11
	s.enemies.append(_enemy(11, TankIds.ENEMY_MEDIUM, s.hull.x_px + s.hull.hull_w + 300.0, 64.0, 1))
	s.enemies.append(_enemy(12, TankIds.ENEMY_LIGHT, s.hull.x_px - 140.0 - 80.0, 24.0, -1))
	var td := _enemy(13, TankIds.ENEMY_DESTROYER, s.camera_x() + 640.0 - 112.0, 50.0, 1)
	td.mode = TankIds.EM_TELEGRAPH
	td.telegraph_s = 2.5
	s.enemies.append(td)
	var ob := TankObstacleState.new()
	ob.id = 14
	ob.code = TankIds.obstacle_code(TankIds.OBST_WRECK)
	ob.x_px = s.hull.x_px + 900.0
	ob.w = 72
	ob.light_hits = 1
	s.obstacles.append(ob)
	s.shells.append(_shell(15, TankIds.SHELL_HEAVY, s.hull.x_px + 260.0, 200.0, 320.0, -90.0, true))
	s.shells.append(
		_shell(16, TankIds.SHELL_ENEMY, s.hull.x_px + 420.0, 240.0, -300.0, 40.0, false)
	)
	s.shells.append(
		_shell(17, TankIds.SHELL_SECONDARY, s.hull.x_px + 120.0, 230.0, -280.0, -30.0, true)
	)
	s.next_id = 18
	return s


static func gun_line(crew: int) -> TankState:
	var c := content()
	var s := _base(c, crew, 5, 40.0)
	s.hull.holding = true
	s.hull.hp = 64.0
	s.hull.hp_max = 120.0
	s.hull.berm_hp = 18.0
	s.hull.loaded = TankIds.SHELL_HEAVY
	s.hull.elev_deg = 3.0
	s.hull.target_id = 21
	s.gun_line.active = true
	s.gun_line.guns_total = 3
	s.gun_line.guns_left = 3
	var front := s.hull.x_px + s.hull.hull_w
	var hv := _enemy(21, TankIds.ENEMY_HEAVY, front + 300.0, 160.0, 1)
	hv.fixed = true
	hv.gun_line = true
	hv.mode = TankIds.EM_TELEGRAPH
	hv.telegraph_s = 1.5
	s.enemies.append(hv)
	for i in 2:
		var dg := _enemy(22 + i, TankIds.ENEMY_DUGIN, front + 150.0 + 80.0 * i, 50.0, 1)
		dg.fixed = true
		dg.gun_line = true
		dg.mode = TankIds.EM_HOLD
		s.enemies.append(dg)
	s.next_id = 24
	return s


static func boss(crew: int) -> TankState:
	var c := content()
	var s := _base(c, crew, 10, 150.0)
	s.hull.holding = true
	s.hull.hp = 90.0
	s.hull.hp_max = 160.0
	s.boss.phase = TankIds.BOSS_PHASE_1
	s.boss.x_px = s.hull.x_px + s.hull.hull_w + 180.0
	var def := c.boss_def()
	var scale := c.enemy_scale(s.hull.tank)
	var bogie_max := float(def["bogie_hp"]) * scale
	s.boss.bogie_hp = [bogie_max, bogie_max * 0.4, 0.0]
	s.boss.turret_hp = float(def["turret_hp"]) * scale
	s.boss.telegraph_s = 4.0
	s.boss.main_s = 4.0
	for st in s.stations:
		if st is TankDieselState:
			(st as TankDieselState).sprinting = true
			(st as TankDieselState).prompt = true
			(st as TankDieselState).dodge_s = 1.2
	s.next_id = 30
	return s


static func cap() -> TankState:
	var s := state(3)
	s.enemies.clear()
	s.shells.clear()
	for i in TankConst.MAX_ENEMIES:
		var e := _enemy(
			1000 + i, TankIds.ENEMY_TYPES[i % 5], 99999.9 + 37.3 * i, 160.0, 1 if i % 2 == 0 else -1
		)
		e.mode = TankIds.EM_TELEGRAPH
		e.telegraph_s = 3.999
		s.enemies.append(e)
	for i in TankConst.MAX_SHELLS:
		s.shells.append(
			_shell(2000 + i, TankIds.SHELL_OVER, 99999.0 + i, -999.0, -359.9, -359.9, i % 2 == 0)
		)
	s.tick = 49200
	s.hull.x_px = 99999.9
	return s


## The InputFrame for state(crew): its phase for every rider, compliant telemetry.
static func frame(crew: int) -> InputFrame:
	var c := content()
	var f := InputFrame.new()
	f.tick = 49200
	f.t = f.tick * Wl.SIM_DT
	var plans := TankPlanBuilder.build_all(c, slots(crew), true)
	for p in slots(crew):
		var plan: EffortPlan = plans[p.peer_id]
		var ph := plan.phase(4)
		var ps := PhaseState.new()
		ps.index = 4
		ps.kind = ph.kind
		ps.mode = ph.mode
		ps.elapsed_s = 60.0
		ps.duration_s = ph.duration_s
		ps.open_ended = ph.open_ended
		ps.min_s = ph.min_s
		ps.max_s = ph.max_s
		ps.label = ph.label
		ps.planned_pct = ph.planned_pct_at(60.0) if ph.mode == Wl.ERG else 0.0
		ps.remaining_s = ph.max_s - 60.0
		ps.count = plan.size() + 1
		ps.plan_elapsed_s = 300.0 + 180.0 + 120.0 + 60.0 + 60.0
		ps.prev_ended_by = Wl.ENDED_DURATION
		var tm := Telemetry.new()
		tm.peer_id = p.peer_id
		tm.t = f.t
		tm.mode = ph.mode
		tm.cadence_rpm = 90.0
		if ph.mode == Wl.ERG:
			tm.applied_target_w = int(
				ps.planned_pct / 100.0 * p.ftp * (1.0 if p.ftp_verified else 0.85)
			)
			tm.power_w = tm.applied_target_w
		else:
			tm.power_w = roundf(0.9 * p.ftp)
		tm.p_eff_w = tm.power_w * p.p_eff_per_w
		tm.ftp_pct = tm.power_w / p.ftp * 100.0
		tm.phase_index = 4
		tm.connected = true
		f.players[p.peer_id] = tm
		f.phase[p.peer_id] = ps
	return f


## frames.json's entry for `crew` rebuilt as an InputFrame.
static func frame_from_json(crew: int) -> InputFrame:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FRAMES_PATH))[str(crew)]
	var f := InputFrame.new()
	f.tick = int(d["tick"])
	f.t = float(d["t"])
	for k: String in d["telemetry"]:
		f.players[int(k)] = Telemetry.from_dict(d["telemetry"][k])
	for k: String in d["phase"]:
		f.phase[int(k)] = PhaseState.from_dict(d["phase"][k])
	return f


## frame(crew) as a JSON-safe dictionary (what frames.json holds).
static func frame_dict(crew: int) -> Dictionary:
	var f := frame(crew)
	var tel := {}
	var ph := {}
	for peer: int in f.players:
		tel[str(peer)] = f.players[peer].to_dict()
		ph[str(peer)] = f.phase[peer].to_dict()
	return {"tick": f.tick, "t": f.t, "telemetry": tel, "phase": ph}


## The snapshot JSON path of `crew`'s state().
static func snapshot_path(crew: int) -> String:
	return DIR.path_join("snapshot_%s.json" % TankIds.tank_for_crew(crew))


static func snapshot(crew: int) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(snapshot_path(crew)))


static func _base(c: TankContent, crew: int, index: int, elapsed: float) -> TankState:
	var s := TankState.create(c, slots(crew), "ashfall_road", true, null)
	var seg := c.segment(index)
	s.tick = 49200
	s.t = s.tick * Wl.SIM_DT
	s.seg.seg = str(seg["type"])
	s.seg.stage = int(seg["stage"])
	s.seg.phase_index = index
	s.seg.segment_index = index
	s.seg.kind = str(seg["kind"])
	s.seg.elapsed_s = elapsed
	s.seg.min_s = float(seg.get("min_s", 0.0))
	s.seg.max_s = float(seg.get("max_s", 0.0))
	s.seg.open_ended = seg.has("min_s")
	s.seg.length_m = float(seg.get("length_m", 0.0))
	for r in s.riders:
		r.engine = engine_at(c, crew, r.slot, index)
		r.raw_w = roundf(0.9 * r.ftp)
		r.cadence_rpm = 90.0
		r.ftp_pct = 90.0
		r.in_band = true
	for st in s.stations:
		st.slot = -1
		st.peer = 0
	for r in s.riders:
		var st := s.station(r.engine)
		if st != null:
			st.slot = r.slot
			st.peer = r.peer
			st.in_band = true
	for st in s.stations:
		if st is TankDynamoState:
			(st as TankDynamoState).bank = 64.0
			(st as TankDynamoState).stabilizing = true
		elif st is TankSteamState:
			(st as TankSteamState).pressure_pct = 72.0
		elif st is TankGearboxState:
			(st as TankGearboxState).lever = TankIds.LEVER_TURRET
			(st as TankGearboxState).lever_to = TankIds.LEVER_TURRET
			(st as TankGearboxState).hoist_j = 1500.0
	s.score.overruns = 1
	s.score.crew_kills = 5
	return s


static func _enemy(id: int, type: String, x: float, hp: float, side: int) -> TankEnemyState:
	var e := TankEnemyState.new()
	e.id = id
	e.code = TankIds.enemy_code(type)
	e.x_px = x
	e.hp = hp
	e.hp_max = hp
	e.side = side
	e.mode = TankIds.EM_HOLD
	var size: Array = content().enemy_def(type).get("size_px", [80, 40])
	e.w = int(size[0])
	e.h = int(size[1])
	return e


static func _shell(
	id: int, type: int, x: float, y: float, vx: float, vy: float, friendly: bool
) -> TankShellState:
	var s := TankShellState.new()
	s.id = id
	s.type = type
	s.x = x
	s.y = y
	s.vx = vx
	s.vy = vy
	s.friendly = friendly
	return s

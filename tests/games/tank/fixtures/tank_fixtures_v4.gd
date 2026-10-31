class_name TankFixturesV4
extends RefCounted
## v4's fixed states (SPEC_TANK section 7) for the view, HUD and bot builders, so nobody waits on the
## v4 rules. Deterministic: fixed numbers, no RNG, built on TankFixtures' helpers with the v4 fields
## filled by hand. make(name) builds one; tick() is the tiny fake of the rules for animated frames
## (shells' left_s and x/y, enemy dashes and weave, the tow's countdown, the press, wheel travel); it
## never calls a rules class. cues(name) lists the events a scene plays once when the fixture opens.

const NAMES: Array[String] = [
	"advance_far",
	"far_duel",
	"boss_far",
	"near_ambush",
	"bow_duel",
	"incoming",
	"tank_lost",
	"restart",
	"repair",
	"bots",
	"hard",
	"easy_breakdown",
	"roam_west",
	"cap_v4",
]
## Mission segment indexes in ashfall_road (TankFixtures' numbers).
const SEG_ADVANCE_2 := 4
const SEG_HOLD_2 := 5
const SEG_BOSS := 10
## The far frame's numbers (tanks.json gun.far) when a state has no content.
const V0 := 560.0
const G := 70.0
## The fake's weave and its near threats' dash.
const WEAVE_M := 40.0
const WEAVE_RAD_S := 0.7
const DASH_PX_S := 40.0
const FLEE_RESET_PX := 185.0
const TOW_LOOP_S := 8.0
const PRESS_PER_S := 0.25


## The fixture `name` for a crew of `crew`; repair and cap_v4 are always crew 4, bots 1 human and 3 bots.
static func make(name: String, crew: int = 3) -> TankState:
	match name:
		"advance_far":
			return _advance_far(crew)
		"far_duel":
			return _far_duel(crew)
		"boss_far":
			return _boss_far(crew)
		"near_ambush":
			return _near_ambush(crew)
		"bow_duel":
			return _bow_duel(crew)
		"incoming":
			return _incoming(crew)
		"tank_lost":
			return _tank_lost(crew)
		"restart":
			return _restart(crew)
		"repair":
			return _repair()
		"bots":
			return _bots()
		"hard":
			return _hard(crew)
		"easy_breakdown":
			return _easy_breakdown(crew)
		"roam_west":
			return _roam_west(crew)
		"cap_v4":
			return _cap_v4()
	push_error("TankFixturesV4: no fixture %s" % name)
	return null


## The events a scene plays once when fixture `name` opens.
static func cues(name: String) -> Array[Dictionary]:
	var ambush_code := TankIds.enemy_code(TankIds.ENEMY_RECON)
	match name:
		"near_ambush":
			return [TankEvents.ambush(41, ambush_code)]
		"tank_lost":
			return [TankEvents.tank_lost(1, TankIds.SEG_ADVANCE, 2)]
		"restart":
			return [TankEvents.stage_restart(TankIds.SEG_ADVANCE, 2, 84.0)]
	return []


## The content a fixture's game must load.
static func content_id(name: String) -> String:
	return "roam_30" if name == "roam_west" else "ashfall_road"


## One step of the fake: moves what the frames show; no rules class, no RNG.
static func tick(state: TankState, dt: float) -> void:
	state.t += dt
	state.tick = int(state.t / Wl.SIM_DT)
	state.seg.elapsed_s += dt
	var hull := state.hull
	if hull.out_of_action():
		hull.speed_mps = 0.0
	var dx := hull.speed_mps * TankConst.PX_PER_M * dt if not hull.holding else 0.0
	hull.x_px += dx
	hull.distance_m = hull.x_px / TankConst.PX_PER_M
	if hull.tow_s > 0.0:
		hull.tow_s = maxf(hull.tow_s - dt, 0.0)
		if hull.tow_s <= 0.0:
			hull.tow_s = TOW_LOOP_S
	for e in state.enemies:
		_tick_enemy(state, e, dx, dt)
	if state.boss.phase == TankIds.BOSS_PHASE_1:
		state.boss.telegraph_s = maxf(state.boss.telegraph_s - dt, 0.0)
		if state.boss.telegraph_s <= 0.0:
			state.boss.telegraph_s = 6.0
	for s in state.shells:
		_tick_shell(s, dt)
	for r in state.riders:
		r.cadence_rpm = 88.0 + 6.0 * sin(state.t * 1.3 + float(r.slot))
		r.raw_w = r.ftp * (0.9 + 0.12 * sin(state.t * 0.7 + float(r.slot)))
	for st in state.stations:
		if st is TankRepairState and (st as TankRepairState).working:
			var rp := st as TankRepairState
			rp.press_t += PRESS_PER_S * dt
			if rp.press_t >= 1.0:
				rp.press_t -= 1.0
				rp.patches += 1
		elif st is TankFeedState and not st.is_empty() and (st as TankFeedState).rpm > 0.0:
			_tick_feed(state, st as TankFeedState, dt)


## The Secondaries' rounds rise at the feed's rate.
static func _tick_feed(state: TankState, feed: TankFeedState, dt: float) -> void:
	var due := float(feed.get_meta(&"due", 0.0)) + feed.rpm / 60.0 * dt
	while due >= 1.0:
		due -= 1.0
		feed.rounds += 1
		feed.fire_tick = state.tick
	feed.set_meta(&"due", due)


static func _tick_enemy(state: TankState, e: TankEnemyState, dx: float, dt: float) -> void:
	if e.is_near():
		e.x_px += dx
		if e.mode == TankIds.EM_MOVE:
			e.x_px += DASH_PX_S * dt
			if e.x_px - _front(state) > FLEE_RESET_PX:
				e.x_px = _front(state) + 10.0
		return
	if e.telegraph_s > 0.0:
		e.telegraph_s = maxf(e.telegraph_s - dt, 0.0)
		if e.telegraph_s <= 0.0:
			e.telegraph_s = 3.0
	if e.code == TankIds.enemy_code(TankIds.ENEMY_LIGHT):
		e.weave += WEAVE_RAD_S * dt
		e.range_m = e.hold_m + WEAVE_M * sin(e.weave)
		e.rate_mps = WEAVE_M * WEAVE_RAD_S * cos(e.weave)


static func _tick_shell(s: TankShellState, dt: float) -> void:
	if not s.far:
		s.x += s.vx * dt
		s.y += s.vy * dt
		return
	s.left_s -= dt
	s.x += s.vx * dt
	s.y += s.vy * dt - 0.5 * G * dt * dt
	s.vy -= G * dt
	if s.left_s <= 0.0:
		_launch_far(s, float(s.get_meta(&"range_m")), float(s.get_meta(&"flight_s")))


# --- Builders ------------------------------------------------------------------------------------


static func _advance_far(crew: int) -> TankState:
	var s := _mission(crew, SEG_ADVANCE_2, 60.0)
	s.hull.x_px = 3200.0
	s.hull.distance_m = 400.0
	s.hull.speed_mps = 7.4
	s.hull.hp = 72.0
	s.hull.hp_max = 120.0
	s.hull.elev_deg = 8.0
	var md := _far(s, 11, TankIds.ENEMY_MEDIUM, 1220.0, 0)
	s.hull.target_id = md.id
	var td := _far(s, 12, TankIds.ENEMY_DESTROYER, 1950.0, 1)
	td.mode = TankIds.EM_TELEGRAPH
	td.telegraph_s = 3.0
	s.shells.append(_far_shell(15, TankIds.SHELL_HEAVY, true, 1220.0, 1.2))
	s.next_id = 16
	return s


static func _far_duel(crew: int) -> TankState:
	var s := _mission(crew, SEG_HOLD_2, 40.0)
	s.hull.holding = true
	s.hull.hp = 64.0
	s.hull.hp_max = 120.0
	s.hull.berm_hp = 18.0
	s.hull.loaded = TankIds.SHELL_HEAVY
	s.gun_line.active = true
	s.gun_line.guns_total = 3
	s.gun_line.guns_left = 3
	var hv := _far(s, 21, TankIds.ENEMY_HEAVY, 1640.0, 0)
	hv.gun_line = true
	hv.mode = TankIds.EM_TELEGRAPH
	hv.telegraph_s = 2.5
	s.hull.target_id = hv.id
	s.hull.elev_deg = 10.5
	for i in 2:
		var m := _far(s, 22 + i, TankIds.ENEMY_MEDIUM, 1150.0 + 300.0 * i, 1 + i)
		m.gun_line = true
	var incoming := _far_shell(31, TankIds.SHELL_ENEMY, false, 1640.0, 1.4)
	incoming.evadable = true
	incoming.will_hit = true
	incoming.source = hv.id
	s.shells.append(incoming)
	for r in s.riders:
		r.can_evade = true
	s.next_id = 32
	return s


static func _boss_far(crew: int) -> TankState:
	var s := _mission(crew, SEG_BOSS, 150.0)
	s.hull.holding = true
	s.hull.hp = 90.0
	s.hull.hp_max = 160.0
	s.hull.elev_deg = 7.0
	var c := s.content
	var def := c.boss_def()
	var scale := c.enemy_scale(s.hull.tank)
	var bogie_max := float(def["bogie_hp"]) * scale
	s.boss.phase = TankIds.BOSS_PHASE_1
	s.boss.range_m = 1100.0
	s.boss.bogie_max = bogie_max
	s.boss.bogie_hp = [bogie_max, bogie_max * 0.4, 0.0]
	s.boss.turret_max = float(def["turret_hp"]) * scale
	s.boss.turret_hp = s.boss.turret_max
	s.boss.telegraph_s = 4.0
	s.boss.main_s = 4.0
	s.hull.target_id = TankBossState.part_id(0)
	s.next_id = 30
	return s


static func _near_ambush(crew: int) -> TankState:
	var s := _mission(crew, SEG_ADVANCE_2, 60.0)
	s.hull.x_px = 3200.0
	s.hull.speed_mps = 6.5
	s.hull.hp = 96.0
	s.hull.hp_max = 120.0
	var rc := _near(s, 41, TankIds.ENEMY_RECON, 135.0, 0)
	rc.mode = TankIds.EM_PAUSE
	var tk := _near(s, 42, TankIds.ENEMY_TANKETTE, 25.0, 1)
	tk.mode = TankIds.EM_MOVE
	s.next_id = 43
	return s


static func _bow_duel(crew: int) -> TankState:
	var s := _near_ambush(crew)
	var arc := s.station(TankIds.ENGINE_ARC)
	var feed := s.station(TankIds.ENGINE_FEED) as TankFeedState
	if crew < 4 or arc == null or feed == null:
		_seat(s, s.riders[s.riders.size() - 1], TankIds.ENGINE_FEED)
	else:
		_seat(s, s.rider_at(arc.slot), TankIds.ENGINE_FEED)
	feed.rounds = 412
	feed.rpm = 180.0
	feed.fire_tick = s.tick
	var rc := s.enemy(41)
	rc.hp = rc.hp_max * 0.4
	return s


static func _incoming(crew: int) -> TankState:
	var s := _mission(crew, SEG_ADVANCE_2, 60.0)
	s.hull.x_px = 3200.0
	s.hull.speed_mps = 7.4
	s.hull.hp = 72.0
	s.hull.hp_max = 120.0
	var md := _far(s, 11, TankIds.ENEMY_MEDIUM, 1220.0, 0)
	var shell := _far_shell(16, TankIds.SHELL_ENEMY, false, 1220.0, 0.3)
	shell.will_hit = true
	shell.source = md.id
	s.shells.append(shell)
	s.next_id = 17
	return s


static func _tank_lost(crew: int) -> TankState:
	var s := _mission(crew, SEG_ADVANCE_2, 90.0)
	s.difficulty = TankIds.DIFF_HARD
	s.hull.x_px = 2400.0
	s.hull.hp = 0.0
	s.hull.hp_max = 120.0
	s.hull.speed_mps = 0.0
	s.hull.tow_s = 5.0
	s.score.losses = 1
	s.next_id = 50
	return s


static func _restart(crew: int) -> TankState:
	var s := _mission(crew, SEG_ADVANCE_2, 98.0)
	s.difficulty = TankIds.DIFF_HARD
	s.hull.x_px = 0.0
	s.hull.distance_m = 0.0
	s.hull.hp_max = 120.0
	s.hull.hp = 84.0
	s.hull.speed_mps = 0.0
	s.score.losses = 1
	s.next_id = 50
	return s


static func _repair() -> TankState:
	var s := _mission(4, SEG_ADVANCE_2, 60.0)
	s.hull.x_px = 3200.0
	s.hull.speed_mps = 7.4
	s.hull.hp_max = 120.0
	s.hull.hp = 66.0
	_seat(s, s.riders[3], TankIds.ENGINE_REPAIR)
	var rp := s.station(TankIds.ENGINE_REPAIR) as TankRepairState
	rp.in_band = true
	rp.working = true
	rp.press_t = 0.6
	rp.patches = 7
	rp.duty = 0.8
	_far(s, 11, TankIds.ENEMY_MEDIUM, 1220.0, 0)
	s.next_id = 12
	return s


static func _bots() -> TankState:
	var s := _mission(4, SEG_ADVANCE_2, 60.0)
	s.hull.x_px = 3200.0
	s.hull.speed_mps = 7.4
	s.hull.hp = 96.0
	s.hull.hp_max = 120.0
	for i in range(1, s.riders.size()):
		s.riders[i].is_bot = true
		s.riders[i].autopilot = true
		s.riders[i].fallback = false
		s.riders[i].ftp_verified = true
	_far(s, 11, TankIds.ENEMY_MEDIUM, 1220.0, 0)
	_far(s, 12, TankIds.ENEMY_LIGHT, 900.0, 1)
	s.next_id = 13
	return s


static func _hard(crew: int) -> TankState:
	var s := _advance_far(crew)
	s.difficulty = TankIds.DIFF_HARD
	s.score.losses = 1
	return s


static func _easy_breakdown(crew: int) -> TankState:
	var s := _mission(crew, SEG_ADVANCE_2, 90.0)
	s.difficulty = TankIds.DIFF_EASY
	s.hull.x_px = 2400.0
	s.hull.hp = 0.0
	s.hull.hp_max = 120.0
	s.hull.speed_mps = 0.0
	s.hull.breakdown = true
	s.hull.repair_j = 4000.0
	s.score.breakdowns = 1
	_far(s, 11, TankIds.ENEMY_MEDIUM, 1400.0, 0)
	s.next_id = 12
	return s


static func _roam_west(crew: int) -> TankState:
	var s := TankViewUtil.roam_state(crew, TankIds.DIR_LEFT)
	s.enemies.clear()
	_far(s, 301, TankIds.ENEMY_MEDIUM, 1300.0, 0)
	_far(s, 302, TankIds.ENEMY_LIGHT, 950.0, 1)
	_near(s, 303, TankIds.ENEMY_RECON, 80.0, 0)
	s.enemy(303).mode = TankIds.EM_PAUSE
	s.next_id = 304
	return s


## Crew 4 at the caps, the wire's worst case: 8 far + 8 near enemies, 24 shells (12 far), large numbers
## (the 4 KB test and the perf gate).
static func _cap_v4() -> TankState:
	var s := _mission(4, SEG_ADVANCE_2, 60.0)
	s.tick = 49200
	s.t = s.tick * Wl.SIM_DT
	s.hull.x_px = 5000.0
	s.hull.speed_mps = 7.4
	s.hull.hp_max = 160.0
	s.hull.hp = 160.0
	s.hull.tow_s = 7.999
	_seat(s, s.riders[3], TankIds.ENGINE_REPAIR)
	var rp := s.station(TankIds.ENGINE_REPAIR) as TankRepairState
	rp.patches = 999
	rp.press_t = 0.999
	rp.duty = 0.999
	var far_kinds: Array[String] = TankIds.FAR_KINDS
	for i in 8:
		var e := _far(s, 1000 + i, far_kinds[i % far_kinds.size()], 2599.0 - 110.0 * i, i % 4)
		e.mode = TankIds.EM_TELEGRAPH
		e.telegraph_s = 3.999
	for i in 8:
		var kind := TankIds.ENEMY_RECON if i % 2 == 0 else TankIds.ENEMY_TANKETTE
		var e := _near(s, 1008 + i, kind, 20.0 + 21.0 * i, i % 2)
		e.mode = TankIds.EM_MOVE if i % 2 == 0 else TankIds.EM_PAUSE
	for i in TankConst.MAX_SHELLS:
		if i < 12:
			var r := 2400.0 - 110.0 * i
			var type := TankIds.SHELL_HEAVY if i % 2 == 0 else TankIds.SHELL_ENEMY
			var fs := _far_shell(2000 + i, type, i % 2 == 0, r, 0.4 + 0.2 * i)
			fs.evadable = i % 2 != 0
			s.shells.append(fs)
		else:
			var shell := TankFixtures._shell(
				2000 + i,
				TankIds.SHELL_BOW,
				s.hull.x_px + 300.0 + 12.0 * i,
				float(TankConst.GROUND_Y) - 40.0,
				360.0,
				-20.0,
				true
			)
			s.shells.append(shell)
	s.next_id = 3000
	return s


# --- Helpers -------------------------------------------------------------------------------------


static func _mission(crew: int, index: int, elapsed: float) -> TankState:
	var s := TankFixtures._base(TankFixtures.content(), crew, index, elapsed)
	s.seg.next_near = 0
	return s


static func _front(s: TankState) -> float:
	return s.hull.x_px + float(s.hull.hull_w)


## Appends a far enemy: range in metres, no px, side always +1.
static func _far(s: TankState, id: int, type: String, range_m: float, lane: int) -> TankEnemyState:
	var e := TankFixtures._enemy(id, type, 0.0, 0.0, 1)
	var def := s.content.enemy_def(type)
	e.hp_max = float(def["hp"]) * TankDifficulty.mult(s, "hp")
	e.hp = e.hp_max
	e.range_m = range_m
	e.hold_m = range_m
	e.lane = lane
	s.enemies.append(e)
	return e


## Appends a near threat `dist_px` rules px past the hull's front.
static func _near(s: TankState, id: int, type: String, dist_px: float, lane: int) -> TankEnemyState:
	var e := TankFixtures._enemy(id, type, _front(s) + dist_px, 0.0, 1)
	var def := s.content.enemy_def(type)
	e.hp_max = float(def["hp"]) * TankDifficulty.mult(s, "hp")
	e.hp = e.hp_max
	e.lane = lane
	s.enemies.append(e)
	return e


## A far shell at the range it flies over, `left_s` before it lands.
static func _far_shell(
	id: int, type: int, friendly: bool, range_m: float, left_s: float
) -> TankShellState:
	var s := TankShellState.new()
	s.id = id
	s.type = type
	s.friendly = friendly
	s.far = true
	var elev := TankBallistics.far_elevation(range_m, V0, G)
	var flight := TankBallistics.far_flight(elev, V0, G)
	s.set_meta(&"range_m", range_m)
	s.set_meta(&"flight_s", flight)
	_launch_far(s, range_m, flight)
	_tick_shell(s, flight - minf(left_s, flight))
	return s


## Puts a far shell at its start: ours at the hull flying out, theirs at `range_m` flying in.
static func _launch_far(s: TankShellState, range_m: float, flight: float) -> void:
	var elev := deg_to_rad(TankBallistics.far_elevation(range_m, V0, G))
	s.left_s = flight
	s.impact_r = range_m if s.friendly else 0.0
	s.x = 0.0 if s.friendly else range_m
	s.y = 0.0
	s.vx = V0 * cos(elev) * (1.0 if s.friendly else -1.0)
	s.vy = V0 * sin(elev)


## Moves rider `r` to seat `engine` by hand (the fixtures' seats, no rules).
static func _seat(s: TankState, r: TankRiderState, engine: String) -> void:
	var old := s.station(r.engine)
	if old != null and old.slot == r.slot:
		old.slot = -1
		old.peer = 0
	var st := s.station(engine)
	st.slot = r.slot
	st.peer = r.peer
	st.in_band = true
	r.engine = engine
	r.target_pct = 60.0 if engine == TankIds.ENGINE_REPAIR else 90.5

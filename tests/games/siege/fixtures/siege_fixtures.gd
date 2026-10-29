class_name SiegeFixtures
extends RefCounted
## Fixed Siege v2 states and snapshots for view, HUD, net and rules tests.
##
## mid_wave(): vo2 wave 2 (phase 4) 50 s in, 4 slots (humans 1, 2, 3 and Bot 1 at -1):
##   - slot 0 on the ballista (level 1) in Overdrive; slot 1 in rescue on the mine; slot 2
##     reconnecting to the arrow organ; the bot on the onager (level 2);
##   - pad 1 Scorpion L0, pad 2 Scorpion L2; the tar works level 1 with 80 HP of curtain and 210 L;
##   - 43 enemies on the path: spear blocks, shield bearers, chariots, a ram battering the gate and
##     a siege tower on the road;
##   - a 3-spawn queue, the gate at 72 / 155 (one Iron band), mine level 1, the Reserve flywheel.
## cap(): mid_wave() with 150 live enemies (the snapshot size test).
## snapshot(): fixtures/mid_wave_snapshot.json, SiegeSnapshot.encode(mid_wave()) as JSON (ints).

const DIR := "res://tests/games/siege/fixtures"
const SNAPSHOT_PATH := DIR + "/mid_wave_snapshot.json"


static func content(shift_id: String = "vo2") -> SiegeContent:
	return SiegeContent.from_dicts(SiegeContent.read_files(), shift_id)


## The four slots of the fixture (FTP 200, 220, 240 and the bot at 260; slot 1 unverified).
static func slots() -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	var peers: Array[int] = [1, 2, 3, -1]
	for i in 4:
		var s := PlayerSlot.new()
		s.peer_id = peers[i]
		s.is_bot = peers[i] < 0
		s.name = "Bot 1" if s.is_bot else "Rider %d" % peers[i]
		s.apply_look(i)
		s.ftp = 200.0 + 20.0 * i
		s.ftp_verified = i != 1
		s.autopilot = s.is_bot
		s.p_eff_per_w = 250.0 / s.ftp
		s.options = {"wave_offset": 0, "tilt_shift": true}
		out.append(s)
	return out


static func mid_wave(c: SiegeContent = null) -> SiegeState:
	if c == null:
		c = content("vo2")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var s := SiegeState.create(c, slots(), Wl.FAIR_FTP, rng)
	s.tick = 11000
	s.t = 550.0
	s.phase_index = 4
	s.role = SiegeIds.ROLE_WAVE
	s.wave_no = 2
	s.phase_kind = Wl.WORK
	s.phase_elapsed_s = 50.0
	s.phase_duration_s = 120.0
	s.phase_remaining_s = 70.0
	s.gate_hp = 72.0
	s.gate_max = 155.0
	s.iron_bands = 1
	s.mine_level = 1
	s.station(SiegeIds.STATION_MINE).level = 1
	s.perks = [SiegeIds.PERK_RESERVE]
	s.team_w = 912.0
	_station(s, SiegeIds.STATION_MINE, 0, 0.5, 0.0, 0.0, 0.3)
	_station(s, SiegeIds.STATION_BALLISTA, 1, 2.24, 0.62, 128.0, 0.62)
	_station(s, SiegeIds.STATION_ONAGER, 2, 0.96, 0.18, 142.5, 0.18)
	_station(s, SiegeIds.STATION_ARROWS, 0, 0.0, 0.4, 151.0, 0.4)
	_station(s, SiegeIds.STATION_TAR, 1, 0.0, 0.7, 0.0, 0.7)
	s.station(SiegeIds.STATION_ARROWS).rack = 1
	s.station(SiegeIds.STATION_BALLISTA).damage_wave = 360.0
	s.station(SiegeIds.STATION_ONAGER).damage_wave = 512.0
	s.station(SiegeIds.STATION_ARROWS).damage_wave = 96.0
	_pad(s, 1, 0, 0.8, 104.0)
	_pad(s, 2, 2, 1.6, 77.5)
	s.tar.curtain_max = s.curtain_max()
	s.tar.curtain_hp = 80.0
	s.tar.coat = 0.8
	s.tar.cauldron_l = 210.0
	var r0 := s.rider_at(0)
	r0.target = SiegeIds.STATION_BALLISTA
	r0.od_state = SiegeIds.OD_ACTIVE
	r0.od_s = 12.0
	r0.od_id = 9
	r0.p_eff_w = 300.0
	r0.raw_w = 240.0
	r0.cadence_rpm = 96.0
	r0.gold = 57.4
	var r1 := s.rider_at(1)
	r1.target = SiegeIds.STATION_MINE
	r1.rescue = true
	r1.p_eff_w = 125.0
	r1.raw_w = 110.0
	r1.cadence_rpm = 41.0
	r1.gold = 133.9
	r1.od_state = SiegeIds.OD_COOLDOWN
	r1.od_cd_s = 61.5
	var r2 := s.rider_at(2)
	r2.target = SiegeIds.STATION_ARROWS
	r2.reconnect_s = 1.2
	r2.p_eff_w = 262.0
	r2.raw_w = 252.0
	r2.cadence_rpm = 88.0
	r2.gold = 12.0
	var r3 := s.rider_at(3)
	r3.target = SiegeIds.STATION_ONAGER
	r3.p_eff_w = 240.0
	r3.raw_w = 250.0
	r3.cadence_rpm = 90.0
	r3.gold = 75.0
	for r in s.riders:
		r.route_fallback = r.is_bot
		r.shop_fallback = r.is_bot
	r3.autopilot = true
	var types: Array[int] = [
		SiegeIds.ENEMY_SPEAR, SiegeIds.ENEMY_SPEAR, SiegeIds.ENEMY_CHARIOT, SiegeIds.ENEMY_SHIELD
	]
	var id := 100
	for i in 41:
		var e := SiegeEnemyState.new()
		e.id = id
		id += 1
		e.type = types[i % types.size()]
		e.prog_m = snappedf(9.0 + i * 8.7, 0.1)
		e.lat_m = snappedf(rng.randf_range(-1.8, 1.8), 0.1)
		var def := c.enemy_def(e.type)
		e.max_hp = float(def["hp"])
		e.hp = ceilf(e.max_hp * (0.35 + 0.65 * float(i % 4) / 3.0))
		e.speed_mps = float(def["speed_mps"])
		e.place(s.path)
		s.enemies.append(e)
	var ram := SiegeEnemyState.new()
	ram.id = id
	id += 1
	ram.type = SiegeIds.ENEMY_RAM
	ram.prog_m = s.path.length_m
	ram.max_hp = 600.0
	ram.hp = 410.0
	ram.st = SiegeIds.EN_BATTER
	ram.reached = true
	ram.place(s.path)
	s.enemies.append(ram)
	var tower := SiegeEnemyState.new()
	tower.id = id
	id += 1
	tower.type = SiegeIds.ENEMY_TOWER
	tower.prog_m = 300.0
	tower.max_hp = 1800.0
	tower.hp = 1450.0
	tower.speed_mps = 0.5
	tower.place(s.path)
	s.enemies.append(tower)
	s.next_enemy_id = id
	for i in 3:
		var sp := SiegeSpawn.new()
		sp.type = SiegeIds.ENEMY_SPEAR
		sp.prog_m = 126.32
		sp.lat_m = (float(i) - 1.0) * 1.2
		s.queue.append(sp)
	s.wave.budget = 180.0
	s.wave.budget_left = 64.0
	s.wave.gate_damage = 58.0
	return s


## mid_wave() with 150 live enemies (shield bearers at 3- to 5-digit ids).
static func cap(c: SiegeContent = null) -> SiegeState:
	var s := mid_wave(c)
	var id := 10000
	while s.enemies.size() < 150:
		var e := SiegeEnemyState.new()
		e.id = id
		id += 7
		e.type = SiegeIds.ENEMY_SHIELD
		e.prog_m = 380.4 - float(s.enemies.size() % 90) * 3.9
		e.lat_m = -1.8
		e.max_hp = 40.0
		e.hp = 40.0
		e.speed_mps = 1.2
		e.place(s.path)
		s.enemies.append(e)
	return s


static func snapshot() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT_PATH))


static func _station(
	s: SiegeState, id: int, level: int, m: float, wind: float, yaw: float, arm: float
) -> void:
	var st := s.station(id)
	st.level = level
	st.m = m
	st.wind = wind
	st.yaw_deg = yaw
	st.arm = arm


static func _pad(s: SiegeState, n: int, level: int, cd: float, yaw: float) -> void:
	var pd := s.pad(n)
	pd.type = SiegeIds.PAD_SCORPION
	pd.level = level
	pd.cd_s = cd
	pd.yaw_deg = yaw

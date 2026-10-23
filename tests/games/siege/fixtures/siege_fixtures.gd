class_name SiegeFixtures
extends RefCounted
## Fixed Siege states and snapshots for view, HUD, net and rules tests (G0 contract).
##
## mid_wave(): vo2 wave 2 (phase 4) 50 s in, 4 slots (humans 1, 2, 3 and Bot 1 at -1), four
##   towers (pad 2 Caltrop L2, pad 3 Ballista L1, pad 4 Scorpion L0, pad 6 Ballista L3), 43
##   enemies on all three roads (every type; the 43rd a ram battering the gate), a landed zone,
##   3 shots, a 3-spawn queue, the gate at 72 / 125 (one Iron band), generator level 1, the
##   Reserve flywheel, slot 0 in Overdrive on pad 3, slot 1 in rescue on the generator, slot 2
##   reconnecting to pad 4, the bot on pad 2.
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
		s.options = {"wave_offset": 0}
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
	s.gate_max = 125.0
	s.iron_bands = 1
	s.gen_level = 1
	s.perks = [SiegeIds.PERK_RESERVE]
	s.team_w = 912.0
	s.breaches = 0
	_tower(s, 2, SiegeIds.TOWER_CALTROP, 2, 0.85, 1.2)
	_tower(s, 3, SiegeIds.TOWER_BALLISTA, 1, 1.68, 0.6)
	_tower(s, 4, SiegeIds.TOWER_SCORPION, 0, 0.0, 0.8)
	_tower(s, 6, SiegeIds.TOWER_BALLISTA, 3, 0.0, 2.0)
	var r0 := s.rider_at(0)
	r0.target = 3
	r0.od_state = SiegeIds.OD_ACTIVE
	r0.od_s = 12.0
	r0.od_id = 9
	r0.p_eff_w = 300.0
	r0.raw_w = 240.0
	r0.cadence_rpm = 96.0
	r0.denarii = 57.4
	var r1 := s.rider_at(1)
	r1.target = SiegeIds.TARGET_GEN
	r1.rescue = true
	r1.p_eff_w = 125.0
	r1.raw_w = 110.0
	r1.cadence_rpm = 41.0
	r1.denarii = 133.9
	r1.od_state = SiegeIds.OD_COOLDOWN
	r1.od_cd_s = 61.5
	var r2 := s.rider_at(2)
	r2.target = 4
	r2.reconnect_s = 1.2
	r2.p_eff_w = 262.0
	r2.raw_w = 252.0
	r2.cadence_rpm = 88.0
	r2.denarii = 12.0
	var r3 := s.rider_at(3)
	r3.target = 2
	r3.p_eff_w = 240.0
	r3.raw_w = 250.0
	r3.cadence_rpm = 90.0
	r3.denarii = 75.0
	r0.route_fallback = false
	r3.autopilot = true
	var types: Array[int] = [
		SiegeIds.ENEMY_RAIDERS,
		SiegeIds.ENEMY_RAIDERS,
		SiegeIds.ENEMY_HORSEMEN,
		SiegeIds.ENEMY_SHIELD_WALL
	]
	var id := 100
	for road in SiegeIds.ROAD_COUNT:
		var length := c.map.road_length(road)
		for i in 13 + road:
			var e := SiegeEnemyState.new()
			e.id = id
			id += 1
			e.type = types[(i + road) % types.size()]
			e.road = road
			e.prog_m = snappedf(fmod(9.0 + i * 7.3 + road * 2.1, length - 5.0), 0.1)
			e.lat_m = snappedf(rng.randf_range(-1.5, 1.5), 0.1)
			var def := c.enemy_def(e.type)
			e.max_hp = float(def["hp"])
			e.hp = ceilf(e.max_hp * (0.35 + 0.65 * float(i % 4) / 3.0))
			e.place(c.map)
			s.enemies.append(e)
	var ram := SiegeEnemyState.new()
	ram.id = id
	ram.type = SiegeIds.ENEMY_RAM
	ram.road = SiegeIds.ROAD_VALLEY
	ram.prog_m = c.map.road_length(SiegeIds.ROAD_VALLEY)
	ram.max_hp = 600.0
	ram.hp = 410.0
	ram.st = SiegeIds.EN_BATTER
	ram.place(c.map)
	s.enemies.append(ram)
	s.next_enemy_id = id + 1
	var z := SiegeZoneState.new()
	z.road = SiegeIds.ROAD_EAST
	z.prog_m = 80.0
	z.ttl_s = 2.5
	z.pad = 2
	z.amp = 1.25
	z.pos = c.map.point_at(z.road, z.prog_m)
	s.zones.append(z)
	for spec: Array in [
		[3, [s.enemies[3].id]],
		[4, [s.enemies[14].id, s.enemies[15].id, s.enemies[16].id]],
		[2, [s.enemies[30].id]]
	]:
		var shot := SiegeShot.new()
		shot.pad = int(spec[0])
		for t: Variant in spec[1]:
			shot.targets.append(int(t))
		s.shots.append(shot)
	for i in 3:
		var sp := SiegeSpawn.new()
		sp.type = SiegeIds.ENEMY_RAIDERS
		sp.road = i
		s.queue.append(sp)
	s.wave.active_roads = [0, 1, 2]
	s.wave.budget = 180.0
	s.wave.budget_left = 64.0
	return s


## mid_wave() with 150 live enemies (raiders on all roads at 3-digit to 5-digit ids).
static func cap(c: SiegeContent = null) -> SiegeState:
	var s := mid_wave(c)
	var id := 10000
	while s.enemies.size() < 150:
		var e := SiegeEnemyState.new()
		e.id = id
		id += 7
		e.type = SiegeIds.ENEMY_SHIELD_WALL
		e.road = s.enemies.size() % SiegeIds.ROAD_COUNT
		e.prog_m = 100.4 - float(s.enemies.size() % 90)
		e.lat_m = -1.5
		e.max_hp = 160.0
		e.hp = 160.0
		e.place(s.content.map)
		s.enemies.append(e)
	return s


static func snapshot() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT_PATH))


static func _tower(s: SiegeState, pad: int, type: int, level: int, m: float, cd: float) -> void:
	var tw := s.pad(pad)
	tw.type = type
	tw.level = level
	tw.m = m
	tw.cd_s = cd

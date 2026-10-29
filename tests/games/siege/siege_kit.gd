class_name SiegeKit
extends RefCounted
## Small helpers for the v2 rules tests: bare states, enemies placed on the path, progs inside a
## station's range band, the combat table.

const F := preload("res://tests/games/siege/siege_fakes.gd")


## A bare state of `shift` with `humans` + `bots` riders (all on the mine), seeded, in `role`
## (a WORK wave by default) with live stations.
static func state(
	shift: String = "short",
	humans: int = 1,
	bots: int = 0,
	rng_seed: int = 1,
	role: String = SiegeIds.ROLE_WAVE
) -> SiegeState:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var s := SiegeState.create(F.content(shift), F.make_slots(humans, bots), Wl.FAIR_FTP, rng)
	s.role = role
	s.phase_kind = Wl.WORK if role == SiegeIds.ROLE_WAVE else Wl.RECOVERY
	s.phase_index = 2
	s.phase_duration_s = 300.0
	s.phase_remaining_s = 300.0
	for r in s.riders:
		r.route_fallback = false
		r.shop_fallback = false
	return s


## A live enemy of `type` at `prog` (lateral `lat`), walking at its base speed; hp < 0: full HP.
static func enemy(
	s: SiegeState, type: int, prog: float, lat: float = 0.0, hp: float = -1.0
) -> SiegeEnemyState:
	var e := SiegeEnemyState.new()
	e.id = s.next_enemy_id
	s.next_enemy_id += 1
	e.type = type
	e.prog_m = prog
	e.lat_m = lat
	var def := s.content.enemy_def(type)
	e.max_hp = float(def.get("hp", 20.0))
	e.hp = e.max_hp if hp < 0.0 else hp
	e.speed_mps = float(def.get("speed_mps", 1.0))
	e.want_mps = e.speed_mps
	e.redraw_s = 100.0
	e.place(s.path)
	s.enemies.append(e)
	return e


## The progs (0.5 m apart) whose path point lies in station `id`'s band, in order.
static func band_progs(s: SiegeState, id: int) -> Array[float]:
	var out: Array[float] = []
	var p := 0.0
	while p <= s.path.length_m:
		if s.in_band(id, s.path.point_at(p)):
			out.append(p)
		p += 0.5
	return out


## A prog inside station `id`'s band (`frac` 0..1 along the covered progs; the middle by default).
static func prog_in_band(s: SiegeState, id: int, frac: float = 0.5) -> float:
	var all := band_progs(s, id)
	if all.is_empty():
		return -1.0
	return all[clampi(roundi(frac * (all.size() - 1)), 0, all.size() - 1)]


## A prog outside every weapon's band (-1 when none).
static func prog_out_of_reach(s: SiegeState) -> float:
	var p := 0.0
	while p <= s.path.length_m:
		var pt := s.path.point_at(p)
		var hit := false
		for id in SiegeIds.WEAPONS:
			hit = hit or s.in_band(id, pt)
		if not hit:
			return p
		p += 0.5
	return -1.0


## The first prog whose ground distance from station `id`'s pivot is within 0.5 m of `d`.
static func prog_at_dist(s: SiegeState, id: int, d: float) -> float:
	var at := s.path.station_pos[id]
	var p := 0.0
	while p <= s.path.length_m:
		if absf(s.path.ground_dist(at, p) - d) < 0.5:
			return p
		p += 0.1
	return -1.0


## The combat table of `s` now.
static func table(s: SiegeState) -> SiegeCombatTable:
	return SiegeCombatTable.of(s.content, s)


## Puts `peer` on station `id` at once (no reconnect), delivering `p_eff_w`.
static func put(s: SiegeState, peer: int, id: int, p_eff_w: float = 250.0) -> SiegeRiderState:
	var r := s.rider(peer)
	r.target = id
	r.reconnect_s = 0.0
	r.p_eff_w = p_eff_w
	r.raw_w = p_eff_w
	r.cadence_rpm = 90.0
	r.route_fallback = false
	r.shop_fallback = false
	return r


## Steps the combat alone `seconds` (no spawner input needed: a WORK wave phase info).
static func run_combat(s: SiegeState, seconds: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inp := SiegeInputs.new()
	inp.phase.kind = Wl.WORK
	inp.phase.role = s.role
	inp.phase.duration_s = 10000.0
	inp.phase.remaining_s = 10000.0
	for _i in roundi(seconds / Wl.SIM_DT):
		s.tick += 1
		inp.tick = s.tick
		out.append_array(SiegeCombat.step(s, inp, Wl.SIM_DT))
	return out


## Steps only the stations, the tar works, the pads and the projectiles `seconds` (nothing
## moves or spawns), so enemies stand where a test put them.
static func run_stations(s: SiegeState, seconds: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for _i in roundi(seconds / Wl.SIM_DT):
		s.tick += 1
		var tb := SiegeCombatTable.of(s.content, s)
		SiegeTarWorks.step(s, tb, Wl.SIM_DT)
		SiegeStations.step(s, tb, Wl.SIM_DT, out)
		SiegePads.step(s, tb, Wl.SIM_DT, out)
		SiegeProjectiles.step(s, tb, out)
	return out


## The events of `type` in `list`.
static func of_type(list: Array[Dictionary], type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in list:
		if str(e.get("type", "")) == type:
			out.append(e)
	return out

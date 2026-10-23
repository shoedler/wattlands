class_name SiegeTowers
extends RefCounted
## Tower output and fire (brief 2.4 "Tower output" and "Towers (P0)"). Pure and deterministic.
##
## Output: m = sum(P_eff x od) / 250 W over the riders delivering to the pad (od from
## SiegeOverdrive.multiplier), x1.4 after upgrade 1, capped at 4.0. An unpowered tower idles;
## Reserve flywheel keeps the last m for 10 s, Aqueduct drive gives m = 0.25. A Breach and every
## non-wave phase silence every tower, perks included.
##
## Fire: the cooldown cd_s counts down by dt x m (so the interval is base / m); at <= 0 the tower
## looks for targets (nearest the gate along its road first) and fires, carrying the overshoot.
## An armed tower with nothing in range scans again every tick. Hits resolve on the fire tick
## with damage = max(1, dmg - armor) (x1.25 inside an upgraded Caltrop zone); projectiles are
## visuals only (SiegeShot).
##   Ballista    30 dmg to the target nearest the gate; pierces up to 4 in a 1 m wide corridor on
##               the line of fire; upgrade 3 ignores armor.
##   Scorpion    10 dmg to each of the 3 enemies nearest the gate (5 with upgrade 3).
##   Caltrop     no damage: a 6 m zone lands after 1.0 s at the lead enemy's predicted spot for
##               4 s (40% slower, no stacking; upgrade 3: +25% damage taken inside).


## One tick of every pad. Kills go to `events`; each removed enemy bumps tb.removed.
static func step(
	state: SiegeState, tb: SiegeCombatTable, dt: float, events: Array[Dictionary]
) -> void:
	var live := state.in_wave() and state.phase_kind != Wl.COOLDOWN and state.breach_s <= 0.0
	for tw in state.pads:
		if not tw.built():
			continue
		tw.age_s = minf(tw.age_s + dt, 1000.0)
		if not live:
			tw.m = 0.0
			tw.hold_s = 0.0
			continue
		tw.m = output(state, tb, tw, dt)
		if tw.m <= 0.0:
			continue
		tw.cd_s -= dt * tw.m
		if tw.cd_s > 0.0:
			continue
		if _fire(state, tb, tw, events):
			tw.cd_s += float(tb.tower[tw.type].get("interval_s", 1.0))
		else:
			tw.cd_s = 0.0


## The output multiplier m of `tw` this tick (also updates the Reserve flywheel's hold).
static func output(
	state: SiegeState, tb: SiegeCombatTable, tw: SiegeTowerState, dt: float
) -> float:
	var sum := 0.0
	for r in state.riders:
		if r.target == tw.pad and r.delivering():
			sum += r.p_eff_w * SiegeOverdrive.multiplier(state, r, r.raw_w)
	if sum > 0.0:
		var m := sum / tb.ref_w
		if tw.level >= 1:
			m *= tb.out_mult
		m = minf(m, tb.m_cap)
		if tb.reserve:
			tw.hold_m = m
			tw.hold_s = tb.hold_s
		return m
	if tb.reserve and tw.hold_s > 0.0:
		tw.hold_s = maxf(tw.hold_s - dt, 0.0)
		return tw.hold_m
	if tb.aqueduct:
		return tb.aq_m
	return 0.0


static func _fire(
	state: SiegeState, tb: SiegeCombatTable, tw: SiegeTowerState, events: Array[Dictionary]
) -> bool:
	var def := tb.tower[tw.type]
	var reach := state.tower_range_m(tw.pad)
	var at := state.content.map.pad_pos(tw.pad)
	var riders := state.riders_on(tw.pad)
	var total := 0.0
	for r in riders:
		total += maxf(r.p_eff_w, 0.0)
	var hits: Array[SiegeEnemyState] = []
	match tw.type:
		SiegeIds.TOWER_BALLISTA:
			var lead := lead_enemies(state, tb, at, reach, 1)
			if lead.is_empty():
				return false
			hits = pierce(state, lead[0], at, reach, int(def.get("pierce", 1)), def)
			var ignore := tw.level >= 3 and str(def.get("special", "")) == "ignore_armor"
			for e in hits:
				_hit(state, tb, tw, riders, total, e, float(def["damage"]), ignore, events)
		SiegeIds.TOWER_SCORPION:
			var k := int(def.get("targets", 3))
			if tw.level >= 3:
				k = int(def.get("special_targets", k))
			hits = lead_enemies(state, tb, at, reach, k)
			if hits.is_empty():
				return false
			for e in hits:
				_hit(state, tb, tw, riders, total, e, float(def["damage"]), false, events)
		SiegeIds.TOWER_CALTROP:
			var lead := lead_enemies(state, tb, at, reach, 1)
			if lead.is_empty():
				return false
			hits = lead
			_throw(state, tb, tw, lead[0], def)
	var shot := SiegeShot.new()
	shot.pad = tw.pad
	for e in hits:
		shot.targets.append(e.id)
	state.shots.append(shot)
	return true


## The (up to) `k` live enemies within `reach` m of `at`, nearest the gate (least road left)
## first. Retreating enemies are not targets.
static func lead_enemies(
	state: SiegeState, tb: SiegeCombatTable, at: Vector2, reach: float, k: int
) -> Array[SiegeEnemyState]:
	var best: Array[SiegeEnemyState] = []
	var keys: Array[float] = []
	var r2 := reach * reach
	for e in state.enemies:
		if e.hp <= 0.0 or e.st == SiegeIds.EN_RETREAT:
			continue
		var dx := e.pos.x - at.x
		var dz := e.pos.y - at.y
		if dx * dx + dz * dz > r2:
			continue
		var rem := tb.road_len[e.road] - e.prog_m
		if best.size() == k and rem >= keys[k - 1]:
			continue
		var i := best.size()
		while i > 0 and keys[i - 1] > rem:
			i -= 1
		best.insert(i, e)
		keys.insert(i, rem)
		if best.size() > k:
			best.pop_back()
			keys.pop_back()
	return best


## The Ballista's bolt: `first` plus up to pierce - 1 more enemies on the line from the tower
## through it, inside the corridor (corridor_m wide) and within reach, nearest the tower first.
static func pierce(
	state: SiegeState,
	first: SiegeEnemyState,
	at: Vector2,
	reach: float,
	pierce: int,
	def: Dictionary
) -> Array[SiegeEnemyState]:
	var out: Array[SiegeEnemyState] = [first]
	if pierce <= 1:
		return out
	var dir := (first.pos - at).normalized()
	var half := float(def.get("corridor_m", 1.0)) * 0.5
	var r2 := reach * reach
	var extra: Array[SiegeEnemyState] = []
	var along: Array[float] = []
	for e in state.enemies:
		if e == first or e.hp <= 0.0 or e.st == SiegeIds.EN_RETREAT:
			continue
		var v := e.pos - at
		if v.length_squared() > r2:
			continue
		var t := v.dot(dir)
		if t <= 0.0 or absf(v.cross(dir)) > half:
			continue
		var i := extra.size()
		while i > 0 and along[i - 1] > t:
			i -= 1
		extra.insert(i, e)
		along.insert(i, t)
		if extra.size() > pierce - 1:
			extra.pop_back()
			along.pop_back()
	out.append_array(extra)
	return out


## The Caltrop thrower's zone: lands after zone_delay_s at where the lead enemy will be.
static func _throw(
	state: SiegeState,
	tb: SiegeCombatTable,
	tw: SiegeTowerState,
	lead: SiegeEnemyState,
	def: Dictionary
) -> void:
	var delay := float(def.get("zone_delay_s", 1.0))
	var ahead := tb.speed[lead.type] * lead.slow * delay if lead.st == SiegeIds.EN_WALK else 0.0
	var z := SiegeZoneState.new()
	z.road = lead.road
	z.prog_m = minf(lead.prog_m + ahead, tb.road_len[lead.road])
	z.delay_s = delay
	z.ttl_s = float(def.get("zone_s", 4.0))
	z.radius_m = float(def.get("zone_radius_m", 6.0))
	z.slow = 1.0 - float(def.get("slow", 0.4))
	z.amp = 1.0
	if tw.level >= 3 and str(def.get("special", "")) == "zone_amp":
		z.amp = 1.0 + float(def.get("zone_amp", 0.25))
	z.pad = tw.pad
	z.pos = state.content.map.point_at(z.road, z.prog_m)
	state.zones.append(z)


static func _hit(
	state: SiegeState,
	tb: SiegeCombatTable,
	tw: SiegeTowerState,
	riders: Array[SiegeRiderState],
	total: float,
	e: SiegeEnemyState,
	dmg: float,
	ignore_armor: bool,
	events: Array[Dictionary]
) -> void:
	var d := dmg if ignore_armor else maxf(1.0, dmg - tb.armor[e.type])
	d *= e.amp
	var dealt := minf(d, e.hp)
	e.hp -= d
	tw.damage += dealt
	if total > 0.0:
		for r in riders:
			r.damage += dealt * maxf(r.p_eff_w, 0.0) / total
	if e.hp > 0.0:
		return
	e.hp = 0.0
	tb.removed += 1
	tw.kills += 1
	var double := SiegeEconomy.pay_bounty(state, tw.pad, e.type, tb.bounty[e.type], e.rush)
	events.append(SiegeEvents.kill(e.id, e.type, tw.pad, e.road, double))
	if e.type == SiegeIds.ENEMY_RAM:
		_ram_down(state, e)


## A destroyed ram: counted as stopped when it never reached the gate; its crew scatter as
## Raiders just behind it.
static func _ram_down(state: SiegeState, ram: SiegeEnemyState) -> void:
	if ram.st == SiegeIds.EN_WALK:
		state.rams_stopped += 1
		state.wave.rams_stopped += 1
	var def := state.content.enemy_def(SiegeIds.ENEMY_RAM)
	var crew_type := SiegeIds.enemy_code(str(def.get("crew_type", "raiders")))
	var back := SiegeTune.wave_pair(state.content, "spawn.crew_back_m", Vector2(2, 8))
	for _i in int(def.get("crew", 6)):
		var at := maxf(ram.prog_m - state.rng.randf_range(back.x, back.y), 0.0)
		SiegeSpawner.enqueue(state, crew_type, ram.road, at, 1.0, false, true)

class_name SiegeProjectiles
extends RefCounted
## Simulated projectiles (brief 2.4 "Projectiles", "Stations", "Pads"). Pure, deterministic.
##
## fire(): the station's or pad's solved launch is quantized to the `shot` event's resolution
## (origin in cm, velocity in mm/s), a seed is drawn from state.rng, and each of the n projectiles
## takes its spread from SiegeHashRng(seed) through SiegeBallistics.shot_velocities, exactly as a
## client replays it. Stones and arrows fly ballistically to a landing decided at fire time
## (SiegeBallistics.land onto the aim point's ground height) and resolve after that many ticks;
## bolts fly tick by tick and hit the bodies their path passes.
##
## Damage = max(1, damage - armour); it lands at impact, never at fire time, so a target can die
## or move away before. Kills pay the bounty to the riders who delivered to the station when it
## fired, by their P_eff share (pads pay nothing), and credit their damage.
##   Bolt (ballista): 120 to the first body within 0.6 m of its path, then it keeps 75% after an
##     infantry body or 30% after an engine and flies on; it stops below 10 or at the ground.
##     Upgrade 3 ignores armour.
##   Stone (onager): at ground impact, 160 x (1 - 0.6 d / 5 m) to every enemy within 5 m (6.5 m
##     after upgrade 3); an engine within 2 m takes x2.5, a docked siege tower x1.5 more.
##   Arrow: 8 to the nearest enemy within 0.6 m (plus its body radius) of the landing point;
##     shield bearers block 70% of arrows (a second hash stream of the shot's seed).
##   Scorpion bolt: 10 to the first body its path passes, then it stops.

## The testudo's hash stream is the shot seed xor this.
const TESTUDO_SALT := 0x5bd1e995
## A bolt that has flown this many ticks without landing is dropped.
const MAX_BOLT_TICKS := 200


## Fires one shot from `src` (a station 1..3, or SRC_PAD + pad) with the lead solution `sol`
## (SiegeAim.lead) as `n` projectiles aimed at enemy `target_id`; appends the `shot` event.
static func fire(
	state: SiegeState,
	_tb: SiegeCombatTable,
	src: int,
	sol: Dictionary,
	n: int,
	target_id: int,
	events: Array[Dictionary]
) -> void:
	var kind := SiegeIds.SHOT_SCORPION if src > SiegeIds.SRC_PAD else SiegeIds.shot_kind(src)
	var def := _def(state, src)
	var o_cm := SiegeEvents.quantize_o(sol["o"])
	var v_mms := SiegeEvents.quantize_v(sol["v"])
	var sd := int(state.rng.randi() & 0x7fffffff) if state.rng != null else 1
	var ev := SiegeEvents.shot(state.tick, src, kind, o_cm, v_mms, n, sd)
	events.append(ev)
	var o := SiegeEvents.shot_origin(ev)
	var vs := SiegeBallistics.shot_velocities(
		SiegeEvents.shot_velocity(ev),
		n,
		sd,
		float(def.get("spread_deg", 0.0)),
		float(def.get("speed_spread", 0.0))
	)
	var k := float(def.get("k", 0.0))
	var aim: Vector3 = sol["aim"]
	var floor_z := aim.z - float(def.get("aim_dz_m", 0.0))
	var peers: Array[int] = []
	var shares: Array[float] = []
	if src < SiegeIds.SRC_PAD:
		var total := 0.0
		for r in state.riders_on(src):
			total += maxf(r.p_eff_w, 0.0)
		for r in state.riders_on(src):
			if total > 0.0 and r.p_eff_w > 0.0:
				peers.append(r.peer)
				shares.append(r.p_eff_w / total)
		state.station(src).shots += n
	else:
		state.pad(src - SiegeIds.SRC_PAD).shots += n
	var testudo := SiegeHashRng.new(sd ^ TESTUDO_SALT)
	for v in vs:
		var p := SiegeProjectile.new()
		p.kind = kind
		p.src = src
		p.pos = o
		p.vel = v
		p.k = k
		p.floor_z = floor_z
		p.target_id = target_id
		p.damage = float(def.get("damage", 1.0))
		p.peers = peers
		p.shares = shares
		match kind:
			SiegeIds.SHOT_BOLT, SiegeIds.SHOT_SCORPION:
				p.pierce = kind == SiegeIds.SHOT_BOLT
				p.ignore_armour = p.pierce and state.station(src).level >= 3
				p.ticks = MAX_BOLT_TICKS
			_:
				var l := SiegeBallistics.land(o, v, k, floor_z)
				p.pos = l["p"]
				p.ticks = int(l["steps"])
				if kind == SiegeIds.SHOT_ARROW:
					# Drawn in order at fire time, so the outcome never depends on the impact order.
					p.testudo = testudo.randf01() < float(def.get("testudo_block", 0.7))
		state.projectiles.append(p)


## One tick of every projectile in flight (fire order): bolts move and hit, stones and arrows
## count down and land.
static func step(state: SiegeState, tb: SiegeCombatTable, events: Array[Dictionary]) -> void:
	if state.projectiles.is_empty():
		return
	var kept: Array[SiegeProjectile] = []
	for p in state.projectiles:
		var flying := true
		match p.kind:
			SiegeIds.SHOT_BOLT, SiegeIds.SHOT_SCORPION:
				flying = _bolt(state, tb, p, events)
			_:
				p.ticks -= 1
				if p.ticks <= 0:
					if p.kind == SiegeIds.SHOT_STONE:
						_stone(state, tb, p, events)
					else:
						_arrow(state, tb, p, events)
					flying = false
		if flying:
			kept.append(p)
	state.projectiles = kept


## Drops every projectile in flight (a phase ends: they land on nothing).
static func clear(state: SiegeState) -> void:
	state.projectiles.clear()


## One tick of a bolt; false when it is spent (stopped by bodies, at the ground, or too old).
static func _bolt(
	state: SiegeState, tb: SiegeCombatTable, p: SiegeProjectile, events: Array[Dictionary]
) -> bool:
	var a := p.pos
	var nx := SiegeBallistics.step(p.pos, p.vel, p.k)
	var b: Vector3 = nx[0]
	p.vel = nx[1]
	p.ticks -= 1
	var grounded := b.z <= p.floor_z and p.vel.z < 0.0
	if grounded:
		var f := (a.z - p.floor_z) / maxf(a.z - b.z, 0.0001)
		b = a.lerp(b, clampf(f, 0.0, 1.0))
	p.pos = b
	var def := _def(state, p.src)
	var hit_r := float(def.get("hit_r_m", 0.6))
	var seg := b - a
	var seg2 := maxf(seg.length_squared(), 1e-9)
	var mid := (a + b) * 0.5
	var reach := sqrt(seg2) * 0.5 + hit_r + tb.max_body_r
	var hits: Array[SiegeEnemyState] = []
	var at: Array[float] = []
	for e in tb.near(state.enemies, mid.x, mid.y, reach):
		if p.hit_ids.has(e.id):
			continue
		var u := clampf((e.pos - a).dot(seg) / seg2, 0.0, 1.0)
		var c := a + seg * u
		var dx := c.x - e.pos.x
		var dy := c.y - e.pos.y
		var r := hit_r + tb.body_r[e.type]
		if dx * dx + dy * dy > r * r:
			continue
		if c.z < e.pos.z - 0.2 or c.z > e.pos.z + tb.body_h[e.type]:
			continue
		var i := hits.size()
		while i > 0 and at[i - 1] > u:
			i -= 1
		hits.insert(i, e)
		at.insert(i, u)
	for e in hits:
		p.hit_ids.append(e.id)
		hit(state, tb, e, p.damage, p, events)
		if not p.pierce:
			return false
		var keep := "keep_engine" if SiegeIds.is_engine(e.type) else "keep_infantry"
		p.damage *= float(def.get(keep, 0.75))
		if p.damage < float(def.get("stop_below", 10.0)):
			return false
	return not grounded and p.ticks > 0


static func _stone(
	state: SiegeState, tb: SiegeCombatTable, p: SiegeProjectile, events: Array[Dictionary]
) -> void:
	var def := _def(state, p.src)
	var st := state.station(p.src)
	var radius := float(def.get("special_splash_m" if st.level >= 3 else "splash_m", 5.0))
	var falloff := float(def.get("falloff", 0.6))
	var direct := float(def.get("engine_direct_m", 2.0))
	for e in tb.near(state.enemies, p.pos.x, p.pos.y, radius):
		var d := Vector2(e.pos.x - p.pos.x, e.pos.y - p.pos.y).length()
		var dmg := p.damage * (1.0 - falloff * d / radius)
		if SiegeIds.is_engine(e.type) and d <= direct:
			dmg *= float(def.get("engine_mult", 2.5))
		if e.type == SiegeIds.ENEMY_TOWER and e.st == SiegeIds.EN_DOCKED:
			dmg *= float(def.get("docked_mult", 1.5))
		hit(state, tb, e, dmg, p, events)


static func _arrow(
	state: SiegeState, tb: SiegeCombatTable, p: SiegeProjectile, events: Array[Dictionary]
) -> void:
	var hit_r := float(_def(state, p.src).get("hit_r_m", 0.6))
	var best: SiegeEnemyState = null
	var best_d := INF
	for e in tb.near(state.enemies, p.pos.x, p.pos.y, hit_r + tb.max_body_r):
		var d := Vector2(e.pos.x - p.pos.x, e.pos.y - p.pos.y).length() - tb.body_r[e.type]
		if d <= hit_r and d < best_d:
			best = e
			best_d = d
	if best == null:
		return
	if best.type == SiegeIds.ENEMY_SHIELD and p.testudo:
		return
	hit(state, tb, best, p.damage, p, events)


## Applies `dmg` from projectile `p` to `e` (armour taken off unless p ignores it; at least 1):
## the station's and riders' damage, and on a kill the bounty, the kill event, a ram's crew.
static func hit(
	state: SiegeState,
	tb: SiegeCombatTable,
	e: SiegeEnemyState,
	dmg: float,
	p: SiegeProjectile,
	events: Array[Dictionary]
) -> void:
	if e.hp <= 0.0:
		return
	var d := dmg if p.ignore_armour else maxf(1.0, dmg - tb.armour[e.type])
	var dealt := minf(d, e.hp)
	e.hp -= d
	var pad := p.src > SiegeIds.SRC_PAD
	if not p.hit:
		p.hit = true
		if pad:
			state.pad(p.src - SiegeIds.SRC_PAD).hits += 1
		else:
			state.station(p.src).hits += 1
	if pad:
		state.pad(p.src - SiegeIds.SRC_PAD).damage += dealt
	else:
		var st := state.station(p.src)
		st.damage_wave += dealt
		st.damage_total += dealt
		for i in p.peers.size():
			var r := state.rider(p.peers[i])
			if r != null:
				r.damage += dealt * p.shares[i]
	if e.hp > 0.0:
		return
	e.hp = 0.0
	tb.removed += 1
	var double := false
	if pad:
		state.pad(p.src - SiegeIds.SRC_PAD).kills += 1
	else:
		state.station(p.src).kills += 1
		double = SiegeEconomy.pay_bounty(
			state, p.peers, p.shares, e.type, tb.bounty[e.type], state.rush_on()
		)
	events.append(SiegeEvents.kill(e.id, e.type, p.src, double))
	if SiegeIds.is_engine(e.type):
		_engine_down(state, e)


## A destroyed siege engine: counted as stopped when it never reached the gate or docked; a ram's
## crew scatter as spearmen just behind it.
static func _engine_down(state: SiegeState, e: SiegeEnemyState) -> void:
	if not e.reached:
		state.engines_stopped += 1
		state.wave.engines_stopped += 1
	if e.type != SiegeIds.ENEMY_RAM:
		return
	var def := state.content.enemy_def(SiegeIds.ENEMY_RAM)
	var crew_type := SiegeIds.enemy_code(str(def.get("crew_type", "spear")))
	var back := SiegeTune.wave_pair(state.content, "engines.crew_back_m", Vector2(2, 6))
	var lat := float(state.content.enemies.get("lateral_m", 1.8))
	for _i in int(def.get("crew", 6)):
		var at := maxf(e.prog_m - state.rng.randf_range(back.x, back.y), 0.0)
		var side := state.rng.randf_range(-lat, lat)
		SiegeSpawner.enqueue(state, crew_type, at, side, 1.0, false, true)


static func _def(state: SiegeState, src: int) -> Dictionary:
	if src > SiegeIds.SRC_PAD:
		return state.content.pad_def(state.pad(src - SiegeIds.SRC_PAD).type)
	return state.content.station_def(src)

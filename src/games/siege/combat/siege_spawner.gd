class_name SiegeSpawner
extends RefCounted
## The wave director on the one road (brief 2.4 "Waves"): groups from the staging grounds in
## ranks, the siege engines, endurance rushes, the warm-up wave's rules and the 150-enemy cap
## with its queue. Pure and deterministic: every draw goes through state.rng in a fixed order.
##
## Spawns never create enemies directly: they go to state.queue and drain() moves them into
## state.enemies up to the cap, so the queue is the only path (FIFO) and the snapshot's q counts
## what waits. An engine's spawn raises its `push` event.
##
## Groups: every 6..12 s (seeded) until 60 s before the wave ends, a group adds its share of the
## budget B still to come (the budget left over the groups left, x 0.8..1.2) to an account; while
## the account covers the next formation's threat, that formation enters. Formations are drawn so
## the expected threat split equals the mix row of the shift's current third: spear blocks
## (4 wide x 3 deep, 1.2 m apart), shield groups (3 x 2), chariot pairs (6 m apart). A formation
## enters at the furthest staging ground (camp, palm grove, wadi) from which it still reaches the
## gate 30 s before the wave ends at its speed; if none can, it doesn't spawn and its threat is
## dropped.
##
## Siege engines (scheduled at the wave start, ADR "engine entry"): each enters where it reaches
## the moat edge push_lead_s (60) before the wave ends at its own speed; one ram for 1-2 slots, two
## 25 m apart (centred on that point) for 3-4; the siege tower alone in the last wave of a shift
## whose waves are >= 300 s; an engine whose point would lie before the camp enters at the camp
## later instead. Escort spearmen worth 10 threat per slot enter behind them. The warm-up wave: one
## ram at half HP, no escort.


## Sets up state.wave for a wave that just started (the budget is already in state.wave).
static func begin_wave(state: SiegeState, ph: SiegePhaseInfo) -> void:
	var w := state.wave
	w.spawn_in_s = SiegeTune.wave_num(state.content, "first_group_s", 3.0)
	w.engines = engine_plan(state, ph)


## The wave's siege engines: [[type, enter_at_s, prog_m, hp_frac, escort_threat], ...] in entry
## order (see the class notes).
static func engine_plan(state: SiegeState, ph: SiegePhaseInfo) -> Array:
	var c := state.content
	var path := state.path
	var dur := ph.duration_s
	var lead := SiegeTune.wave_num(c, "engines.push_lead_s", 60.0)
	var type := SiegeIds.ENEMY_RAM
	var count := 1
	var hp_frac := 1.0
	var escort := (
		SiegeTune.wave_num(c, "engines.escort_threat_per_slot", 10.0) * state.riders.size()
	)
	if ph.role == SiegeIds.ROLE_WARMUP_WAVE:
		hp_frac = SiegeTune.wave_num(c, "warmup.ram_hp_frac", 0.5)
		if not bool((c.waves.get("warmup", {}) as Dictionary).get("ram_escort", false)):
			escort = 0.0
	elif ph.last_wave and dur >= SiegeTune.wave_num(c, "engines.tower_min_wave_s", 300.0):
		type = SiegeIds.ENEMY_TOWER
	elif state.riders.size() >= int(SiegeTune.wave_num(c, "engines.two_rams_from_slots", 3.0)):
		count = 2
	var speed := float(c.enemy_def(type).get("speed_mps", 0.8))
	var gap := SiegeTune.wave_num(c, "engines.pair_gap_m", 25.0)
	var out: Array = []
	for i in count:
		var ahead := (float(i) - float(count - 1) * 0.5) * gap
		var prog := path.moat_edge_m - speed * maxf(dur - lead, 0.0) + ahead
		var at := 0.0
		if prog < 0.0:
			at = -prog / speed
			prog = 0.0
		out.append([type, at, minf(prog, path.moat_edge_m - 1.0), hp_frac, escort / count])
	out.sort_custom(_by_entry)
	return out


static func _by_entry(a: Array, b: Array) -> bool:
	return float(a[1]) < float(b[1])


## One tick of the director (waves only; breaks and the cool-down spawn nothing).
static func step(
	state: SiegeState,
	inputs: SiegeInputs,
	tb: SiegeCombatTable,
	dt: float,
	_events: Array[Dictionary]
) -> void:
	var ph := inputs.phase
	if not state.in_wave() or ph.is_cooldown():
		return
	var stop := SiegeTune.wave_num(state.content, "stop_before_end_s", 60.0)
	_teach(state)
	_engines(state, ph, tb)
	_groups(state, ph, tb, stop, dt)
	_rush(state, ph, tb, dt, _events)


## Moves queued spawns into state.enemies while fewer than the cap are alive.
static func drain(state: SiegeState, tb: SiegeCombatTable, events: Array[Dictionary]) -> void:
	var q := state.queue
	if q.is_empty():
		return
	var taken := 0
	while taken < q.size() and state.enemies.size() < tb.cap:
		_spawn(state, tb, q[taken], events)
		taken += 1
	for _i in taken:
		q.pop_front()
	if taken > 0:
		tb.invalidate()


## Queues one body.
static func enqueue(
	state: SiegeState,
	type: int,
	prog_m: float,
	lat_m: float = 0.0,
	hp_frac: float = 1.0,
	escort: bool = false,
	crew: bool = false,
	rush: bool = false,
	push: bool = false
) -> void:
	var sp := SiegeSpawn.new()
	sp.type = type
	sp.prog_m = prog_m
	sp.lat_m = lat_m
	sp.hp_frac = hp_frac
	sp.escort = escort
	sp.crew = crew
	sp.rush = rush
	sp.push = push
	state.queue.append(sp)


## The mix row [spear, shield, chariot] now (fractions summing to 1): the warm-up wave's own
## rule (spearmen only for 180 s, then chariots too), else the phase's mix in the shift's third.
static func mix_row(state: SiegeState, ph: SiegePhaseInfo) -> Array[float]:
	if state.role == SiegeIds.ROLE_WARMUP_WAVE:
		if ph.elapsed_s < SiegeTune.wave_num(state.content, "warmup.spear_only_s", 180.0):
			return [1.0, 0.0, 0.0]
		return third_row(state, SiegeIds.MIX_RAIDERS_HORSEMEN, ph.plan_elapsed_s)
	return third_row(state, ph.mix, ph.plan_elapsed_s)


## The mix row `mix` of waves.json for the third of the shift that `plan_t` seconds falls in.
static func third_row(state: SiegeState, mix: String, plan_t: float) -> Array[float]:
	var row: Array[float] = [1.0, 0.0, 0.0]
	var total := maxf(SiegePlanBuilder.total_s(state.content.shift), 1.0)
	var third := clampi(int(plan_t / total * 3.0), 0, 2)
	var rows: Array = (state.content.waves.get("mix", {}) as Dictionary).get(mix, [])
	if third < rows.size() and rows[third] is Array and (rows[third] as Array).size() == 3:
		row = [float(rows[third][0]), float(rows[third][1]), float(rows[third][2])]
	return row


## The threat of one formation of `type` (files x ranks x the body's threat).
static func formation_threat(state: SiegeState, tb: SiegeCombatTable, type: int) -> float:
	var rk := _ranks(state, type)
	return float(rk.x * rk.y) * tb.threat[type]


## The staging ground's prog a body of `type` enters from at wave second `elapsed` so it still
## reaches the gate `reach_before_end_s` (30) before the wave ends: the furthest from the gate
## that works, or -1.
static func staging_for(
	state: SiegeState, tb: SiegeCombatTable, type: int, elapsed: float, duration: float
) -> float:
	var margin := SiegeTune.wave_num(state.content, "staging.reach_before_end_s", 30.0)
	var v := maxf(tb.speed[type], 0.01)
	var best := INF
	for s in state.path.staging:
		if elapsed + (tb.length_m - s) / v <= duration - margin + 1e-6 and s < best:
			best = s
	return best if best < INF else -1.0


## Draws the next formation type for `row` (weights = fraction / formation threat, so the
## expected threat split equals the row); 0 when the row is empty.
static func draw_type(state: SiegeState, tb: SiegeCombatTable, row: Array[float]) -> int:
	var weights: Array[float] = [0.0, 0.0, 0.0]
	var total := 0.0
	for i in 3:
		if row[i] > 0.0:
			weights[i] = row[i] / formation_threat(state, tb, SiegeIds.MIX_ORDER[i])
			total += weights[i]
	if total <= 0.0:
		return 0
	var pick := state.rng.randf_range(0.0, total)
	for i in 3:
		if weights[i] > 0.0 and pick < weights[i]:
			return SiegeIds.MIX_ORDER[i]
		pick -= weights[i]
	for i in range(2, -1, -1):
		if weights[i] > 0.0:
			return SiegeIds.MIX_ORDER[i]
	return 0


## Queues one formation of `type` at its staging ground; `index` places it behind the earlier
## formations of the same group. False when no staging ground can reach the gate in time.
static func place_formation(
	state: SiegeState, tb: SiegeCombatTable, ph: SiegePhaseInfo, type: int, index: int, rush: bool
) -> bool:
	var at := staging_for(state, tb, type, ph.elapsed_s, ph.duration_s)
	if at < 0.0:
		return false
	var rk := _ranks(state, type)
	var spacing := float(state.content.enemy_def(type).get("spacing_m", 1.2))
	var depth := float(rk.y - 1) * spacing
	var gap := SiegeTune.wave_num(state.content, "staging.formation_gap_m", 3.0)
	var front := at + depth + float(index) * (depth + gap)
	for r in rk.y:
		for f in rk.x:
			var lat := (float(f) - float(rk.x - 1) * 0.5) * spacing
			if rk.x == 1:
				lat = state.rng.randf_range(-tb.lateral_m, tb.lateral_m)
			enqueue(
				state,
				type,
				minf(front - float(r) * spacing, tb.length_m - 1.0),
				lat,
				1.0,
				false,
				false,
				rush
			)
	return true


static func _ranks(state: SiegeState, type: int) -> Vector2i:
	var rk: Variant = state.content.enemy_def(type).get("ranks", [1, 1])
	if rk is Array and (rk as Array).size() == 2:
		return Vector2i(maxi(int(rk[0]), 1), maxi(int(rk[1]), 1))
	return Vector2i(1, 1)


static func _teach(state: SiegeState) -> void:
	if state.role != SiegeIds.ROLE_WARMUP_WAVE:
		return
	var every := SiegeTune.wave_num(state.content, "warmup.toast_every_s", 60.0)
	state.wave.toast_min = floori(state.phase_elapsed_s / every + 1e-9) + 1


static func _engines(state: SiegeState, ph: SiegePhaseInfo, tb: SiegeCombatTable) -> void:
	var w := state.wave
	while not w.engines.is_empty() and float(w.engines[0][1]) <= ph.elapsed_s + 1e-6:
		var en: Array = w.engines.pop_front()
		var type := int(en[0])
		var prog := float(en[2])
		enqueue(state, type, prog, 0.0, float(en[3]), false, false, false, true)
		var n := roundi(float(en[4]) / maxf(tb.threat[SiegeIds.ENEMY_SPEAR], 0.01))
		var files := _ranks(state, SiegeIds.ENEMY_SPEAR).x
		var spacing := float(state.content.enemy_def(SiegeIds.ENEMY_SPEAR).get("spacing_m", 1.2))
		var back := tb.body_r[type] + 2.0
		for i in n:
			var f := i % files
			var r := i / files
			var lat := (float(f) - float(files - 1) * 0.5) * spacing
			var at := maxf(prog - back - float(r) * spacing, 0.0)
			enqueue(state, SiegeIds.ENEMY_SPEAR, at, lat, 1.0, true)


static func _groups(
	state: SiegeState, ph: SiegePhaseInfo, tb: SiegeCombatTable, stop: float, dt: float
) -> void:
	var w := state.wave
	w.spawn_in_s -= dt
	if w.spawn_in_s > 0.0 or ph.remaining_s <= stop:
		return
	var gap := SiegeTune.wave_pair(state.content, "group_every_s", Vector2(6, 12))
	w.spawn_in_s = state.rng.randf_range(gap.x, gap.y)
	if w.budget_left <= 1e-6:
		return
	var span := ph.remaining_s - stop
	var share := w.budget_left
	if w.spawn_in_s < span:
		var left_groups := floorf(span / ((gap.x + gap.y) * 0.5)) + 1.0
		var v := SiegeTune.wave_pair(state.content, "group_var", Vector2(0.8, 1.2))
		share = minf(w.budget_left / left_groups * state.rng.randf_range(v.x, v.y), w.budget_left)
	w.budget_left = maxf(w.budget_left - share, 0.0)
	w.group_acc += share
	var row := mix_row(state, ph)
	var index := 0
	while true:
		if w.next_type == 0 or row[SiegeIds.MIX_ORDER.find(w.next_type)] <= 0.0:
			w.next_type = draw_type(state, tb, row)
		if w.next_type == 0:
			return
		var ft := formation_threat(state, tb, w.next_type)
		if w.group_acc < ft - 1e-6:
			return
		w.group_acc -= ft
		if not place_formation(state, tb, ph, w.next_type, index, false):
			w.dropped += ft
		index += 1
		w.next_type = 0


static func _rush(
	state: SiegeState,
	ph: SiegePhaseInfo,
	tb: SiegeCombatTable,
	dt: float,
	events: Array[Dictionary]
) -> void:
	var w := state.wave
	var dur := state.content.num("rush.duration_s", 30.0)
	var step_s := SiegeTune.wave_num(state.content, "rush.group_every_s", 3.0)
	if w.rush_s > 0.0:
		w.rush_s = snappedf(w.rush_s - dt, 0.001)
		if w.rush_s <= 0.0:
			w.rush_s = 0.0
			_rush_group(state, tb, ph, dur, step_s, dur)
			events.append(SiegeEvents.rush(false, w.rush_next - 1))
		else:
			var idx := floori((dur - w.rush_s) / step_s + 1e-6)
			var prev := floori((dur - w.rush_s - dt) / step_s + 1e-6)
			if idx != prev:
				_rush_group(state, tb, ph, dur - w.rush_s, step_s, dur)
		return
	if w.rush_next >= ph.rushes_at_s.size() or ph.elapsed_s < ph.rushes_at_s[w.rush_next]:
		return
	var amount := minf(state.content.num("rush.budget_frac", 0.08) * w.budget, w.budget_left)
	w.budget_left -= amount
	w.rush_budget_left = amount
	w.rush_acc = 0.0
	w.rush_s = dur
	w.rush_next += 1
	events.append(SiegeEvents.rush(true, w.rush_next - 1))
	_rush_group(state, tb, ph, 0.0, step_s, dur)


## One rush group: its share of the rush budget (the last takes the rest) in spearmen and
## chariot formations (waves.json rush.types), marked as rush bodies.
static func _rush_group(
	state: SiegeState,
	tb: SiegeCombatTable,
	ph: SiegePhaseInfo,
	elapsed: float,
	step_s: float,
	dur: float
) -> void:
	var w := state.wave
	var total := maxi(roundi(dur / step_s), 1)
	var idx := floori(elapsed / step_s + 1e-6)
	var last := idx >= total - 1 or elapsed >= dur - 1e-6
	var share := w.rush_budget_left if last else w.rush_budget_left / float(total - idx)
	w.rush_budget_left = maxf(w.rush_budget_left - share, 0.0)
	w.rush_acc += share
	var row := third_row(state, SiegeIds.MIX_RAIDERS_HORSEMEN, ph.plan_elapsed_s)
	var allowed: Array[int] = []
	for t: Variant in (state.content.waves.get("rush", {}) as Dictionary).get("types", []):
		allowed.append(SiegeIds.enemy_code(str(t)))
	for i in 3:
		if not allowed.has(SiegeIds.MIX_ORDER[i]):
			row[i] = 0.0
	var index := 0
	while true:
		if w.rush_type == 0:
			w.rush_type = draw_type(state, tb, row)
		if w.rush_type == 0:
			return
		var ft := formation_threat(state, tb, w.rush_type)
		if w.rush_acc < ft - 1e-6:
			return
		w.rush_acc -= ft
		if not place_formation(state, tb, ph, w.rush_type, index, true):
			w.dropped += ft
		index += 1
		w.rush_type = 0


static func _spawn(
	state: SiegeState, tb: SiegeCombatTable, sp: SiegeSpawn, events: Array[Dictionary]
) -> void:
	var e := SiegeEnemyState.new()
	e.id = state.next_enemy_id
	state.next_enemy_id += 1
	e.type = sp.type
	e.prog_m = sp.prog_m
	e.lat_m = sp.lat_m
	e.max_hp = tb.hp[sp.type]
	e.hp = e.max_hp * sp.hp_frac
	e.escort = sp.escort
	e.crew = sp.crew
	e.rush = sp.rush
	e.speed_mps = tb.speed[sp.type]
	if e.type == SiegeIds.ENEMY_CHARIOT:
		var def := state.content.enemy_def(SiegeIds.ENEMY_CHARIOT)
		SiegeCombat.redraw_chariot(state, e, def, tb.speed[e.type])
		e.speed_mps = e.want_mps
	e.place(state.path)
	state.enemies.append(e)
	if sp.push:
		state.wave.engines_in += 1
		state.engines_total += 1
		events.append(SiegeEvents.push(e.id, e.type, e.prog_m))

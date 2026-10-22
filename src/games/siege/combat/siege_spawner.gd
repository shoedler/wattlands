class_name SiegeSpawner
extends RefCounted
## The wave director (brief 2.4 "Waves"): groups, active roads and their rotation, the ram push,
## endurance rushes, the warm-up wave's rules and the 150-enemy cap with its queue. Pure and
## deterministic: every draw goes through state.rng in a fixed order.
##
## Spawns never create enemies directly: they go to state.queue and drain() moves them into
## state.enemies up to the cap, so the queue is the only path (FIFO) and the snapshot's q counts
## what waits.
##
## Group threat: the wave's budget B is spread over the groups still to come (6..12 s apart,
## seeded, until 60 s before the wave ends); a group's types are drawn so the expected threat
## split equals the mix row of the shift's current third (70/10/20, 50/25/25, 40/30/30), and
## unspent threat stays in the budget.


## Sets up state.wave for a wave that just started (the budget is already in state.wave).
static func begin_wave(state: SiegeState) -> void:
	var w := state.wave
	var n := clampi(state.riders.size(), 1, SiegeIds.ROAD_COUNT)
	w.active_roads = roads_for(n)
	w.next_roads = []
	w.horn_s = 0.0
	w.spawn_in_s = SiegeTune.wave_num(state.content, "spawn.first_group_s", 3.0)
	w.rotate_in_s = _rotate_gap(state) if n < SiegeIds.ROAD_COUNT else 0.0


## The road ids active at the start of a wave with `n` active roads (Valley first).
static func roads_for(n: int) -> Array[int]:
	var out: Array[int] = []
	var order: Array[int] = [SiegeIds.ROAD_VALLEY, SiegeIds.ROAD_WEST, SiegeIds.ROAD_EAST]
	for i in clampi(n, 0, SiegeIds.ROAD_COUNT):
		out.append(order[i])
	out.sort()
	return out


## One tick of the director (waves only; breaks and the cool-down spawn nothing).
static func step(
	state: SiegeState,
	inputs: SiegeInputs,
	tb: SiegeCombatTable,
	dt: float,
	events: Array[Dictionary]
) -> void:
	var ph := inputs.phase
	if not state.in_wave() or ph.is_cooldown():
		return
	var stop := float(state.content.waves.get("stop_before_end_s", 60.0))
	_teach(state)
	_rotate(state, ph, stop, dt, events)
	_groups(state, ph, tb, stop, dt)
	_push(state, ph, tb, events)
	_rush(state, ph, tb, dt, events)


## Moves queued spawns into state.enemies while fewer than the cap are alive.
static func drain(state: SiegeState, tb: SiegeCombatTable) -> void:
	var q := state.queue
	if q.is_empty():
		return
	var taken := 0
	while taken < q.size() and state.enemies.size() < tb.cap:
		_spawn(state, tb, q[taken])
		taken += 1
	for _i in taken:
		q.pop_front()


## Queues one spawn.
static func enqueue(
	state: SiegeState,
	type: int,
	road: int,
	prog_m: float,
	hp_frac: float = 1.0,
	escort: bool = false,
	crew: bool = false,
	rush: bool = false
) -> void:
	var sp := SiegeSpawn.new()
	sp.type = type
	sp.road = road
	sp.prog_m = prog_m
	sp.hp_frac = hp_frac
	sp.escort = escort
	sp.crew = crew
	sp.rush = rush
	state.queue.append(sp)


## The mix row [raiders, shield wall, horsemen] now (fractions summing to 1): the warm-up wave's
## own rule, else the phase's mix in the shift's current third.
static func mix_row(state: SiegeState, ph: SiegePhaseInfo) -> Array[float]:
	var row: Array[float] = [1.0, 0.0, 0.0]
	if state.role == SiegeIds.ROLE_WARMUP_WAVE:
		var only_s := SiegeTune.wave_num(state.content, "warmup.raiders_only_s", 180.0)
		if ph.elapsed_s >= only_s:
			row = [0.0, 0.0, 1.0]
		return row
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


## Enemy types for `threat` points of a mix `row`, restricted to `allowed` (empty: all). Sets
## `spent[0]` to the threat they cost (<= threat).
static func compose(
	state: SiegeState,
	tb: SiegeCombatTable,
	row: Array[float],
	threat: float,
	allowed: Array[int],
	spent: Array[float]
) -> Array[int]:
	var types: Array[int] = []
	var weights: Array[float] = [0.0, 0.0, 0.0]
	var total_w := 0.0
	var cheapest := INF
	for i in 3:
		var code := SiegeIds.MIX_ORDER[i]
		if row[i] <= 0.0 or (not allowed.is_empty() and not allowed.has(code)):
			continue
		weights[i] = row[i] / tb.threat[code]
		total_w += weights[i]
		cheapest = minf(cheapest, tb.threat[code])
	var left := threat
	spent[0] = 0.0
	if total_w <= 0.0:
		return types
	var guard := 0
	while left >= cheapest - 1e-6 and guard < 100000:
		guard += 1
		var pick := state.rng.randf_range(0.0, 1.0) * total_w
		var idx := 2
		for i in 3:
			if weights[i] > 0.0 and pick < weights[i]:
				idx = i
				break
			pick -= weights[i]
		while weights[idx] <= 0.0:
			idx = (idx + 1) % 3
		var code := SiegeIds.MIX_ORDER[idx]
		if tb.threat[code] > left + 1e-6:
			# Too dear for what is left: the cheapest allowed type fills the gap.
			for i in 3:
				if weights[i] > 0.0 and tb.threat[SiegeIds.MIX_ORDER[i]] <= cheapest + 1e-9:
					code = SiegeIds.MIX_ORDER[i]
		types.append(code)
		left -= tb.threat[code]
	spent[0] = threat - left
	return types


static func _teach(state: SiegeState) -> void:
	if state.role != SiegeIds.ROLE_WARMUP_WAVE:
		return
	var every := SiegeTune.wave_num(state.content, "warmup.toast_every_s", 60.0)
	state.wave.toast_min = floori(state.phase_elapsed_s / every + 1e-9) + 1


## Seconds until the horn: the seeded 30..60 s between road changes, less the horn's own 5 s, so
## the roads switch 30..60 s apart.
static func _rotate_gap(state: SiegeState) -> float:
	var p := SiegeTune.wave_pair(state.content, "roads.rotate_s", Vector2(30, 60))
	var horn := SiegeTune.wave_num(state.content, "roads.horn_s", 5.0)
	return maxf(state.rng.randf_range(p.x, p.y) - horn, 0.0)


static func _rotate(
	state: SiegeState, ph: SiegePhaseInfo, stop: float, dt: float, events: Array[Dictionary]
) -> void:
	var w := state.wave
	if state.riders.size() >= SiegeIds.ROAD_COUNT:
		return
	var horn := SiegeTune.wave_num(state.content, "roads.horn_s", 5.0)
	if w.horn_s > 0.0:
		w.horn_s = snappedf(w.horn_s - dt, 0.001)
		if w.horn_s <= 0.0:
			w.horn_s = 0.0
			w.active_roads = w.next_roads.duplicate()
			w.next_roads = []
			w.rotate_in_s = _rotate_gap(state)
		return
	if ph.remaining_s <= stop + horn:
		return
	w.rotate_in_s = snappedf(w.rotate_in_s - dt, 0.001)
	if w.rotate_in_s > 0.0:
		return
	var n := w.active_roads.size()
	var options: Array[Array] = []
	for a in SiegeIds.ROAD_COUNT:
		if n == 1:
			if [a] != w.active_roads:
				options.append([a])
		else:
			for b in range(a + 1, SiegeIds.ROAD_COUNT):
				if [a, b] != w.active_roads:
					options.append([a, b])
	var pick: Array = options[state.rng.randi_range(0, options.size() - 1)]
	var next: Array[int] = []
	for r: Variant in pick:
		next.append(int(r))
	w.next_roads = next
	w.horn_s = horn
	events.append(SiegeEvents.roads(next, roundi(horn * 1000.0)))


static func _groups(
	state: SiegeState, ph: SiegePhaseInfo, tb: SiegeCombatTable, stop: float, dt: float
) -> void:
	var w := state.wave
	w.spawn_in_s -= dt
	if w.spawn_in_s > 0.0 or ph.remaining_s <= stop:
		return
	var gap := SiegeTune.wave_pair(state.content, "group_every_s", Vector2(6, 12))
	w.spawn_in_s = state.rng.randf_range(gap.x, gap.y)
	var min_threat := INF
	for code in range(1, SiegeIds.ENEMY_NAMES.size() - 1):
		min_threat = minf(min_threat, tb.threat[code])
	if w.budget_left < min_threat - 1e-6:
		return
	var span := ph.remaining_s - stop
	var left_groups := floorf(span / ((gap.x + gap.y) * 0.5)) + 1.0
	var threat := w.budget_left
	if w.spawn_in_s < span:
		var v := SiegeTune.wave_pair(state.content, "spawn.group_var", Vector2(0.8, 1.2))
		threat = minf(w.budget_left / left_groups * state.rng.randf_range(v.x, v.y), w.budget_left)
	var spent: Array[float] = [0.0]
	var types := compose(state, tb, mix_row(state, ph), threat, [], spent)
	w.budget_left = maxf(w.budget_left - spent[0], 0.0)
	_place_group(state, types, false)


## Queues `types` on random active roads near the spawn.
static func _place_group(state: SiegeState, types: Array[int], rush: bool) -> void:
	var w := state.wave
	if w.active_roads.is_empty():
		return
	var spread := SiegeTune.wave_num(state.content, "spawn.spread_m", 4.0)
	for t in types:
		var road := w.active_roads[state.rng.randi_range(0, w.active_roads.size() - 1)]
		enqueue(state, t, road, state.rng.randf_range(0.0, spread), 1.0, false, false, rush)


static func _push(
	state: SiegeState, ph: SiegePhaseInfo, tb: SiegeCombatTable, events: Array[Dictionary]
) -> void:
	var w := state.wave
	var c := state.content
	if w.push_done or ph.remaining_s > SiegeTune.wave_num(c, "ram_push.at_left_s", 60.0):
		return
	w.push_done = true
	var roads: Array[int] = w.active_roads.duplicate()
	if roads.is_empty():
		return
	var escorted := true
	var hp_frac := 1.0
	if state.role == SiegeIds.ROLE_WARMUP_WAVE:
		roads = [roads[0]]
		hp_frac = SiegeTune.wave_num(c, "warmup.ram_hp_frac", 0.5)
		escorted = bool((c.waves.get("warmup", {}) as Dictionary).get("ram_escort", false))
	var enter := SiegeTune.wave_num(c, "ram_push.enter_from_gate_m", 40.0)
	var back := SiegeTune.wave_pair(c, "spawn.escort_back_m", Vector2(2, 12))
	var per_slot := SiegeTune.wave_num(c, "ram_push.escort_threat_per_slot", 10.0)
	var escort_n := 0
	if escorted:
		escort_n = roundi(per_slot * state.riders.size() / tb.threat[SiegeIds.ENEMY_RAIDERS])
	for i in roads.size():
		var road := roads[i]
		var at := maxf(tb.road_len[road] - enter, 0.0)
		enqueue(state, SiegeIds.ENEMY_RAM, road, at, hp_frac, true)
		var n := escort_n / roads.size() + (1 if i < escort_n % roads.size() else 0)
		for _k in n:
			var behind := state.rng.randf_range(back.x, back.y)
			enqueue(state, SiegeIds.ENEMY_RAIDERS, road, maxf(at - behind, 0.0), 1.0, true)
	w.rams += roads.size()
	state.rams_total += roads.size()
	events.append(SiegeEvents.push(roads))


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
			_rush_group(state, tb, dur, step_s, dur)
			events.append(SiegeEvents.rush(false, w.rush_next - 1))
		else:
			var idx := floori((dur - w.rush_s) / step_s + 1e-6)
			var prev := floori((dur - w.rush_s - dt) / step_s + 1e-6)
			if idx != prev:
				_rush_group(state, tb, dur - w.rush_s, step_s, dur)
		return
	if w.rush_next >= ph.rushes_at_s.size() or ph.elapsed_s < ph.rushes_at_s[w.rush_next]:
		return
	var amount := minf(state.content.num("rush.budget_frac", 0.08) * w.budget, w.budget_left)
	w.budget_left -= amount
	w.rush_budget_left = amount
	w.rush_s = dur
	w.rush_next += 1
	events.append(SiegeEvents.rush(true, w.rush_next - 1))
	_rush_group(state, tb, 0.0, step_s, dur)


## One rush group: the rush budget over the groups still to come (the last takes the rest).
static func _rush_group(
	state: SiegeState, tb: SiegeCombatTable, elapsed: float, step_s: float, dur: float
) -> void:
	var w := state.wave
	if w.rush_budget_left <= 0.0:
		return
	var total := maxi(roundi(dur / step_s), 1)
	var idx := floori(elapsed / step_s + 1e-6)
	var last := idx >= total - 1 or elapsed >= dur - 1e-6
	var threat := w.rush_budget_left if last else w.rush_budget_left / float(total - idx)
	var allowed: Array[int] = []
	for t: Variant in (state.content.waves.get("rush", {}) as Dictionary).get("types", []):
		allowed.append(SiegeIds.enemy_code(str(t)))
	var row := third_row(state, SiegeIds.MIX_RAIDERS_HORSEMEN, state.t)
	var spent: Array[float] = [0.0]
	var types := compose(state, tb, row, threat, allowed, spent)
	w.rush_budget_left = maxf(w.rush_budget_left - spent[0], 0.0)
	_place_group(state, types, true)


static func _spawn(state: SiegeState, tb: SiegeCombatTable, sp: SiegeSpawn) -> void:
	var e := SiegeEnemyState.new()
	e.id = state.next_enemy_id
	state.next_enemy_id += 1
	e.type = sp.type
	e.road = sp.road
	e.prog_m = sp.prog_m
	e.lat_m = snappedf(state.rng.randf_range(-tb.lateral_m, tb.lateral_m), 0.1)
	e.max_hp = tb.hp[sp.type]
	e.hp = e.max_hp * sp.hp_frac
	e.escort = sp.escort
	e.crew = sp.crew
	e.rush = sp.rush
	e.place(state.content.map)
	state.enemies.append(e)

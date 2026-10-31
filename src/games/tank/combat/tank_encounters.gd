class_name TankEncounters
extends RefCounted
## What stands in each segment (brief 2.4 mission P0, 2.9; v4): the Advance's obstacles and its fixed
## encounter list keyed by metres driven (far kinds through TankFar, near kinds through TankNear), a
## holding action's force (the UI's name for a gun line) and its props, near threats by seconds into a
## holding action or the boss fight, the Behemoth, the depot's drill wrecks. Counts scale with the crew
## and difficulty.count (TankContent.crew_count). No random spawns: the mission file lists everything,
## so the plan builder knows every segment before the ride starts. Owner: rules (combat).


## A new segment began (TankSegments.track): clears the previous one's world and sets this one up.
## `prev_seg` / `overran`: the segment that ended and whether the platform cut it at max_s (a gun
## line cut short falls to a support barrage: its remaining guns die with no kill credit).
static func begin(
	state: TankState, aux: TankAux, prev_seg: String, overran: bool, events: Array[Dictionary]
) -> void:
	var hull := state.hull
	var gl := state.gun_line
	var barrage := overran and prev_seg == TankIds.SEG_GUN_LINE
	if barrage:
		for e in state.enemies.duplicate():
			if e.gun_line:
				TankShells.kill_enemy(state, aux, e, TankEvents.BY_BARRAGE, -1, events)
	gl.barrage = barrage
	gl.guns_total = 0
	gl.guns_left = 0
	state.enemies.clear()
	state.shells.clear()
	state.obstacles.clear()
	aux.enemy_vx.clear()
	aux.enemy_dist.clear()
	aux.enemy_age.clear()
	aux.enemy_leaving.clear()
	aux.enemy_shots.clear()
	aux.shell_left.clear()
	aux.manual_target = false
	aux.enemy_flank_done.clear()
	aux.enemy_shift.clear()
	aux.near_left.clear()
	aux.near_lane = 0
	aux.boss_rate_mps = 0.0
	state.seg.next_near = 0
	aux.evade.clear()
	aux.drill_wrecks = false
	hull.berm_hp = 0.0
	hull.berm_j = 0.0
	hull.blocked_by = 0
	hull.traps_cleared = false
	hull.target_id = 0
	var c := state.content
	var seg := c.segment(state.seg.segment_index)
	aux.drills = seg.get("drills", [])
	match state.seg.seg:
		TankIds.SEG_ADVANCE, TankIds.SEG_SKIRMISH:
			for o: Variant in seg.get("obstacles", []):
				if not _meets(state, o):
					continue
				var at_px := TankConst.m_to_px(float(o.get("at_m", 0.0)))
				add_obstacle(state, str(o.get("type", TankIds.OBST_WIRE)), at_px)
		TankIds.SEG_GUN_LINE:
			_gun_line(state, aux, seg)
		TankIds.SEG_BOSS:
			TankBoss.start(state, aux, events)
		TankIds.SEG_COOLDOWN:
			TankBoss.withdraw(state, aux, events)


## Adds an obstacle or prop of `type` with its left edge at world x `x_px`.
static func add_obstacle(state: TankState, type: String, x_px: float) -> TankObstacleState:
	var o := TankObstacleState.new()
	o.id = state.take_id()
	o.code = TankIds.obstacle_code(type)
	o.x_px = x_px
	o.w = int(state.content.num("tanks", "props.%s.w" % type, 64.0))
	state.obstacles.append(o)
	return o


## A holding action: entries {enemy, count, hold_m: [..], min_crew?}; every one is on the move at long
## range and counts toward the objective.
static func _gun_line(state: TankState, aux: TankAux, seg: Dictionary) -> void:
	var total := 0
	var specs: Array = seg.get("enemies", [])
	var counts := crew_counts(state, specs)
	for k in specs.size():
		var spec: Dictionary = specs[k]
		var type := str(spec.get("enemy", ""))
		var at: Array = spec.get("hold_m", [])
		for i in counts[k]:
			var hold := float(at[mini(i, at.size() - 1)]) if not at.is_empty() else -1.0
			if TankFar.spawn(state, aux, type, hold, true, -1) != null:
				total += 1
	state.gun_line.guns_total = total
	state.gun_line.guns_left = total
	var front := float(state.hull.hull_w)
	for p: Variant in seg.get("props", []):
		add_obstacle(
			state, str(p.get("type", TankIds.OBST_TANK_TRAPS)), front + float(p.get("at_px", 40))
		)


## Advance and skirmish: spawns the encounters the tank has driven up to.
static func advance(state: TankState, aux: TankAux, events: Array[Dictionary]) -> void:
	var sg := state.seg
	if sg.seg != TankIds.SEG_ADVANCE and sg.seg != TankIds.SEG_SKIRMISH:
		return
	var list: Array = state.content.segment(sg.segment_index).get("encounters", [])
	var counts := crew_counts(state, list)
	while sg.next_encounter < list.size():
		var enc: Dictionary = list[sg.next_encounter]
		if state.hull.distance_m < float(enc.get("at_m", 0.0)):
			return
		var type := str(enc.get("enemy", ""))
		for _i in counts[sg.next_encounter]:
			# Each copy rolls its own hold.
			if TankIds.NEAR_KINDS.has(type):
				TankNear.spawn(state, aux, type, sg.next_encounter, events)
			else:
				TankFar.spawn(state, aux, type, -1.0, false, sg.next_encounter)
		sg.next_encounter += 1


## A holding action and the boss fight: near threats burst from the bushes by seconds into the segment
## (its "near" list, {at_s, enemy, count, min_crew?}).
static func near_step(state: TankState, aux: TankAux, events: Array[Dictionary]) -> void:
	var sg := state.seg
	if (sg.seg != TankIds.SEG_GUN_LINE and sg.seg != TankIds.SEG_BOSS) or sg.objective_done:
		return
	var list: Array = state.content.segment(sg.segment_index).get("near", [])
	if sg.next_near >= list.size():
		return
	var counts := crew_counts(state, list)
	while sg.next_near < list.size():
		var enc: Dictionary = list[sg.next_near]
		if sg.elapsed_s < float(enc.get("at_s", 0.0)):
			return
		for _i in counts[sg.next_near]:
			TankNear.spawn(state, aux, str(enc.get("enemy", "")), -1, events)
		sg.next_near += 1


## True when the crew meets entry `e` at all: its optional min_crew (v3 solo balance: the smallest
## crew it shows up for, default 1) is at most the crew's size.
static func _meets(state: TankState, e: Variant) -> bool:
	return state.crew >= int((e as Dictionary).get("min_crew", 1))


## (v3, brief "Difficulty is enemy count") How many of each entry of a segment's list (encounters
## or gun-line enemies, {enemy, count}) the crew meets: the segment's total count x the crew's scale
## (TankContent.crew_count: 0.5 / 0.7 / 0.85 / 1.0 for crews 1-4, x difficulty.count, rounded, at
## least 1), taken from the entries in their order (a later entry gets what is left, maybe 0), so a
## list puts first what the smallest crews must still meet. A total raised above the list by
## difficulty.count goes to the last entries, one each, the lightest and latest first.
static func crew_counts(state: TankState, entries: Array) -> Array[int]:
	var total := 0
	for e: Variant in entries:
		if _meets(state, e):
			total += int(e.get("count", 1))
	var mult := TankDifficulty.mult(state, "count")
	var left := (
		state.content.crew_count(total, state.hull.tank, state.crew, mult) if total > 0 else 0
	)
	var out: Array[int] = []
	for e: Variant in entries:
		var n := mini(int(e.get("count", 1)), left) if _meets(state, e) else 0
		left -= n
		out.append(n)
	while left > 0:
		for k in range(entries.size() - 1, -1, -1):
			if left > 0 and _meets(state, entries[k]):
				out[k] += 1
				left -= 1
	return out


## The depot's aim drill: its wrecks stand ahead of the halted tank once the drill starts.
static func depot_wrecks(state: TankState, aux: TankAux) -> void:
	if state.seg.seg != TankIds.SEG_DEPOT or aux.drill_wrecks:
		return
	for d: Variant in aux.drills:
		if str(d.get("drill", "")) != "aim" or state.seg.elapsed_s < float(d.get("from_s", 0.0)):
			continue
		aux.drill_wrecks = true
		var front := state.hull.x_px + state.hull.hull_w
		var px: Array = state.content.value("tanks", "drill.wreck_px", [135, 170])
		for i in int(d.get("targets", 2)):
			add_obstacle(state, TankIds.OBST_DRILL_WRECK, front + float(px[mini(i, px.size() - 1)]))
		return

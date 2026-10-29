class_name TankPlanBuilder
extends RefCounted
## Every rider's EffortPlan from the mission's segments and stations.json (brief 2.3, v3 effort
## table). Owner: effort (the v3 rules builder keeps it).
##
## - Every rider gets one lap-true phase per mission segment, with the same kinds and lengths, so
##   every boundary is shared and phase_changed means the same segment for everyone. Open-ended
##   segments (Advance, gun line, boss, roam) carry min_s / max_s; the PlanValidator appends the
##   cool-down (180 s at 50%), never this builder.
## - The phase's mode and numbers come from the rider's seat (stations.json <plan_table>.<engine>.
##   <segment type>; checkpoints use the table's "checkpoint" entry, ERG 50% for everyone).
## - Seats: every slot starts on its start seat (stations.json start_engines, a crew of n takes the
##   first n) and keeps it for the whole plan. v3 retired rotation: a rider changes seats with the
##   seat intent, and each move replans the rest of that rider's plan (TankSeatPlan.tail).
## - PlanPhase.meta: {"seg": TankIds.SEG_*, "stage": int, "segment": mission segment index,
##   "engine": TankIds.ENGINE_*, "mission": id}, plus "seg_min_s" (the segment's own min_s) for an
##   open-ended segment (TankInputs reads it).
## - An open-ended phase's min_s is the segment's min_s, or its "plan_min_s" where the mission has
##   one (free roam: TankConst.SEAT_LOCK_S, so a seat switch can split the hour-long roam phase; the
##   game reads the segment's own min_s from seg_min_s).
## - Labels come from the mission file (TANK_PHASE_* keys).


## {peer_id: EffortPlan} for every slot.
static func build_all(content: TankContent, players: Array[PlayerSlot]) -> Dictionary:
	var plans := {}
	var tank := TankIds.tank_for_crew(players.size())
	for p in players:
		plans[p.peer_id] = build(content, tank, p.slot_index)
	return plans


## One slot's plan (no cool-down).
static func build(content: TankContent, tank: String, slot: int) -> EffortPlan:
	var plan := EffortPlan.new()
	var segs := content.segments()
	var engine := engine_for(content, tank, slot)
	for i in segs.size():
		plan.add(phase_for(content, segs[i], engine, i))
	return plan


## The seat `slot` starts on (and, until a seat intent moves it, works in every segment).
static func engine_for(content: TankContent, tank: String, slot: int) -> String:
	var start := content.start_engines(tank)
	return start[slot] if slot >= 0 and slot < start.size() else ""


## The PlanPhase of mission segment `s` (index `index`) for a rider on `engine`.
static func phase_for(content: TankContent, s: Dictionary, engine: String, index: int) -> PlanPhase:
	var type := str(s.get("type", ""))
	var kind := str(s.get("kind", Wl.WORK))
	var duration := float(s.get("duration_s", 0.0))
	var label := str(s.get("label", ""))
	var entry := content.plan_entry(engine, type)
	if entry.is_empty():
		# The schema requires every entry (TankContentSchema.TABLE_SEGMENTS); never guess one.
		push_error("tank: no stations.json plan entry for %s in %s" % [engine, type])
	var ph: PlanPhase
	if str(entry.get("mode", Wl.ERG)) == Wl.SIM:
		ph = PlanPhase.sim(kind, str(entry.get("grade_source", Wl.GRADE_FLAT)), duration, label)
	else:
		ph = PlanPhase.erg(kind, float(entry.get("target_pct", 50.0)), duration, label)
		if entry.has("ramp_to_pct"):
			ph.with_ramp(float(entry["ramp_to_pct"]))
		if entry.get("range_pct") is Array:
			ph.with_range(float(entry["range_pct"][0]), float(entry["range_pct"][1]))
	var meta := {
		"seg": type,
		"stage": int(s.get("stage", 0)),
		"segment": index,
		"engine": engine,
		"mission": content.mission_id
	}
	if s.has("min_s") and s.has("max_s"):
		ph.with_open(float(s.get("plan_min_s", s["min_s"])), float(s["max_s"]))
		meta["seg_min_s"] = float(s["min_s"])
	ph.with_lap()
	ph.with_meta(meta)
	return ph


## The segment type of plan phase `index` ("" past the end: the cool-down).
static func seg_of(plan: EffortPlan, index: int) -> String:
	if plan == null or index < 0 or index >= plan.size():
		return ""
	return str(plan.phase(index).meta.get("seg", ""))

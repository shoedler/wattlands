class_name TankPlanBuilder
extends RefCounted
## Every rider's EffortPlan from the mission's segments and stations.json (brief 2.3). Owner:
## effort (G0 wrote this complete first version; effort keeps it and adds the plan tests).
##
## - Every rider gets one lap-true phase per mission segment, with the same kinds and lengths, so
##   every boundary is shared and phase_changed means the same segment for everyone. Open-ended
##   segments (Advance, gun line, boss) carry min_s / max_s; the PlanValidator appends the
##   cool-down (180 s at 50%), never this builder.
## - The phase's mode and numbers come from the rider's engine in that segment
##   (stations.json <plan_table>.<engine>.<segment type>; checkpoints use the table's
##   "checkpoint" entry, ERG 50% for everyone).
## - Engines: the depot (stage 0) and every drill segment use the slot's start engine; stage n
##   uses rotation[n - 1] and the boss rotation[3] when rotation is on (the "rotation" option and
##   the mission's "rotation" flag), else the start engine; a checkpoint already carries the
##   engine of the segment after it (the crew moves at the checkpoint). Rotation is fixed at the
##   start: Tank never calls replan.
## - PlanPhase.meta: {"seg": TankIds.SEG_*, "stage": int, "segment": mission segment index,
##   "engine": TankIds.ENGINE_*, "mission": id} (TankPhaseInfo reads it).
## - Labels come from the mission file (TANK_PHASE_* keys).


## {peer_id: EffortPlan} for every slot.
static func build_all(
	content: TankContent, players: Array[PlayerSlot], rotation: bool
) -> Dictionary:
	var plans := {}
	var tank := TankIds.tank_for_crew(players.size())
	for p in players:
		plans[p.peer_id] = build(content, tank, p.slot_index, rotation)
	return plans


## One slot's plan (no cool-down).
static func build(content: TankContent, tank: String, slot: int, rotation: bool) -> EffortPlan:
	var plan := EffortPlan.new()
	var segs := content.segments()
	for i in segs.size():
		var s: Dictionary = segs[i]
		var engine := engine_for(content, tank, slot, i, rotation)
		plan.add(phase_for(content, s, engine, i))
	return plan


## The engine `slot` works in mission segment `index`.
static func engine_for(
	content: TankContent, tank: String, slot: int, index: int, rotation: bool
) -> String:
	var start := content.start_engines(tank)
	var start_engine: String = start[slot] if slot >= 0 and slot < start.size() else ""
	if not rotation or not content.mission_rotates():
		return start_engine
	var segs := content.segments()
	var s: Dictionary = segs[index]
	var type := str(s.get("type", ""))
	var stage := int(s.get("stage", 0))
	if type == TankIds.SEG_CHECKPOINT and index + 1 < segs.size():
		return engine_for(content, tank, slot, index + 1, rotation)
	if stage < 1:
		return start_engine
	var row := content.rotation_row(tank, slot)
	return row[clampi(stage, 1, 4) - 1] if row.size() >= 4 else start_engine


## The PlanPhase of mission segment `s` (index `index`) for a rider on `engine`.
static func phase_for(content: TankContent, s: Dictionary, engine: String, index: int) -> PlanPhase:
	var type := str(s.get("type", ""))
	var kind := str(s.get("kind", Wl.WORK))
	var duration := float(s.get("duration_s", 0.0))
	var label := str(s.get("label", ""))
	var entry := content.plan_entry(engine, type)
	var ph: PlanPhase
	if str(entry.get("mode", Wl.ERG)) == Wl.SIM:
		ph = PlanPhase.sim(kind, str(entry.get("grade_source", Wl.GRADE_FLAT)), duration, label)
	else:
		ph = PlanPhase.erg(kind, float(entry.get("target_pct", 50.0)), duration, label)
		if entry.has("ramp_to_pct"):
			ph.with_ramp(float(entry["ramp_to_pct"]))
		if entry.get("range_pct") is Array:
			ph.with_range(float(entry["range_pct"][0]), float(entry["range_pct"][1]))
	if s.has("min_s") and s.has("max_s"):
		ph.with_open(float(s["min_s"]), float(s["max_s"]))
	ph.with_lap()
	ph.with_meta(
		{
			"seg": type,
			"stage": int(s.get("stage", 0)),
			"segment": index,
			"engine": engine,
			"mission": content.mission_id
		}
	)
	return ph


## The segment type of plan phase `index` ("" past the end: the cool-down).
static func seg_of(plan: EffortPlan, index: int) -> String:
	if plan == null or index < 0 or index >= plan.size():
		return ""
	return str(plan.phase(index).meta.get("seg", ""))

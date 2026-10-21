class_name TemplateGame
extends GameModule
## The template game (BRIEF 3.6; tools/new_game copies it, docs/GAME_SDK.md walks through it).
## Each rider pushes a marker along a lane: a 5-minute warm-up ramp (50 -> 65% FTP), one 3-minute WORK
## phase at 75% FTP with a +5% "hill", a lap marker, results; "short" adds course_grade, replan, end_phase.

var state: Dictionary = {}
var content: Dictionary = {}
var _last_index: Dictionary = {}
var _done: Dictionary = {}


## Every peer, first. Content goes through ctx.load_content_json so run_game_sim --override works.
func configure(p_ctx: GameContext) -> void:
	super.configure(p_ctx)
	var c: Variant = ctx.load_content_json("%s.json" % ctx.content_id)
	var err := TemplateRules.content_error(c)
	if err != "":
		push_error("_template: content %s: %s" % [ctx.content_id, err])
		return
	content = c
	state = TemplateRules.new_state(content, ctx.peers(), float(ctx.options.get("track", 400)))
	for rd: Dictionary in state["riders"]:
		rd["dist_m"] = ctx.rng.randf_range(0.0, 2.0)  # ctx.rng is the only randomness


## Host/SOLO: one plan per slot, bots included (WORK targets take the rider's work_offset; "sim": true is
## a SIM phase the game feeds with course_grade). The PlanValidator checks each and appends the cool-down.
func build_effort_plans() -> Dictionary:
	var plans := {}
	if content.is_empty():
		return plans  # invalid content: no plans, so the session does not start
	for p in ctx.players:
		var plan := EffortPlan.new()
		for d: Dictionary in content["phases"]:
			var ph := PlanPhase.erg(str(d["kind"]), float(d.get("target_pct", 0)), float(d["duration_s"]), str(d["label"])) \
				.with_ramp(float(d.get("ramp_to_pct", PlanPhase.NONE))).with_lap()
			if d.get("sim", false):
				ph = PlanPhase.sim(ph.kind, Wl.GRADE_GAME, ph.duration_s, ph.label).with_lap()
			if ph.kind == Wl.WORK:
				ph.target_pct += clampf(float(p.options.get("work_offset", 0)), -10.0, 5.0)
				ph.with_range(ph.target_pct, ph.target_pct + float(content["nudge_pct"]))
			plan.add(ph)
		plans[p.peer_id] = plan
	return plans


## Host/SOLO, every 0.05 s of game time, through the cool-down too.
func sim_step(dt: float, frame: InputFrame) -> void:
	var inputs := {}
	for p in ctx.players:
		var tm := frame.telemetry(p.peer_id)
		var boost := tm != null and bool(ctx.options.get("boosts", true)) and tm.intents.any(func(it: Variant) -> bool: return it is Dictionary and str(it.get("k", "")) == "boost")
		inputs[p.peer_id] = {"p_eff_w": tm.p_eff_w if tm != null else 0.0, "boost": boost}
		_phase_rules(p, frame.phase_of(p.peer_id), tm)
	for e: Dictionary in TemplateRules.step(state, inputs, dt):
		send_event(e)  # clients raise their own toasts in apply_event; the host does it here
		if e["type"] == "lap" and TemplateRules.rider(state, null, int(e["slot"])).get("peer") == ctx.local_peer:
			ctx.hud.toast("_TEMPLATE_LAP_DONE", [e["laps"]], ctx.local_peer)
	ctx.hud.readout("laps", str(TemplateRules.rider(state, ctx.local_peer).get("laps", 0)))


func _phase_rules(p: PlayerSlot, ph: PhaseState, tm: Telemetry) -> void:
	if ph == null:
		return
	var peer := p.peer_id
	var in_band := tm != null and absf(tm.power_w - tm.applied_target_w) <= 0.05 * tm.applied_target_w
	if ph.index != int(_last_index.get(peer, -1)):
		_last_index[peer] = ph.index  # the group's phase is the lowest: phase_changed once every rider reached it
		if _last_index.size() == ctx.players.size() and _first("group%d" % _last_index.values().min()):
			phase_changed.emit(_last_index.values().min())
		if ph.kind == Wl.WORK:  # the gauge's band (drawn while in SIM) and a cadence band
			ctx.hud.power_band(peer, 0.70 * p.ftp, 0.80 * p.ftp)
			ctx.directives.cadence_band(peer, 80.0, 100.0)
		if not p.is_bot: ctx.hud.banner("_TEMPLATE_BANNER_PHASE", [ctx.strings.t(ph.label)], 3.0, peer)  # its own phase only
		if ph.index == int(content.get("replan_at", -1)):  # the rest of the plan, validated like the first
			ctx.directives.replan(peer, EffortPlan.of([PlanPhase.erg(Wl.WORK, 55, 40, "_TEMPLATE_PHASE_FINISH").with_range(55, 60).with_open(30, 50).with_lap()]))
	if ph.mode == Wl.SIM and int(state["tick"]) % 10 == 0:  # grade_source "game": gentle rollers at 2 Hz
		ctx.directives.course_grade(peer, 1.5 * sin(ph.elapsed_s / 5.0))
	if ph.open_ended and ph.elapsed_s >= ph.min_s and in_band and _first("end%d_%d" % [peer, ph.index]):
		ctx.directives.end_phase(peer)  # in band after min_s ends it; the platform ends it at max_s
	if ph.kind == Wl.WORK and ph.elapsed_s >= float(content["nudge_at_s"]) and _first("nudge%d_%d" % [peer, ph.index]):
		ctx.directives.request(peer, EffortDirective.from_dict({"target_pct": ph.planned_pct + float(content["nudge_pct"]),
			"duration_s": float(content["nudge_s"]), "reason": "hill", "source": "_template"}))
	if ph.kind == Wl.WORK and ph.elapsed_s >= float(content["lap_marker_at_s"]) and _first("lap_marker%d" % ph.index):
		lap_marker.emit("_TEMPLATE_LAP_HALFWAY")
	if ph.kind == Wl.COOLDOWN and _first("cool%d" % peer) and _done.keys().filter(func(k: Variant) -> bool: return str(k).begins_with("cool")).size() == ctx.players.size():
		finished.emit("complete")  # once every rider is in the cool-down (earlier it would end open phases)
	if int(state["tick"]) % Wl.SIM_HZ == 0 and tm != null:
		var laps: int = TemplateRules.rider(state, peer).get("laps", 0)
		ctx.hud.teammate_status(peer, {"in_band": in_band, "icon": "", "text": ctx.strings.t("_TEMPLATE_STATUS_LAPS", [laps])})


func _first(key: String) -> bool:
	var first := not _done.has(key)
	_done[key] = true
	return first


## Host/SOLO: a bot's or Autopilot rider's game choices; never effort (BRIEF 3.5).
func autopilot_intents(_peer_id: int) -> Array:
	return [{"k": "boost", "auto": 1}] if int(state.get("tick", 0)) % 600 == 300 else []


## Host/SOLO: rescue is a stagger (the marker waits), never a wipe.
func on_rescue(peer_id: int, active: bool) -> void:
	TemplateRules.rider(state, peer_id)["rescue"] = active
	if active and ctx.player(peer_id) != null and not ctx.player(peer_id).is_bot:
		ctx.hud.toast("_TEMPLATE_STAGGER", [], peer_id)  # only that rider's peer shows it


func on_afk(peer_id: int, afk: bool) -> void:
	TemplateRules.rider(state, peer_id)["afk"] = afk


## Every peer: the local rider's actions and gestures become intents, tagged by source.
func local_intents(actions: Array[StringName], gestures: Array[StringName]) -> Array:
	if gestures.has(Wl.G_SURGE):
		return [{"k": "boost", "via": "surge"}]
	return [{"k": "boost", "via": "action"}] if actions.has(&"confirm") else []


## Host, 10 Hz: the full state as integer arrays (declared in int_fields).
func snapshot() -> Dictionary:
	var r: Array = []
	for rd: Dictionary in state.get("riders", []):
		r.append([rd["slot"], roundi(float(rd["dist_m"]) * 10.0), rd["laps"],
			roundi(float(rd["boost_s"]) * 1000.0), int(rd["rescue"]), int(rd["afk"])])
	return {"v": 1, "tick": state.get("tick", 0), "r": r}


func apply_snapshot(snap: Dictionary) -> void:
	state["tick"] = int(snap.get("tick", 0))
	for row: Variant in snap.get("r", []):
		TemplateRules.rider(state, null, int(row[0])).merge({"dist_m": int(row[1]) / 10.0, "laps": int(row[2]),
			"boost_s": int(row[3]) / 1000.0, "rescue": int(row[4]) != 0, "afk": int(row[5]) != 0}, true)
	ctx.hud.readout("laps", str(TemplateRules.rider(state, ctx.local_peer).get("laps", 0)))


func apply_event(event: Dictionary) -> void:
	var rd := TemplateRules.rider(state, null, int(event.get("slot", -1)))
	if not rd.is_empty() and event.get("type") == "boost":
		rd["boost_s"] = state["boost_s"]
	elif not rd.is_empty() and event.get("type") == "lap":
		rd["laps"] = int(event["laps"])
		if rd["peer"] == ctx.local_peer:
			ctx.hud.toast("_TEMPLATE_LAP_DONE", [rd["laps"]])


func client_predict(dt: float, local: Telemetry) -> void:
	var rd := TemplateRules.rider(state, ctx.local_peer)
	if local != null and not rd.is_empty() and not (rd["rescue"] or rd["afk"]):
		rd["dist_m"] = float(rd["dist_m"]) + TemplateRules.speed(state, local.p_eff_w, float(rd["boost_s"]) > 0.0) * dt


func int_fields() -> Dictionary:
	return {"snapshot": ["v", "tick", "r[][]"], "boost": ["slot"], "lap": ["slot", "laps"]}


func make_view() -> Node:
	var view := TemplateView.new()
	view.game = self
	return view


func hud_spec() -> HudSpec:
	var boost := Button.new()  # the game's own Control sends intents through ctx.intents
	boost.text = ctx.strings.t("_TEMPLATE_BOOST")
	boost.pressed.connect(func() -> void: ctx.intents.send({"k": "boost", "via": "button"}))
	return HudSpec.new().add(HudSpec.TIMELINE, HudSpec.TOP_LEFT).add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT) \
		.add(HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "custom", "id": "laps", "label": "_TEMPLATE_LAPS"}) \
		.add(HudSpec.CADENCE, HudSpec.BOTTOM_LEFT).add(HudSpec.WBAL, HudSpec.BOTTOM_LEFT).add(HudSpec.GEAR, HudSpec.BOTTOM_LEFT) \
		.add(HudSpec.TEAMMATES, HudSpec.BOTTOM).add_control(boost, Rect2i(528, 300, 104, 48)).toasts_at(HudSpec.TOP).banners_at(HudSpec.TOP)


## Host/SOLO, once: the platform's rows (kJ, %FTP, time in band) plus the game's own.
func results() -> GameResults:
	var res := GameResults.from_stats(ctx.stats, ctx.players)
	var band := 0.0
	for row in res.rows:
		var laps: int = TemplateRules.rider(state, row["peer_id"]).get("laps", 0)
		row["stats"]["laps"] = laps
		row["xp"] = roundi(float(row.get("kj", 0.0)) / 10.0) + 5 * laps
		row["unlocks"] = ["gold_marker"] if laps >= 3 else []
		band += float(row.get("time_in_band_pct", 0.0)) / 100.0 / res.rows.size()
		res.score += laps
	res.grade = GameResults.grade_from_fraction(band)
	res.team = {"laps": int(res.score)}
	res.summary_key = "_TEMPLATE_RESULTS"
	return res


## Every peer, once per session: the local rider's XP and new unlocks into `progress` (ctx.progress).
func apply_progress(res: GameResults, progress: ProgressStore) -> Array:
	var row := res.row(ctx.local_peer)
	if row.is_empty() or (res.session_id != "" and progress.get_value("last_session", "") == res.session_id):
		return []
	progress.set_value("last_session", res.session_id)
	progress.add("xp", float(row.get("xp", 0)))
	var held: Array = progress.get_value("unlocks", [])
	var fresh: Array = row.get("unlocks", []).filter(func(u: Variant) -> bool: return not held.has(u))
	progress.set_value("unlocks", held + fresh)
	return fresh

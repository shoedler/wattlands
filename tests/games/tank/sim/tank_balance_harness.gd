class_name TankBalanceHarness
extends RefCounted
## The pure rules-level balance harness (brief 4, G2 "Balance: tune content until T1-T5 hold"):
## drives TankRules + TankDirector (or, with via_module, the whole TankGame) with a recording fake
## sink (TankFakes) and synthetic compliant riders (TankSyntheticRiders: an ERG follower and a SIM
## band rider, like the MockTrainer's `erg` profile) for one crew size, seed and compliance, and
## reports what the tuning targets need:
##
##   segments        per plan segment: start, end, duration and how it ended (end_phase / max_s /
##                   duration), so T1's ranges and overruns read straight off
##   overruns, breakdowns, score, grade, outcome, kills by enemy code
##   dynamo          per fight phase of the dynamo's rider: seconds with the applied ERG target above
##                   80% FTP, and seconds from the fight's end until it is back at <= 65% (T2)
##   shells          per steam shell: the seconds from "ready to build" to the latch (the 5 s
##                   window included) and the seconds at boiler grade 0 until the next build (T3)
##   drive_share     per Advance, the Bulwark's share of time with the lever on Drive (T4)
##   max_enemies, max_shells, max_snapshot_bytes (S8's caps), directive and event counts, a hash
##
## It never touches the trainer stack: only TankFakes.Directives and TankFakes.Hud, which record
## what the game asked. Runs are deterministic for a given config. Everything is read through the
## contract classes, so it works the same on the G0 stubs and on the merged rules.
##
## Config keys (all optional): crew (1), seed (1), compliance (1.0), content ("ashfall_road"),
## rotation (true), enemy_mult (1: every encounter and gun-line count x n, in memory), via_module
## (false), snapshots (true: encode a snapshot every 2nd tick), max_seconds (the session limit).

const SESSION_LIMIT_S := 2460.0 + 180.0 + 30.0
const FIGHT_SEGS: Array[String] = [TankIds.SEG_ADVANCE, TankIds.SEG_GUN_LINE, TankIds.SEG_BOSS]

var cfg: Dictionary = {}
var ctx: GameContext = null
var content: TankContent = null
var state: TankState = null
var plans: Dictionary = {}
var clock: TankFakes.PhaseClock = null
var riders: TankSyntheticRiders = null
var director: TankDirector = null
var game: TankGame = null
var dirs: TankFakes.Directives = null
var hud: TankFakes.Hud = null

var events: Array[Dictionary] = []
## The events with the game time `_t` of their tick (for probes and debugging).
var events_t: Array[Dictionary] = []
var _now: float = 0.0
var event_counts: Dictionary = {}
var max_enemies: int = 0
var max_shells: int = 0
var max_snapshot_bytes: int = 0
var snapshots_taken: int = 0

var _limiter := TankIntentLimiter.new()
var _dyn: Dictionary = {}
var _shells: Array[Dictionary] = []
var _ready_since: float = 0.0
var _was_busy: bool = false
var _g0_ticks: int = 0
var _phase_seen: int = -1
var _phase_t: float = 0.0
var _drive: Dictionary = {}
var _kills: Array[int] = [0, 0, 0, 0, 0, 0, 0]


## One run: returns the result dictionary (see the class doc).
static func run(config: Dictionary = {}) -> Dictionary:
	var h := TankBalanceHarness.new()
	return h.execute(config)


## The mission patch (GameContext.content_overrides) that multiplies every Advance encounter and
## gun-line enemy count of `content_id` by `mult`, in memory: gun lines get extra positions 40 px
## further along for each extra copy. The Behemoth and the segment table are untouched.
static func enemy_mult_overrides(content_id: String, mult: int) -> Dictionary:
	var mission: Dictionary = TankContent.read_files(content_id)["mission"]
	var segs: Array = (mission["segments"] as Array).duplicate(true)
	for s: Dictionary in segs:
		for e: Dictionary in s.get("encounters", []):
			e["count"] = int(e["count"]) * mult
		for e: Dictionary in s.get("enemies", []):
			var base: Array = (e.get("at_px", []) as Array).duplicate()
			var n := int(e["count"])
			var out: Array = base.duplicate()
			for k in range(base.size(), n * mult):
				out.append(float(base[k % base.size()]) + 40.0 * float(k / base.size()))
			e["count"] = n * mult
			if not base.is_empty():
				e["at_px"] = out
	return {TankContent.mission_path(content_id): {"segments": segs}}


func execute(config: Dictionary) -> Dictionary:
	cfg = config
	var crew := int(cfg.get("crew", 1))
	var content_id := str(cfg.get("content", "ashfall_road"))
	var rotation := bool(cfg.get("rotation", true))
	var limit := float(cfg.get("max_seconds", SESSION_LIMIT_S))
	ctx = TankFakes.make_ctx(
		crew, 0, content_id, Wl.HOST if crew > 1 else Wl.SOLO, 1, int(cfg.get("seed", 1))
	)
	ctx.options["rotation"] = rotation
	var mult := int(cfg.get("enemy_mult", 1))
	if mult > 1:
		ctx.content_overrides = enemy_mult_overrides(content_id, mult)
	dirs = ctx.directives as TankFakes.Directives
	hud = ctx.hud as TankFakes.Hud
	if bool(cfg.get("via_module", false)):
		game = TankFakes.make_game(ctx)
		game.cue.connect(_on_cue)
		var with_cd := TankFakes.plans_of(game)
		plans = game.plans
		state = game.state
		content = game.content
		clock = TankFakes.PhaseClock.new(with_cd, dirs)
	else:
		content = TankContent.load_for(ctx)
		rotation = rotation and content.mission_rotates()
		state = TankRules.new_state(content, ctx.players, content_id, rotation, ctx.rng)
		plans = TankPlanBuilder.build_all(content, ctx.players, rotation)
		director = TankDirector.new(ctx, content, plans)
		var with_cd := {}
		for peer: int in plans:
			with_cd[peer] = TankFakes.with_cooldown(plans[peer])
		clock = TankFakes.PhaseClock.new(with_cd, dirs)
	riders = TankSyntheticRiders.new(ctx, clock, float(cfg.get("compliance", 1.0)))
	if not content.ok():
		return {"error": "; ".join(content.errors)}
	var tick := 0
	var end_t := -1.0
	while tick * Wl.SIM_DT < limit:
		var t := tick * Wl.SIM_DT
		clock.advance(t)
		dirs.t = t
		hud.t = t
		_step(tick, t)
		if end_t < 0.0 and clock.all_in_cooldown():
			end_t = t
		if end_t >= 0.0 and t >= end_t + 1.0:
			break
		tick += 1
	var res := _result(tick * Wl.SIM_DT)
	if game != null:
		game.free()
		game = null
	return res


func _step(tick: int, t: float) -> void:
	_now = t
	var raw := {}
	for p in ctx.players:
		raw[p.peer_id] = TankAutopilot.intents(state, p.peer_id)
	var f := riders.frame(tick, raw)
	var evs: Array[Dictionary] = []
	if game != null:
		game.sim_step(Wl.SIM_DT, f)
		evs = _drain
	else:
		var filtered := {}
		for p in ctx.players:
			var ps := f.phase_of(p.peer_id)
			var engine := str(TankInputs.meta_of(plans.get(p.peer_id), ps.index).get("engine", ""))
			filtered[p.peer_id] = _limiter.filter(p.peer_id, tick, raw[p.peer_id], engine)
		var inp := TankInputs.from_frame(f, ctx.players, plans, filtered, {}, {})
		evs = TankRules.step(state, inp, Wl.SIM_DT)
		director.step(state, inp, evs)
		for e in evs:
			_on_event(e)
	_observe(t, evs)
	if bool(cfg.get("snapshots", true)) and tick % 2 == 0:
		var snap := TankSnapshot.encode(state)
		max_snapshot_bytes = maxi(max_snapshot_bytes, TankSnapshotSchema.byte_size(snap))
		snapshots_taken += 1
	max_enemies = maxi(max_enemies, state.enemies.size())
	max_shells = maxi(max_shells, state.shells.size())


## Events the module raised through its cue signal since the last tick (module mode).
var _drain: Array[Dictionary] = []


func _on_cue(_kind: String, data: Dictionary) -> void:
	_drain.append(data)
	_on_event(data)


func _on_event(e: Dictionary) -> void:
	events.append(e)
	var et := e.duplicate()
	et["_t"] = _now
	events_t.append(et)
	var type := str(e.get("type", ""))
	event_counts[type] = int(event_counts.get(type, 0)) + 1
	if type == TankEvents.KILL:
		var code := clampi(int(e.get("e", 0)), 0, _kills.size() - 1)
		_kills[code] += 1


func _observe(t: float, evs: Array[Dictionary]) -> void:
	_drain = []
	var sg := state.seg
	if sg.phase_index != _phase_seen:
		_phase_seen = sg.phase_index
		_phase_t = t
	var dyn := state.station(TankIds.ENGINE_DYNAMO)
	if dyn != null and dyn.peer != 0 and FIGHT_SEGS.has(sg.seg):
		var pct := riders.applied_pct(dyn.peer)
		var key := sg.phase_index
		if not _dyn.has(key):
			_dyn[key] = {
				"index": key,
				"seg": sg.seg,
				"stage": sg.stage,
				"peer": dyn.peer,
				"above80_s": 0.0,
				"fight_end_t": -1.0,
				"back_to_65_s": -1.0,
			}
		var rec: Dictionary = _dyn[key]
		if pct > 80.0:
			rec["above80_s"] = float(rec["above80_s"]) + Wl.SIM_DT
		if sg.objective_done:
			if float(rec["fight_end_t"]) < 0.0:
				rec["fight_end_t"] = t
			if float(rec["back_to_65_s"]) < 0.0 and pct <= 65.0:
				rec["back_to_65_s"] = t - float(rec["fight_end_t"])
	var steam := state.station(TankIds.ENGINE_STEAM) as TankSteamState
	if steam != null:
		var busy := steam.loaded or steam.cycling
		for e in evs:
			if str(e.get("type", "")) == TankEvents.LATCH:
				(
					_shells
					. append(
						{
							"t": t,
							"index": sg.phase_index,
							"seg": sg.seg,
							"shell": int(e.get("sh", 0)),
							# Like check_sims.mjs: pressure holds across a checkpoint, so a shell is
							# timed from the later of the last cycle's end and the segment start.
							"build_s": t - maxf(_ready_since, _phase_t),
							"first": _ready_since <= _phase_t,
							"grade0_s": 0.0,
						}
					)
				)
		if busy:
			if steam.peer != 0 and is_zero_approx(riders.last_grade(steam.peer, "boiler")):
				_g0_ticks += 1
		elif _was_busy:
			if not _shells.is_empty():
				_shells[_shells.size() - 1]["grade0_s"] = _g0_ticks * Wl.SIM_DT
			_g0_ticks = 0
			_ready_since = t
		_was_busy = busy
	var gb := state.station(TankIds.ENGINE_BULWARK) as TankGearboxState
	if gb != null and sg.seg == TankIds.SEG_ADVANCE:
		var key := sg.phase_index
		if not _drive.has(key):
			_drive[key] = {"index": key, "stage": sg.stage, "ticks": 0, "drive_ticks": 0}
		var d: Dictionary = _drive[key]
		d["ticks"] = int(d["ticks"]) + 1
		if gb.lever == TankIds.LEVER_DRIVE:
			d["drive_ticks"] = int(d["drive_ticks"]) + 1


func _result(end_t: float) -> Dictionary:
	var sum := TankScore.summary(state)
	var peer := ctx.players[0].peer_id
	var starts: Array[float] = []
	var ended: Array[String] = []
	for c: Dictionary in clock.changes:
		if int(c["peer"]) == peer:
			starts.append(float(c["t"]))
			ended.append(str(c["ended_by"]))
	var segments: Array = []
	var plan: EffortPlan = plans[peer]
	for i in plan.size():
		var ph := plan.phase(i)
		var s0 := starts[i] if i < starts.size() else end_t
		var s1 := starts[i + 1] if i + 1 < starts.size() else end_t
		(
			segments
			. append(
				{
					"index": i,
					"seg": str(ph.meta.get("seg", "")),
					"stage": int(ph.meta.get("stage", 0)),
					"kind": ph.kind,
					"start": s0,
					"end": s1,
					"dur_s": s1 - s0,
					"ended_by": ended[i + 1] if i + 1 < ended.size() else "",
					"overran": i + 1 < ended.size() and ended[i + 1] == Wl.ENDED_MAX_S,
				}
			)
		)
	var dyn_list: Array = []
	for k: int in _dyn:
		var rec: Dictionary = _dyn[k]
		if float(rec["fight_end_t"]) >= 0.0 and float(rec["back_to_65_s"]) < 0.0:
			# The phase ended before the target fell to 65%: the next phase (a checkpoint at 50%)
			# took it there at the boundary.
			var seg_end: float = segments[int(rec["index"])]["end"]
			rec["back_to_65_s"] = seg_end - float(rec["fight_end_t"])
		dyn_list.append(rec)
	var drive_list: Array = []
	for k: int in _drive:
		var d: Dictionary = _drive[k]
		drive_list.append(
			{
				"index": d["index"],
				"stage": d["stage"],
				"share": float(d["drive_ticks"]) / maxi(int(d["ticks"]), 1)
			}
		)
	var reasons := {}
	for r: Array in dirs.requests:
		var reason := str((r[1] as Dictionary).get("reason", ""))
		reasons[reason] = int(reasons.get(reason, 0)) + 1
	var res := {
		"crew": int(cfg.get("crew", 1)),
		"seed": int(cfg.get("seed", 1)),
		"compliance": float(cfg.get("compliance", 1.0)),
		"content": str(cfg.get("content", "ashfall_road")),
		"enemy_mult": int(cfg.get("enemy_mult", 1)),
		"end_t": end_t,
		"segments": segments,
		"overruns": state.score.overruns,
		"breakdowns": state.score.breakdowns,
		"score": float(sum["score"]),
		"grade": str(sum["grade"]),
		"band": float(sum["band"]),
		"outcome": state.outcome,
		"kills": _kills.duplicate(),
		"dynamo": dyn_list,
		"shells": _shells.duplicate(true),
		"drive_share": drive_list,
		"max_enemies": max_enemies,
		"max_shells": max_shells,
		"max_snapshot_bytes": max_snapshot_bytes,
		"snapshots": snapshots_taken,
		"event_counts": event_counts.duplicate(),
		"request_reasons": reasons,
		"requests": dirs.requests.size(),
		"course_grades": dirs.course_grades.size(),
		"end_phase_batches": clock.batches.size(),
		"cadence_bands": dirs.cadence_bands.size(),
		"power_bands": hud.power_band_at.size(),
	}
	res["hash"] = (
		JSON
		. stringify([res["segments"], res["event_counts"], res["score"], events.size()])
		. sha256_text()
	)
	return res


## A readable block for one result: segment times, then the T1-T5 inputs.
static func format(r: Dictionary) -> String:
	if r.has("error"):
		return "error: %s" % r["error"]
	var lines: PackedStringArray = []
	(
		lines
		. append(
			(
				"crew %d seed %d compliance %.2f %s: %.0f s, score %.0f grade %s, breakdowns %d, overruns %d, outcome %s"
				% [
					r["crew"],
					r["seed"],
					r["compliance"],
					r["content"],
					r["end_t"],
					r["score"],
					r["grade"],
					r["breakdowns"],
					r["overruns"],
					r["outcome"],
				]
			)
		)
	)
	var parts: PackedStringArray = []
	for s: Dictionary in r["segments"]:
		parts.append(
			(
				"%s%d %.0f%s"
				% [str(s["seg"]).substr(0, 3), s["stage"], s["dur_s"], "!" if s["overran"] else ""]
			)
		)
	lines.append("  segments: " + ", ".join(parts))
	for d: Dictionary in r["dynamo"]:
		lines.append(
			(
				"  dynamo %s stage %d: above 80%% %.0f s, back to 65%% after %.0f s"
				% [d["seg"], d["stage"], d["above80_s"], d["back_to_65_s"]]
			)
		)
	var builds: PackedStringArray = []
	for s: Dictionary in r["shells"]:
		builds.append("%.0f/%.0f" % [s["build_s"], s["grade0_s"]])
	if not builds.is_empty():
		lines.append("  shells (build s / grade-0 s): " + ", ".join(builds))
	var shares: PackedStringArray = []
	for d: Dictionary in r["drive_share"]:
		shares.append("%.0f%%" % (100.0 * float(d["share"])))
	if not shares.is_empty():
		lines.append("  Bulwark Drive share per Advance: " + ", ".join(shares))
	lines.append(
		(
			"  max enemies %d, shells %d, snapshot %d B, requests %d, kills %s"
			% [
				r["max_enemies"],
				r["max_shells"],
				r["max_snapshot_bytes"],
				r["requests"],
				str(r["kills"])
			]
		)
	)
	return "\n".join(lines)

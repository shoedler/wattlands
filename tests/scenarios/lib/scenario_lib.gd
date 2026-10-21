extends RefCounted
## Helpers for the BRIEF 7.4 and 7.5 scenario tests in tests/scenarios/ (owned by qa).
## Not a test file (GUT collects only test_*.gd). Load with
## `const S := preload("res://tests/scenarios/lib/scenario_lib.gd")`.
##
## The scenarios drive GameSimRunner (sdk-runtime) headless through its frozen API: parse_args,
## setup, step, run_to_end, sim_seconds, build_report, write_report and `host` (GameHost), whose
## local_riders give each host-side rider's LocalRider (device, governor, recorder). Per-tick
## checks read SafetyGovernor.status() and the MockTrainer's samples on platform time.
## The run_game_sim report's exact keys are documented in docs/GAME_SDK.md (SIM4); the report
## accessors below accept the shapes that document allows (maps keyed by peer id, or lists of
## {peer, ...}) so a key rename needs one change here.

const WORKOUT := "workout"
## BRIEF 3.7's built-in sessions (every one must be in workout's game.json `contents`).
const WORKOUT_SESSIONS: Array[String] = ["easy_30", "sweet_spot", "threshold", "vo2", "rolling_road", "e2e"]
const FTP := 200.0
const EPS := 1e-6
const WARMUP_S := 300.0
const WARMUP_ERG_MAX_PCT := 65.0
const WARMUP_GRADE_MIN := -2.0
const WARMUP_GRADE_MAX := 3.0
const RESCUE_MIN_PCT := 60.0
## not_pedaling (BRIEF 3.5): power < 15 W and cadence < 20 rpm.
const NOT_PEDALING_W := 15.0
const NOT_PEDALING_RPM := 20.0
const COAST_FLOOR_S := 3.0
const COAST_PAUSE_S := 10.0


## run_game_sim flags for one Workout session: one human (the host, SOLO) and one bot, a
## compliant verified-FTP rider. A flag in `extra` replaces the default with the same name (every
## default --rider when `extra` holds one).
static func flags(content: String, report_path: String, extra: Array = []) -> PackedStringArray:
	var defaults: Array[String] = [
		"--game=%s" % WORKOUT, "--content=%s" % content, "--players=1", "--bots=1",
		"--rider=erg", "--seed=7", "--sim-speed=1000", "--report=%s" % report_path,
	]
	var overridden: Dictionary = {}
	for e: Variant in extra:
		overridden[flag_key(str(e))] = true
	var f := PackedStringArray()
	for d in defaults:
		if not overridden.has(flag_key(d)):
			f.append(d)
	for e: Variant in extra:
		f.append(str(e))
	return f


static func flag_key(flag: String) -> String:
	var eq := flag.find("=")
	return flag if eq < 0 else flag.substr(0, eq)


## {runner: GameSimRunner, error: String}. The caller adds the runner to the tree (autofree).
static func new_runner(f: PackedStringArray) -> Dictionary:
	var args: Dictionary = GameSimRunner.parse_args(f)
	if str(args.get("error", "")) != "":
		return {"runner": null, "error": "parse_args: %s" % args["error"]}
	args["headless"] = true
	var runner := GameSimRunner.new()
	return {"runner": runner, "args": args, "error": ""}


## The host's own human rider (ctx.local_peer; SOLO and HOST).
static func human_peer(runner: GameSimRunner) -> int:
	if runner.host == null or runner.host.ctx == null:
		return 0
	return runner.host.ctx.local_peer


static func rider_of(runner: GameSimRunner, peer: int) -> LocalRider:
	if runner.host == null:
		return null
	return runner.host.local_rider(peer)


static func mock_of(rider: LocalRider) -> MockTrainer:
	return rider.device as MockTrainer if rider != null else null


## Platform seconds on the rider's own clock (its MockTrainer's), else the runner's.
static func platform_t(runner: GameSimRunner, rider: LocalRider) -> float:
	var m := mock_of(rider)
	return m.platform_time_s() if m != null else runner.sim_seconds()


## The ERG floor max(30 % FTP, 50 W), rounded up (BRIEF 4.6.1).
static func floor_w(ftp: float) -> int:
	return ceili(maxf(0.30 * ftp, 50.0))


static func is_not_pedaling(s: TrainerSample) -> bool:
	var cad := s.cadence_rpm if s.has_cadence() else 0.0
	return s.power_w < NOT_PEDALING_W and cad < NOT_PEDALING_RPM


static func clamped(status: Dictionary, rule: String) -> bool:
	var c: Variant = status.get("clamped_by", [])
	return c is Array and (c as Array).has(rule)


## Problems with one tick's status against the 4.6.8 warm-up limits (empty when fine).
static func warmup_problems(status: Dictionary, t: float) -> Array[String]:
	var out: Array[String] = []
	if not bool(status.get("warmup_active", false)):
		return out
	var mode := str(status.get("mode", ""))
	if mode == Wl.ERG and float(status.get("applied_pct", 0.0)) > WARMUP_ERG_MAX_PCT + EPS:
		out.append("t=%.2f: ERG %.2f%% FTP during warm-up" % [t, float(status["applied_pct"])])
	if mode == Wl.SIM:
		var g := float(status.get("applied_grade_pct", 0.0))
		if g < WARMUP_GRADE_MIN - EPS or g > WARMUP_GRADE_MAX + EPS:
			out.append("t=%.2f: SIM grade %.2f%% during warm-up" % [t, g])
	if bool(status.get("haptic_active", false)):
		out.append("t=%.2f: a haptic during warm-up" % t)
	return out


# ---------------------------------------------------------------------------------------------
# Report accessors (the run_game_sim report, BRIEF 3.6 and docs/GAME_SDK.md)


## A per-peer entry of `report[key]` for the first key present: a map keyed by peer id (string
## or int) or a list of {peer|peer_id, <inner>}.
static func per_peer(report: Dictionary, keys: Array, peer: int, inner: Array = []) -> Variant:
	for k: Variant in keys:
		if not report.has(k):
			continue
		var v: Variant = report[k]
		if v is Dictionary:
			var d: Dictionary = v
			for cand: Variant in [str(peer), peer, float(peer)]:
				if d.has(cand):
					return d[cand]
		elif v is Array:
			for e: Variant in v:
				if e is Dictionary:
					var ed: Dictionary = e
					var p: Variant = ed.get("peer", ed.get("peer_id", null))
					if p != null and int(p) == peer:
						for ik: Variant in inner:
							if ed.has(ik):
								return ed[ik]
						return ed
	return null


## The rider's validated plan phases as dictionaries (cool-down appended).
static func plan_phases(report: Dictionary, peer: int) -> Array:
	var p: Variant = per_peer(report, ["plans"], peer, ["plan", "phases"])
	if p is Dictionary and (p as Dictionary).has("phases"):
		p = (p as Dictionary)["phases"]
	return p if p is Array else []


## The rider's phases as run: [{index, kind, start, end, ended_by}].
static func run_phases(report: Dictionary, peer: int) -> Array:
	var p: Variant = per_peer(report, ["phases"], peer, ["phases"])
	return p if p is Array else []


## The rider's 1 Hz trace.
static func trace(report: Dictionary, peer: int) -> Array:
	var p: Variant = per_peer(report, ["traces", "trace"], peer, ["trace", "entries"])
	return p if p is Array else []


static func results(report: Dictionary) -> Dictionary:
	var r: Variant = report.get("results", {})
	return r if r is Dictionary else {}


static func result_row(report: Dictionary, peer: int) -> Dictionary:
	for row: Variant in results(report).get("rows", []):
		if row is Dictionary and int((row as Dictionary).get("peer_id", 0)) == peer:
			return row
	return {}


## Every FIT path in the report (a list, or a map slot/peer -> path).
static func fit_paths(report: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var v: Variant = report.get("fit_paths", [])
	if v is Array:
		for p: Variant in v:
			out.append(str(p))
	elif v is Dictionary:
		for k: Variant in (v as Dictionary).keys():
			out.append(str((v as Dictionary)[k]))
	return out


static func lap_markers(report: Dictionary, peer: int) -> int:
	var n := 0
	for e: Variant in report.get("events", []):
		if e is Dictionary:
			var ed: Dictionary = e
			var type := str(ed.get("type", ""))
			if (type == "lap_marker" or type == "lap") and (not ed.has("peer") or int(ed["peer"]) == peer):
				n += 1
	return n


## FIT1: lap-true phases that started (the cool-down aside) + lap markers + 1 for the cool-down
## when it started.
static func expected_laps(report: Dictionary, peer: int) -> int:
	var plan := plan_phases(report, peer)
	var n := 0
	var cooldown_started := false
	for rp: Variant in run_phases(report, peer):
		if not rp is Dictionary:
			continue
		var i := int((rp as Dictionary).get("index", -1))
		if i < 0 or i >= plan.size():
			continue
		var ph: Dictionary = plan[i]
		if str(ph.get("kind", "")) == Wl.COOLDOWN:
			cooldown_started = true
		elif bool(ph.get("lap", false)):
			n += 1
	return n + lap_markers(report, peer) + (1 if cooldown_started else 0)


## BRIEF 7.5 problems with one FIT file against the recorder's summary (empty when fine):
## zero decoder errors (CRCs, cycling / virtual_activity), one record per second within 1 %,
## `expected_laps` laps, and session totals equal to the recorder's.
static func fit_problems(path: String, summary: Dictionary, expected_laps_n: int) -> Array[String]:
	var out: Array[String] = []
	var d := QaFitDecoder.decode_file(path, {"expect_laps": expected_laps_n})
	for e: Variant in d["errors"]:
		out.append("%s: %s" % [path.get_file(), str(e)])
	var ses: Dictionary = d["session"]
	var duration := float(summary.get("duration_s", ses.get("elapsed_s", 0.0)))
	var records := int(d["records"])
	if duration > 0.0 and absf(records - duration) > maxf(1.0, 0.01 * duration):
		out.append("%s: %d records for a %.0f s ride (one per second within 1%%)" % [path.get_file(), records, duration])
	if summary.has("records") and int(summary["records"]) != records:
		out.append("%s: %d records, the recorder kept %d" % [path.get_file(), records, int(summary["records"])])
	if summary.has("kj") and absf(float(ses.get("work_kj", 0.0)) - float(summary["kj"])) > 0.01 + 0.001 * float(summary["kj"]):
		out.append("%s: session work %.3f kJ, recorder %.3f kJ" % [path.get_file(), float(ses.get("work_kj", 0.0)), float(summary["kj"])])
	for pair: Array in [["avg_power_w", "avg_power_w"], ["max_power_w", "max_power_w"], ["avg_cadence_rpm", "avg_cadence_rpm"], ["max_cadence_rpm", "max_cadence_rpm"]]:
		if summary.has(pair[1]) and absf(float(ses.get(pair[0], 0.0)) - float(summary[pair[1]])) > 1.0:
			out.append("%s: session %s %.1f, recorder %.1f" % [path.get_file(), pair[0], float(ses.get(pair[0], 0.0)), float(summary[pair[1]])])
	if summary.has("distance_m") and absf(float(ses.get("distance_m", 0.0)) - float(summary["distance_m"])) > maxf(1.0, 0.001 * float(summary["distance_m"])):
		out.append("%s: session distance %.1f m, recorder %.1f m" % [path.get_file(), float(ses.get("distance_m", 0.0)), float(summary["distance_m"])])
	if duration > 0.0 and absf(float(ses.get("elapsed_s", 0.0)) - duration) > 1.0:
		out.append("%s: session elapsed %.1f s, recorder %.1f s" % [path.get_file(), float(ses.get("elapsed_s", 0.0)), duration])
	return out


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


## The GameRegistry autoload (null when missing).
static func registry(from: Node) -> WlGameRegistry:
	if from == null or not from.is_inside_tree():
		return null
	return from.get_tree().root.get_node_or_null(^"GameRegistry") as WlGameRegistry


## Makes sure Workout's strings are registered with the TranslationServer, rescanning the
## GameRegistry autoload when `probe_key` is untranslated. Returns true when it translates.
## Why: WlGameRegistry adds each game's cached Translation resources and removes them when an
## instance is freed, and the TranslationServer keeps one entry per resource, so a private
## registry freed by an earlier test also unregisters the autoload's game strings for the rest of
## the run (reported to sdk-runtime).
static func ensure_game_strings(from: Node, probe_key: String) -> bool:
	if String(TranslationServer.translate(probe_key)) != probe_key:
		return true
	var reg := registry(from)
	if reg != null:
		reg.scan()
	return String(TranslationServer.translate(probe_key)) != probe_key


## Workout's .zwo sessions (BRIEF 3.7 Workout Director): every content id in its game.json whose
## content/workout/sessions/<id>.json names a .zwo, as [{content, zwo (res path)}]. `root` is the
## project root (tests pass a fixture folder).
static func zwo_sessions(root: String = "res://") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var manifest := read_json(root.path_join("src/games/%s/game.json" % WORKOUT))
	for c: Variant in manifest.get("contents", []):
		var session := read_json(root.path_join("content/%s/sessions/%s.json" % [WORKOUT, str(c)]))
		var zwo: Variant = session.get("zwo", null)
		if zwo is String and str(zwo) != "":
			out.append({"content": str(c), "zwo": root.path_join("content/%s" % WORKOUT).path_join(str(zwo))})
	return out


## Problems with one tick's governor status against BRIEF 4.6.1's caps (empty when fine): ERG at
## most 150 % FTP, and at most 105 % FTP in a phase longer than 300 s (`phase_length_s`: its
## duration, or max_s when open-ended).
static func cap_problems(status: Dictionary, phase_length_s: float, t: float) -> Array[String]:
	var out: Array[String] = []
	if str(status.get("mode", "")) != Wl.ERG:
		return out
	var pct := float(status.get("applied_pct", 0.0))
	if pct > 150.0 + EPS:
		out.append("t=%.2f: ERG %.2f%% FTP above the 150%% ceiling" % [t, pct])
	if phase_length_s > 300.0 and pct > 105.0 + EPS:
		out.append("t=%.2f: ERG %.2f%% FTP above 105%% in a %.0f s phase" % [t, pct, phase_length_s])
	return out


## A plan phase's length for the 4.6.1 long-phase cap: duration_s, or max_s when open-ended.
static func phase_length_s(phase: Dictionary) -> float:
	if bool(phase.get("open_ended", false)):
		return float(phase.get("max_s", phase.get("duration_s", 0.0)))
	return float(phase.get("duration_s", 0.0))


static func remove_tree(dir: String) -> void:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)

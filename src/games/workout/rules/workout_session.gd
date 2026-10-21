class_name WorkoutSession
extends RefCounted
## One Workout session (BRIEF 3.7), loaded from content/workout/sessions/<content id>.json
## and validated at load. A bad file is rejected with one push_error naming every problem.
##
## A session file is either explicit phases or a .zwo reference:
## [codeblock]
## {"id": "vo2", "label": "WORKOUT_CONTENT_VO2", "summary": "WORKOUT_SUMMARY_VO2",
##  "phases": [{"kind": "WARMUP", "mode": "ERG", "target_pct": 50, "ramp_to_pct": 65,
##              "duration_s": 300, "lap": true, "label": "WORKOUT_LBL_WARMUP"}, ...]}
## {"id": "zwo_sample", "label": ..., "summary": ..., "zwo": "zwo/sample.zwo"}
## [/codeblock]
## Optional keys: "course" (WorkoutCourse spec, needed by SIM phases with grade_source
## "course"), "band_pct" ([lo, hi] % FTP for SIM WORK phases, default [76, 105]) and
## "warmup_only" (true for e2e: the whole session stays inside the warm-up limits instead
## of opening with the 5-minute ramp). Content id "zwo:<path>" imports any .zwo file.
## Every phase has lap = true and a label; the platform appends the cool-down.

const SESSIONS_DIR := "sessions"
const CONTENT_DIR := "res://content/workout"
const ZWO_PREFIX := "zwo:"
const TOP_KEYS: Array[String] = ["id", "label", "summary", "phases", "zwo", "course", "band_pct", "warmup_only"]
const PHASE_KEYS: Array[String] = ["kind", "mode", "target_pct", "ramp_to_pct", "duration_s", "lap", "label", "grade_source"]
const GAME_KINDS: Array[String] = [Wl.WARMUP, Wl.WORK, Wl.RECOVERY, Wl.FREE]
const WARMUP_S := 300.0
const WARMUP_FROM_PCT := 50.0
const WARMUP_TO_PCT := 65.0
const WARMUP_MAX_PCT := 65.0
const MAX_PCT := 150.0
const DEFAULT_BAND_PCT := [76.0, 105.0]
## The platform's appended cool-down (PlanValidator.COOLDOWN_S).
const COOLDOWN_S := 180.0

## Optional zwo parser for tests: Callable(path: String) -> Dictionary shaped like
## WorkoutImport.parse_zwo_file(). Unset: WorkoutImport is used.
static var zwo_parser: Callable = Callable()

var id: String = ""
var label: String = ""
var summary: String = ""
## The game's phases (no cool-down), lap = true, each with a label.
var phases: Array[PlanPhase] = []
var course: WorkoutCourse = null
var band_pct: Array = DEFAULT_BAND_PCT.duplicate()
var warmup_only: bool = false
## "json" or "zwo".
var source: String = "json"
## .zwo imports: the file, its workout name, and the importer's clamps and warnings.
var zwo_path: String = ""
var zwo_name: String = ""
var clamps: Array[String] = []
var warnings: Array[String] = []


## Loads `content_id` for a game context: sessions/<id>.json through ctx.load_content_json
## (so run_game_sim --override works), or a .zwo for "zwo:<path>". Returns null and
## push_error on any problem. With quiet = true (clients) a missing .zwo only warns.
static func load_for(ctx: GameContext, quiet: bool = false) -> WorkoutSession:
	var content_id := ctx.content_id
	var dir := ctx.content_dir if ctx.content_dir != "" else CONTENT_DIR
	if content_id.begins_with(ZWO_PREFIX):
		return from_zwo(content_id, content_id.substr(ZWO_PREFIX.length()), quiet)
	var data: Variant = ctx.load_content_json(SESSIONS_DIR.path_join(content_id + ".json"))
	if data == null:
		return null
	return parse(data, content_id, dir, quiet)


## Loads `content_id` straight from res://content/workout (lobby previews, tests).
static func load_id(content_id: String, quiet: bool = false) -> WorkoutSession:
	if content_id.begins_with(ZWO_PREFIX):
		return from_zwo(content_id, content_id.substr(ZWO_PREFIX.length()), quiet)
	var path := CONTENT_DIR.path_join(SESSIONS_DIR).path_join(content_id + ".json")
	if not FileAccess.file_exists(path):
		if not quiet:
			push_error("WorkoutSession: no session %s (%s)" % [content_id, path])
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		push_error("WorkoutSession: invalid JSON in %s" % path)
		return null
	return parse(data, content_id, CONTENT_DIR, quiet)


## Validates a parsed session file. Returns null and push_error (one message listing
## every problem) when invalid.
static func parse(data: Variant, content_id: String, content_dir: String = CONTENT_DIR, quiet: bool = false) -> WorkoutSession:
	var errs := validate(data, content_id)
	if not errs.is_empty():
		push_error("WorkoutSession: %s rejected: %s" % [content_id, "; ".join(errs)])
		return null
	var d: Dictionary = data
	var s := WorkoutSession.new()
	s.id = content_id
	s.label = str(d["label"])
	s.summary = str(d["summary"])
	s.warmup_only = bool(d.get("warmup_only", false))
	if d.has("band_pct"):
		s.band_pct = [float(d["band_pct"][0]), float(d["band_pct"][1])]
	if d.has("course"):
		s.course = WorkoutCourse.from_spec(d["course"])
	if d.has("zwo"):
		var zs := from_zwo(content_id, content_dir.path_join(str(d["zwo"])), quiet)
		if zs == null:
			return null
		zs.label = s.label
		zs.summary = s.summary
		return zs
	for pd: Dictionary in d["phases"]:
		s.phases.append(_phase_from(pd, s.course))
	return s


## Every problem with a parsed session file ([] when valid).
static func validate(data: Variant, content_id: String) -> Array[String]:
	var errs: Array[String] = []
	if not (data is Dictionary):
		return ["the file must hold a JSON object"]
	var d: Dictionary = data
	for key: Variant in d.keys():
		if not TOP_KEYS.has(str(key)):
			errs.append("%s: unknown key" % key)
	if str(d.get("id", "")) != content_id:
		errs.append("id: must be \"%s\" (the content id), got \"%s\"" % [content_id, d.get("id", "")])
	for key: String in ["label", "summary"]:
		if not (d.get(key) is String) or not str(d[key]).begins_with("WORKOUT_"):
			errs.append("%s: must be a WORKOUT_ strings key" % key)
	if d.has("warmup_only") and not (d["warmup_only"] is bool):
		errs.append("warmup_only: must be true or false")
	if d.has("band_pct"):
		var b: Variant = d["band_pct"]
		if not (b is Array) or (b as Array).size() != 2 or not _is_number(b[0]) or not _is_number(b[1]) \
				or float(b[0]) <= 0.0 or float(b[0]) >= float(b[1]) or float(b[1]) > MAX_PCT:
			errs.append("band_pct: must be [lo, hi] with 0 < lo < hi <= 150")
	var has_course := d.has("course")
	if has_course:
		errs.append_array(WorkoutCourse.spec_errors(d["course"]))
	var has_phases := d.has("phases")
	var has_zwo := d.has("zwo")
	if has_phases == has_zwo:
		errs.append("exactly one of phases and zwo is required")
		return errs
	if has_zwo:
		if not (d["zwo"] is String) or not str(d["zwo"]).ends_with(".zwo"):
			errs.append("zwo: must be a .zwo path under content/workout")
		if has_course:
			errs.append("course: not used by a .zwo session")
		return errs
	if not (d["phases"] is Array) or (d["phases"] as Array).is_empty():
		errs.append("phases: must be a non-empty array")
		return errs
	var uses_course := false
	var arr: Array = d["phases"]
	for i in arr.size():
		if not (arr[i] is Dictionary):
			errs.append("phases[%d]: must be an object" % i)
			continue
		var pe := _phase_errors(arr[i], i)
		errs.append_array(pe)
		if pe.is_empty() and str(arr[i].get("grade_source", "")) == Wl.GRADE_COURSE:
			uses_course = true
	if not errs.is_empty():
		return errs
	if uses_course and not has_course:
		errs.append("course: required by phases with grade_source \"course\"")
	if has_course and not uses_course:
		errs.append("course: no phase uses it")
	var warmup_only := bool(d.get("warmup_only", false))
	if warmup_only:
		var total := 0.0
		for pd: Dictionary in arr:
			total += float(pd["duration_s"])
			for key: String in ["target_pct", "ramp_to_pct"]:
				if pd.has(key) and float(pd[key]) > WARMUP_MAX_PCT:
					errs.append("warmup_only: %s %s is above %s%% FTP" % [pd["label"], key, WARMUP_MAX_PCT])
		if total > WARMUP_S:
			errs.append("warmup_only: the session lasts %s s, more than the %s s warm-up" % [total, WARMUP_S])
	else:
		var w: Dictionary = arr[0]
		if str(w["kind"]) != Wl.WARMUP or str(w["mode"]) != Wl.ERG or float(w["duration_s"]) != WARMUP_S \
				or float(w.get("target_pct", -1.0)) != WARMUP_FROM_PCT or float(w.get("ramp_to_pct", -1.0)) != WARMUP_TO_PCT:
			errs.append("phases[0]: must be the 5-minute WARMUP ERG ramp from 50 to 65 % FTP")
	return errs


static func _phase_errors(pd: Dictionary, i: int) -> Array[String]:
	var errs: Array[String] = []
	var at := "phases[%d]" % i
	for key: Variant in pd.keys():
		if not PHASE_KEYS.has(str(key)):
			errs.append("%s.%s: unknown key" % [at, key])
	var kind := str(pd.get("kind", ""))
	var mode := str(pd.get("mode", ""))
	if not GAME_KINDS.has(kind):
		errs.append("%s.kind: must be one of %s (the platform appends the cool-down)" % [at, ", ".join(GAME_KINDS)])
	if mode != Wl.ERG and mode != Wl.SIM:
		errs.append("%s.mode: must be ERG or SIM" % at)
	if not _is_number(pd.get("duration_s")) or float(pd["duration_s"]) <= 0.0:
		errs.append("%s.duration_s: must be a number > 0" % at)
	if not (pd.get("lap") is bool) or not bool(pd["lap"]):
		errs.append("%s.lap: must be true (every Workout phase is a FIT lap)" % at)
	if not (pd.get("label") is String) or str(pd["label"]).strip_edges() == "":
		errs.append("%s.label: must be a non-empty string" % at)
	if mode == Wl.ERG:
		if not _is_number(pd.get("target_pct")) or float(pd["target_pct"]) <= 0.0 or float(pd["target_pct"]) > MAX_PCT:
			errs.append("%s.target_pct: must be a number in (0, 150]" % at)
		if pd.has("ramp_to_pct") and (not _is_number(pd["ramp_to_pct"]) or float(pd["ramp_to_pct"]) <= 0.0 or float(pd["ramp_to_pct"]) > MAX_PCT):
			errs.append("%s.ramp_to_pct: must be a number in (0, 150]" % at)
		if pd.has("grade_source"):
			errs.append("%s.grade_source: only for SIM phases" % at)
		if kind == Wl.FREE:
			errs.append("%s: FREE phases ride SIM with virtual gears" % at)
	elif mode == Wl.SIM:
		var src := str(pd.get("grade_source", ""))
		if src != Wl.GRADE_FLAT and src != Wl.GRADE_COURSE:
			errs.append("%s.grade_source: must be flat or course" % at)
		if pd.has("target_pct") or pd.has("ramp_to_pct"):
			errs.append("%s: SIM phases take no target_pct or ramp_to_pct" % at)
		if src == Wl.GRADE_COURSE and kind != Wl.WORK:
			errs.append("%s: a course phase is a WORK phase (Rolling road)" % at)
	return errs


static func _phase_from(pd: Dictionary, p_course: WorkoutCourse) -> PlanPhase:
	var p: PlanPhase
	if str(pd["mode"]) == Wl.ERG:
		p = PlanPhase.erg(str(pd["kind"]), float(pd["target_pct"]), float(pd["duration_s"]), str(pd["label"]))
		if pd.has("ramp_to_pct"):
			p.with_ramp(float(pd["ramp_to_pct"]))
	else:
		p = PlanPhase.sim(str(pd["kind"]), Wl.GRADE_FLAT, float(pd["duration_s"]), str(pd["label"]))
		if str(pd["grade_source"]) == Wl.GRADE_COURSE and p_course != null:
			p.with_course(p_course.to_course_profile())
	p.with_lap(true)
	return p


## Imports a .zwo file through WorkoutImport (BRIEF 3.7): phases come back clamped to 4.6
## and the warm-up limits with a warm-up prefix; their clamps and warnings are kept for
## session_preview(). Workout then sets lap = true and a label on every phase and turns
## an imported cool-down block into a RECOVERY phase (the platform appends its own).
static func from_zwo(content_id: String, path: String, quiet: bool = false) -> WorkoutSession:
	if path == "" or not FileAccess.file_exists(path):
		if quiet:
			push_warning("WorkoutSession: .zwo file %s not found here" % path)
		else:
			push_error("WorkoutSession: .zwo file %s not found" % path)
		return null
	var result: Dictionary = parse_zwo_path(path)
	if not bool(result.get("ok", false)):
		push_error("WorkoutSession: .zwo import of %s failed: %s" % [path, result.get("error", "unknown error")])
		return null
	var s := WorkoutSession.new()
	s.id = content_id
	s.label = "WORKOUT_CONTENT_ZWO"
	s.summary = "WORKOUT_SUMMARY_ZWO"
	s.source = "zwo"
	s.zwo_path = path
	s.zwo_name = str(result.get("name", ""))
	for c: Variant in result.get("clamps", []):
		s.clamps.append(str(c))
	for w: Variant in result.get("warnings", []):
		s.warnings.append(str(w))
	var strings := GameStrings.new()
	var n := 0
	for item: Variant in result.get("phases", []):
		var p: PlanPhase = null
		if item is PlanPhase:
			p = (item as PlanPhase).duplicate_phase()
		elif item is Dictionary:
			p = PlanPhase.from_dict(item)
		if p == null:
			continue
		n += 1
		if p.kind == Wl.COOLDOWN:
			p.kind = Wl.RECOVERY
		if p.mode == Wl.SIM and p.kind != Wl.FREE and p.grade_source == Wl.GRADE_FLAT and p.course_profile.is_empty():
			p.kind = Wl.FREE
		p.lap = true
		if p.label.strip_edges() == "":
			p.label = block_label(strings, n)
		p.open_ended = false
		s.phases.append(p)
	var errs: Array[String] = []
	if s.phases.is_empty():
		errs.append("the workout has no supported blocks")
	for i in s.phases.size():
		var pe := _phase_errors(_phase_dict(s.phases[i]), i)
		errs.append_array(pe)
	if not errs.is_empty():
		push_error("WorkoutSession: .zwo %s rejected: %s" % [path, "; ".join(errs)])
		return null
	return s


## The label of imported block `n` ("Block 3"), which is also its FIT lap name. Plain text
## even where Workout's strings aren't registered (a headless run), never the bare key.
static func block_label(strings: GameStrings, n: int) -> String:
	if strings != null and strings.has("WORKOUT_LBL_BLOCK"):
		return strings.t("WORKOUT_LBL_BLOCK", {"n": n})
	return "Block %d" % n


## Runs the .zwo parser (WorkoutImport, or zwo_parser in tests).
static func parse_zwo_path(path: String) -> Dictionary:
	if zwo_parser.is_valid():
		var r: Variant = zwo_parser.call(path)
		return r if r is Dictionary else {"ok": false, "error": "parser returned no result"}
	return WorkoutImport.parse_zwo_file(path)


## The phase as a session-file entry (for validating imported phases).
static func _phase_dict(p: PlanPhase) -> Dictionary:
	var d := {"kind": p.kind, "mode": p.mode, "duration_s": p.duration_s, "lap": p.lap, "label": p.label}
	if p.mode == Wl.ERG:
		d["target_pct"] = p.target_pct
		if p.has_ramp():
			d["ramp_to_pct"] = p.ramp_to_pct
	else:
		d["grade_source"] = p.grade_source if p.grade_source != Wl.GRADE_GAME else Wl.GRADE_FLAT
	return d


## A fresh plan (new PlanPhase objects) for one rider. The same %FTP phases for everyone.
func build_plan() -> EffortPlan:
	var plan := EffortPlan.new()
	for p in phases:
		plan.add(p.duplicate_phase())
	return plan


## The session's phases plus the platform's appended cool-down: what every rider rides.
func timeline() -> Array[PlanPhase]:
	var out: Array[PlanPhase] = []
	for p in phases:
		out.append(p.duplicate_phase())
	out.append(PlanValidator.cooldown_phase())
	return out


## Seconds of the game's own phases (no cool-down).
func total_s() -> float:
	var t := 0.0
	for p in phases:
		t += p.duration_s
	return t


## Seconds including the appended 3-minute cool-down.
func total_with_cooldown_s() -> float:
	return total_s() + COOLDOWN_S


## Plan time (s) at which phase `index` starts.
func start_s(index: int) -> float:
	var t := 0.0
	for i in mini(index, phases.size()):
		t += phases[i].duration_s
	return t


## The lobby preview (GameModule.session_preview): title, total and one line per phase,
## then the importer's clamps and warnings.
func preview() -> Dictionary:
	var strings := GameStrings.new()
	var lines: Array[String] = []
	for p in phases:
		lines.append(describe_phase(p, strings, band_pct))
	for c in clamps:
		lines.append(strings.t("WORKOUT_PREVIEW_CLAMP", {"text": c}))
	for w in warnings:
		lines.append(strings.t("WORKOUT_PREVIEW_WARNING", {"text": w}))
	var title := strings.t(label)
	if source == "zwo" and zwo_name != "":
		title = zwo_name
	return {"title": title, "total_s": total_with_cooldown_s(), "lines": lines}


## One line for a phase: "5:00  Warm-up  50 -> 65% FTP". `band` is the session's SIM WORK
## band in % FTP (Rolling road's 76-105).
static func describe_phase(p: PlanPhase, strings: GameStrings, band: Array = DEFAULT_BAND_PCT) -> String:
	var what := ""
	if p.mode == Wl.ERG:
		if p.has_ramp():
			what = strings.t("WORKOUT_PREVIEW_RAMP", {"from": _pct(p.target_pct), "to": _pct(p.ramp_to_pct)})
		else:
			what = strings.t("WORKOUT_PREVIEW_ERG", {"pct": _pct(p.target_pct)})
	elif p.kind == Wl.FREE:
		what = strings.t("WORKOUT_PREVIEW_FREE")
	else:
		var b: Array = band if band.size() == 2 else DEFAULT_BAND_PCT
		what = strings.t("WORKOUT_PREVIEW_COURSE", {"lo": _pct(float(b[0])), "hi": _pct(float(b[1]))})
	return "%s  %s  %s" % [clock(p.duration_s), strings.t(p.label), what]


## "m:ss" for seconds.
static func clock(seconds: float) -> String:
	var s := int(round(seconds))
	return "%d:%02d" % [s / 60, s % 60]


static func _pct(v: float) -> String:
	return str(int(round(v))) if is_equal_approx(v, round(v)) else "%.1f" % v


static func _is_number(v: Variant) -> bool:
	return v is float or v is int

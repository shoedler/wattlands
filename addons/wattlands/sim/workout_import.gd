class_name ZwoImport
extends RefCounted
## .zwo import (BRIEF 3.7, Workout Director, P0). Owned by sim; public API frozen after W0.
## (W4, QT-6) Named WorkoutImport until W4: platform classes never carry a game prefix, so the
## class is ZwoImport now (the file keeps the path BRIEF 3.7 names). The Workout game keeps a
## deprecated WorkoutImport alias (src/games/workout/rules/workout_import.gd) for one qa test.
## Parses SteadyState, Warmup, Ramp, Cooldown, IntervalsT and FreeRide (as SIM flat) with
## power as a fraction of FTP. Unsupported tags are skipped with a warning. Inserts a
## warm-up prefix if missing and clamps each block to BRIEF 4.6 and the warm-up limits
## before the PlanValidator runs, listing each clamp and its reason for the session
## preview. Games reuse the parser (Siege waves, fishing bites).
##
## Blocks become phases in file order, every one with lap = true and a plain-text label
## (from content/strings/sim.csv): SteadyState -> ERG, WORK at >= 76% FTP else RECOVERY;
## Warmup -> ERG ramp, WARMUP; Cooldown -> ERG ramp, RECOVERY (the PlanValidator appends
## the platform's own cool-down); Ramp -> ERG ramp, kind by its upper end; IntervalsT ->
## Repeat x (WORK at OnPower for OnDuration, RECOVERY at OffPower for OffDuration);
## FreeRide -> SIM flat, FREE. Zwift's PowerLow is a ramp's start and PowerHigh its end,
## whichever is larger. Tag and attribute names match case-insensitively.
##
## Then, in this order (each change is listed in "clamps" and "clamp_records"):
## 1. Warm-up prefix: unless the first block is a Warmup or the first 300 s already keep
##    every ERG value <= 65% FTP, a 300 s ERG ramp 50 -> 65% (WARMUP, "Warm-up") goes first.
## 2. Mode-switch spacing: every run of SIM (or ERG) phases between two ERG <-> SIM
##    switches lasts >= 30 s (the appended ERG cool-down counts as a switch after a final
##    SIM run); a shorter run is extended to 30 s (rule "switch_spacing").
## 3. Warm-up limits: an ERG phase that starts in the first 300 s keeps every value <= 65%;
##    one that runs past 300 s with a value above 65% is first split at 300 s (rule
##    "warmup_split"; the second part continues the lap), then the part inside is clamped
##    (rule "warmup").
## 4. 150% absolute cap (rule "ceiling").
## 5. Phases longer than 300 s cap at 105% (rule "long_phase"); a part split off in step 3
##    counts its whole block's length, so the split never lifts a long block's cap.
## 6. Duration limits, walked in order like the PlanValidator: a phase whose peak is above
##    120% (105%) accrues its whole length; >= 120 consecutive ERG seconds whose peaks are
##    <= 90% reset both counts; a SIM phase restarts that reset count and accrues nothing.
##    A phase that would take the 120% count past 60 s is clamped to 120% (rule
##    "limit_120"); one that would take the 105% count past 300 s is clamped to 105% (rule
##    "limit_105").
## Percentages are rounded to 0.01 and durations to whole seconds (a duration that rounds to
## 0 makes the block invalid). Nothing here changes a block's length except step 2.
## Guards against malformed files: an IntervalsT Repeat above MAX_REPEAT is limited to it
## (with a warning), and a workout longer than MAX_TOTAL_S is rejected.

const WARMUP_S := 300.0
const WARMUP_MAX_PCT := 65.0
const PREFIX_FROM_PCT := 50.0
const PREFIX_TO_PCT := 65.0
const ABS_MAX_PCT := 150.0
const LONG_PHASE_S := 300.0
const LONG_PHASE_CAP_PCT := 105.0
const LIMIT_105_PCT := 105.0
const LIMIT_105_S := 300.0
const LIMIT_120_PCT := 120.0
const LIMIT_120_S := 60.0
const RESET_PCT := 90.0
const RESET_S := 120.0
const SWITCH_SPACING_S := 30.0
## SteadyState (and Ramp by its upper end) at or above this % FTP is WORK, else RECOVERY.
const WORK_MIN_PCT := 76.0
## A power attribute above this is read as a percentage, not a fraction of FTP.
const PERCENT_GUESS_ABOVE := 5.0
## IntervalsT Repeat is limited to this (a typo like Repeat="10000" can't explode the plan).
const MAX_REPEAT := 200
## Longest workout accepted, seconds (24 h), counted from the parsed blocks.
const MAX_TOTAL_S := 86400.0
const EPS := 1e-6

## clamp_records[].rule values. Shared names match Wl.CLAMP_* where the governor has one.
const RULE_WARMUP := Wl.CLAMP_WARMUP
const RULE_WARMUP_SPLIT := "warmup_split"
const RULE_CEILING := Wl.CLAMP_CEILING
const RULE_LONG_PHASE := Wl.CLAMP_LONG_PHASE
const RULE_LIMIT_105 := Wl.CLAMP_LIMIT_105
const RULE_LIMIT_120 := Wl.CLAMP_LIMIT_120
const RULE_SWITCH_SPACING := Wl.REFUSE_SWITCH_SPACING

const BOM := "\uFEFF"

const TAG_STEADY := "SteadyState"
const TAG_WARMUP := "Warmup"
const TAG_COOLDOWN := "Cooldown"
const TAG_RAMP := "Ramp"
const TAG_INTERVALS := "IntervalsT"
const TAG_FREE := "FreeRide"
const SUPPORTED_TAGS: Array[String] = [
	TAG_STEADY,
	TAG_WARMUP,
	TAG_COOLDOWN,
	TAG_RAMP,
	TAG_INTERVALS,
	TAG_FREE,
]


## Parse .zwo XML text. Returns:
## {"ok": bool, "name": String, "description": String,
##  "phases": Array[PlanPhase] (clamped, warm-up prefixed, no cool-down),
##  "blocks": Array[Dictionary] (raw parsed blocks before clamping: {tag, duration_s,
##     power_lo, power_hi, repeat, on_s, off_s, on_power, off_power, cadence}),
##  "clamps": Array[String] (human-readable "block 3: 1.30 -> 1.05 (phase > 300 s cap)"),
##  "warnings": Array[String] (skipped tags, ...), "error": String}
## Added in W1: "clamp_records": Array[Dictionary] ({block, phase, rule, from_pct, to_pct,
## from_s, to_s, text}: block is the 1-based element number inside <workout> (0 for the
## prefix), phase the index in "phases", from/to_pct the [start, end] % FTP before and
## after ([] for spacing), from/to_s the lengths for spacing (-1 otherwise));
## "prefix_inserted": bool; "total_s": float (sum of phase lengths). Each block also
## carries "index" (its element number) and "cadence_resting" (IntervalsT, else -1).
## Powers in "blocks" are fractions of FTP as in the file (-1 where a tag has none).
## A rejected file (not XML, no <workout_file>, no supported block, longer than 24 h, or a
## missing file for parse_zwo_file) returns ok false with "error" set and logs it with
## push_warning: a .zwo is user content. A leading byte-order mark is ignored.
static func parse_zwo(xml_text: String) -> Dictionary:
	var result := _empty_result()
	var doc := _read_xml(xml_text.trim_prefix(BOM))
	if not bool(doc["ok"]):
		return _fail(result, str(doc["error"]))
	result["name"] = doc["name"]
	result["description"] = doc["description"]
	var warnings: Array[String] = []
	var sport := str(doc["sport"]).strip_edges().to_lower()
	if not sport.is_empty() and sport != "bike":
		warnings.append(_t("SIM_ZWO_W_SPORT", {"sport": sport}))

	var blocks: Array[Dictionary] = []
	var elements: Array = doc["elements"]
	for i in elements.size():
		var b := _parse_block(elements[i], i + 1, warnings)
		if not b.is_empty():
			blocks.append(b)
	var child_counts: Dictionary = doc["child_counts"]
	var child_tags: Array = child_counts.keys()
	child_tags.sort()
	for tag: Variant in child_tags:
		warnings.append(_t("SIM_ZWO_W_CHILD", {"tag": str(tag), "count": int(child_counts[tag])}))
	result["blocks"] = blocks
	result["warnings"] = warnings
	if blocks.is_empty():
		return _fail(result, _t("SIM_ZWO_E_EMPTY"))
	var file_s := 0.0
	for b in blocks:
		file_s += float(b["duration_s"])
	if file_s > MAX_TOTAL_S + EPS:
		return _fail(result, _t("SIM_ZWO_E_TOO_LONG", {"hours": roundi(MAX_TOTAL_S / 3600.0)}))

	var ctx := {"next_id": 0, "records": []}
	var segs := _expand(blocks, ctx)
	var prefix := false
	if str(blocks[0]["tag"]) != TAG_WARMUP and not _warmup_within_limits(segs):
		var p := _seg(ctx, 0, "", Wl.WARMUP, Wl.ERG, PREFIX_FROM_PCT, PREFIX_TO_PCT, WARMUP_S)
		p["label_key"] = "SIM_ZWO_PREFIX"
		segs.push_front(p)
		prefix = true
	_fix_switch_spacing(segs, ctx)
	_apply_warmup_limits(segs, ctx)
	_apply_ceiling(segs, ctx)
	_apply_long_phase_cap(segs, ctx)
	_apply_duration_limits(segs, ctx)

	var phases: Array[PlanPhase] = []
	var index_of := {}
	var total := 0.0
	for s in segs:
		index_of[int(s["id"])] = phases.size()
		phases.append(_to_phase(s))
		total += float(s["dur"])
	var clamps: Array[String] = []
	var records: Array[Dictionary] = []
	for r: Dictionary in ctx["records"]:
		var rec := r.duplicate()
		rec["phase"] = int(index_of.get(int(rec["seg_id"]), -1))
		rec.erase("seg_id")
		records.append(rec)
		clamps.append(str(rec["text"]))
	result["ok"] = true
	result["phases"] = phases
	result["clamps"] = clamps
	result["clamp_records"] = records
	result["prefix_inserted"] = prefix
	result["total_s"] = total
	return result


## parse_zwo on a file's text. A missing file returns the same result shape as a rejected
## one, with "error" naming the path.
static func parse_zwo_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail(_empty_result(), _t("SIM_ZWO_E_MISSING", {"path": path}))
	return parse_zwo(FileAccess.get_file_as_string(path))


## An EffortPlan of a successful result's phases (copies; the PlanValidator still has to
## accept it and append the cool-down). Empty plan for a failed result.
static func to_plan(result: Dictionary) -> EffortPlan:
	var plan := EffortPlan.new()
	if not bool(result.get("ok", false)):
		return plan
	for p: Variant in result.get("phases", []):
		if p is PlanPhase:
			plan.phases.append((p as PlanPhase).duplicate_phase())
	return plan


# ------------------------------------------------------------------------------ XML


## {ok, error, name, description, sport, elements: [{tag, attrs (lower-case names)}],
##  child_counts: {tag: n}} for the elements directly inside <workout>.
static func _read_xml(text: String) -> Dictionary:
	var out := {
		"ok": false,
		"error": "",
		"name": "",
		"description": "",
		"sport": "",
		"elements": [],
		"child_counts": {}
	}
	if text.strip_edges().is_empty():
		out["error"] = _t("SIM_ZWO_E_XML", {"why": _t("SIM_ZWO_WHY_EMPTY")})
		return out
	var parser := XMLParser.new()
	var err := parser.open_buffer(text.to_utf8_buffer())
	if err != OK:
		out["error"] = _t("SIM_ZWO_E_XML", {"why": error_string(err)})
		return out
	var stack: Array[String] = []
	var root_seen := false
	var workout_seen := false
	var name_text := ""
	var desc_text := ""
	var sport_text := ""
	var elements: Array = []
	var child_counts: Dictionary = {}
	while true:
		err = parser.read()
		if err == ERR_FILE_EOF:
			break
		if err != OK:
			out["error"] = _t("SIM_ZWO_E_XML", {"why": error_string(err)})
			return out
		var node_type := parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var tag := parser.get_node_name()
			var lower := tag.to_lower()
			if stack.is_empty():
				if root_seen or lower != "workout_file":
					out["error"] = _t(
						"SIM_ZWO_E_XML", {"why": _t("SIM_ZWO_WHY_ROOT", {"tag": tag})}
					)
					return out
				root_seen = true
			elif stack.size() == 2 and stack[1] == "workout":
				var attrs := {}
				for i in parser.get_attribute_count():
					attrs[parser.get_attribute_name(i).to_lower()] = parser.get_attribute_value(i)
				elements.append({"tag": tag, "attrs": attrs})
			elif stack.size() >= 3 and stack[1] == "workout":
				child_counts[tag] = int(child_counts.get(tag, 0)) + 1
			if stack.size() == 1 and lower == "workout":
				workout_seen = true
			if not parser.is_empty():
				stack.append(lower)
		elif node_type == XMLParser.NODE_ELEMENT_END:
			if stack.is_empty() or stack[-1] != parser.get_node_name().to_lower():
				var why := _t("SIM_ZWO_WHY_NESTING", {"tag": parser.get_node_name()})
				out["error"] = _t("SIM_ZWO_E_XML", {"why": why})
				return out
			stack.pop_back()
		elif node_type == XMLParser.NODE_TEXT or node_type == XMLParser.NODE_CDATA:
			if stack.size() == 2:
				# XMLParser decodes entities itself and keeps CDATA content in the node name.
				var data := ""
				if node_type == XMLParser.NODE_TEXT:
					data = parser.get_node_data()
				else:
					data = parser.get_node_name()
				match stack[1]:
					"name":
						name_text += data
					"description":
						desc_text += data
					"sporttype":
						sport_text += data
	if not root_seen:
		out["error"] = _t("SIM_ZWO_E_XML", {"why": _t("SIM_ZWO_WHY_NO_ROOT")})
		return out
	if not stack.is_empty():
		out["error"] = _t("SIM_ZWO_E_XML", {"why": _t("SIM_ZWO_WHY_TRUNCATED", {"tag": stack[-1]})})
		return out
	if not workout_seen:
		out["error"] = _t("SIM_ZWO_E_XML", {"why": _t("SIM_ZWO_WHY_NO_WORKOUT")})
		return out
	out["ok"] = true
	out["name"] = name_text.strip_edges()
	out["description"] = desc_text.strip_edges()
	out["sport"] = sport_text
	out["elements"] = elements
	out["child_counts"] = child_counts
	return out


# --------------------------------------------------------------------------- blocks


## One raw block from an element inside <workout>, or {} (with a warning) when skipped.
static func _parse_block(el: Dictionary, index: int, warnings: Array[String]) -> Dictionary:
	var raw_tag := str(el["tag"])
	var tag := _canonical_tag(raw_tag)
	var attrs: Dictionary = el["attrs"]
	if tag.is_empty():
		warnings.append(_t("SIM_ZWO_W_UNSUPPORTED", {"block": index, "tag": raw_tag}))
		return {}
	var b := {
		"index": index,
		"tag": tag,
		"duration_s": 0.0,
		"power_lo": -1.0,
		"power_hi": -1.0,
		"repeat": 1,
		"on_s": 0.0,
		"off_s": 0.0,
		"on_power": -1.0,
		"off_power": -1.0,
		"cadence": _num_or(attrs, "cadence", -1.0),
		"cadence_resting": -1.0
	}
	var why := ""
	match tag:
		TAG_STEADY:
			var d := _seconds(attrs, "duration")
			var p := _power(attrs, "power", index, warnings)
			if is_nan(p):
				var lo := _power(attrs, "powerlow", index, warnings)
				var hi := _power(attrs, "powerhigh", index, warnings)
				if not is_nan(lo) and not is_nan(hi):
					p = 0.5 * (lo + hi)
					warnings.append(_t("SIM_ZWO_W_MEAN", {"block": index, "tag": tag}))
			if is_nan(d) or d <= 0.0:
				why = "SIM_ZWO_WHY_DURATION"
			elif is_nan(p):
				why = "SIM_ZWO_WHY_POWER"
			elif p < 0.0:
				why = "SIM_ZWO_WHY_NEGATIVE"
			else:
				b["duration_s"] = d
				b["power_lo"] = p
				b["power_hi"] = p
		TAG_WARMUP, TAG_COOLDOWN, TAG_RAMP:
			var d := _seconds(attrs, "duration")
			var lo := _power(attrs, "powerlow", index, warnings)
			var hi := _power(attrs, "powerhigh", index, warnings)
			if is_nan(lo) or is_nan(hi):
				var p := _power(attrs, "power", index, warnings)
				if not is_nan(p):
					lo = p
					hi = p
			if is_nan(d) or d <= 0.0:
				why = "SIM_ZWO_WHY_DURATION"
			elif is_nan(lo) or is_nan(hi):
				why = "SIM_ZWO_WHY_POWER"
			elif lo < 0.0 or hi < 0.0:
				why = "SIM_ZWO_WHY_NEGATIVE"
			else:
				b["duration_s"] = d
				b["power_lo"] = lo
				b["power_hi"] = hi
		TAG_INTERVALS:
			var rep_f := _num(attrs, "repeat")
			var on_s := _seconds(attrs, "onduration")
			var off_s := _seconds(attrs, "offduration", 0.0)
			var on_p := _interval_power(
				attrs, "onpower", "poweronlow", "poweronhigh", index, tag, warnings
			)
			var off_p := _interval_power(
				attrs, "offpower", "powerofflow", "poweroffhigh", index, tag, warnings
			)
			if is_nan(rep_f) or rep_f < 1.0:
				why = "SIM_ZWO_WHY_REPEAT"
			elif is_nan(on_s) or on_s <= 0.0 or is_nan(off_s) or off_s < 0.0:
				why = "SIM_ZWO_WHY_DURATION"
			elif is_nan(on_p) or (off_s > 0.0 and is_nan(off_p)):
				why = "SIM_ZWO_WHY_POWER"
			elif on_p < 0.0 or (off_s > 0.0 and off_p < 0.0):
				why = "SIM_ZWO_WHY_NEGATIVE"
			else:
				var rep := int(floor(minf(rep_f, float(MAX_REPEAT))))
				if rep_f >= MAX_REPEAT + 1.0:
					warnings.append(
						_t(
							"SIM_ZWO_W_REPEAT",
							{"block": index, "repeat": str(attrs["repeat"]), "max": MAX_REPEAT}
						)
					)
				b["repeat"] = rep
				b["on_s"] = on_s
				b["off_s"] = off_s
				b["on_power"] = on_p
				b["off_power"] = off_p if off_s > 0.0 else -1.0
				b["duration_s"] = rep * (on_s + off_s)
				b["cadence_resting"] = _num_or(attrs, "cadenceresting", -1.0)
		TAG_FREE:
			var d := _seconds(attrs, "duration")
			if is_nan(d) or d <= 0.0:
				why = "SIM_ZWO_WHY_DURATION"
			else:
				b["duration_s"] = d
	if not why.is_empty():
		warnings.append(_t("SIM_ZWO_W_BAD_BLOCK", {"block": index, "tag": raw_tag, "why": _t(why)}))
		return {}
	return b


static func _canonical_tag(tag: String) -> String:
	var lower := tag.to_lower()
	for t in SUPPORTED_TAGS:
		if t.to_lower() == lower:
			return t
	return ""


## A number attribute, or NAN when missing or not a number.
static func _num(attrs: Dictionary, key: String) -> float:
	if not attrs.has(key):
		return NAN
	var s := str(attrs[key]).strip_edges()
	if not s.is_valid_float():
		return NAN
	return s.to_float()


static func _num_or(attrs: Dictionary, key: String, fallback: float) -> float:
	var v := _num(attrs, key)
	return fallback if is_nan(v) else v


## A duration attribute rounded to whole seconds (Zwift writes whole seconds; converters
## leave artefacts like 29.999999), `fallback` when missing, or NAN when not a number.
static func _seconds(attrs: Dictionary, key: String, fallback: float = NAN) -> float:
	if not attrs.has(key):
		return fallback
	var v := _num(attrs, key)
	return v if is_nan(v) or is_inf(v) else roundf(v)


## A power attribute as a fraction of FTP (a value above PERCENT_GUESS_ABOVE is read as a
## percentage, with a warning), or NAN.
static func _power(attrs: Dictionary, key: String, index: int, warnings: Array[String]) -> float:
	var v := _num(attrs, key)
	if not is_nan(v) and v > PERCENT_GUESS_ABOVE:
		warnings.append(_t("SIM_ZWO_W_PERCENT", {"block": index, "value": str(attrs[key])}))
		v /= 100.0
	return v


## IntervalsT on/off power: the plain attribute, else the mean of the Low/High pair.
static func _interval_power(
	attrs: Dictionary,
	key: String,
	low_key: String,
	high_key: String,
	index: int,
	tag: String,
	warnings: Array[String]
) -> float:
	var v := _power(attrs, key, index, warnings)
	if not is_nan(v):
		return v
	var lo := _power(attrs, low_key, index, warnings)
	var hi := _power(attrs, high_key, index, warnings)
	if is_nan(lo) or is_nan(hi):
		return NAN
	warnings.append(_t("SIM_ZWO_W_MEAN", {"block": index, "tag": tag}))
	return 0.5 * (lo + hi)


# ------------------------------------------------------------------------- segments


## A working phase: {id, block, part, kind, mode, from, to, dur, span, lap, rep, reps,
## cadence, label_key, orig}. from/to are % FTP (ERG; equal when steady); span is the
## phase's length before the warm-up split (the long-phase cap uses it).
static func _seg(
	ctx: Dictionary,
	block: int,
	part: String,
	kind: String,
	mode: String,
	from_pct: float,
	to_pct: float,
	dur: float
) -> Dictionary:
	var id := int(ctx["next_id"])
	ctx["next_id"] = id + 1
	return {
		"id": id,
		"block": block,
		"part": part,
		"kind": kind,
		"mode": mode,
		"from": _round_pct(from_pct),
		"to": _round_pct(to_pct),
		"dur": dur,
		"span": dur,
		"lap": true,
		"rep": 0,
		"reps": 0,
		"cadence": -1.0,
		"label_key": "",
		"orig": ""
	}


static func _expand(blocks: Array[Dictionary], ctx: Dictionary) -> Array[Dictionary]:
	var segs: Array[Dictionary] = []
	for b in blocks:
		var tag := str(b["tag"])
		var index := int(b["index"])
		var lo := float(b["power_lo"]) * 100.0
		var hi := float(b["power_hi"]) * 100.0
		var d := float(b["duration_s"])
		var cadence := float(b["cadence"])
		if tag == TAG_INTERVALS:
			var reps := int(b["repeat"])
			var on_pct := float(b["on_power"]) * 100.0
			var off_pct := float(b["off_power"]) * 100.0
			for r in reps:
				var on := _seg(ctx, index, "on", Wl.WORK, Wl.ERG, on_pct, on_pct, float(b["on_s"]))
				on["label_key"] = "SIM_ZWO_ON"
				on["rep"] = r + 1
				on["reps"] = reps
				on["cadence"] = cadence
				segs.append(on)
				if float(b["off_s"]) > 0.0:
					var off := _seg(
						ctx, index, "off", Wl.RECOVERY, Wl.ERG, off_pct, off_pct, float(b["off_s"])
					)
					off["label_key"] = "SIM_ZWO_OFF"
					off["rep"] = r + 1
					off["reps"] = reps
					off["cadence"] = float(b["cadence_resting"])
					segs.append(off)
			continue
		var s: Dictionary
		match tag:
			TAG_STEADY:
				var kind := Wl.WORK if _round_pct(lo) >= WORK_MIN_PCT - EPS else Wl.RECOVERY
				s = _seg(ctx, index, "", kind, Wl.ERG, lo, lo, d)
				s["label_key"] = "SIM_ZWO_STEADY"
			TAG_WARMUP:
				s = _seg(ctx, index, "", Wl.WARMUP, Wl.ERG, lo, hi, d)
				s["label_key"] = "SIM_ZWO_WARMUP"
			TAG_COOLDOWN:
				s = _seg(ctx, index, "", Wl.RECOVERY, Wl.ERG, lo, hi, d)
				s["label_key"] = "SIM_ZWO_COOLDOWN"
			TAG_RAMP:
				var kind := (
					Wl.WORK if _round_pct(maxf(lo, hi)) >= WORK_MIN_PCT - EPS else Wl.RECOVERY
				)
				s = _seg(ctx, index, "", kind, Wl.ERG, lo, hi, d)
				s["label_key"] = "SIM_ZWO_RAMP"
			_:
				s = _seg(ctx, index, "", Wl.FREE, Wl.SIM, 0.0, 0.0, d)
				s["label_key"] = "SIM_ZWO_FREE"
		s["cadence"] = cadence
		segs.append(s)
	for s in segs:
		s["orig"] = _label(s)
	return segs


## True when every ERG phase starting in the first 300 s keeps all its values <= 65%.
static func _warmup_within_limits(segs: Array[Dictionary]) -> bool:
	var start := 0.0
	for s in segs:
		if start >= WARMUP_S - EPS:
			break
		if str(s["mode"]) == Wl.ERG and _peak(s) > WARMUP_MAX_PCT + EPS:
			return false
		start += float(s["dur"])
	return true


static func _fix_switch_spacing(segs: Array[Dictionary], ctx: Dictionary) -> void:
	# Runs of consecutive same-mode phases: first and last index of each.
	var firsts: Array[int] = []
	var lasts: Array[int] = []
	for i in segs.size():
		if firsts.is_empty() or str(segs[i]["mode"]) != str(segs[lasts[-1]]["mode"]):
			firsts.append(i)
			lasts.append(i)
		else:
			lasts[-1] = i
	for r in firsts.size():
		var switch_before := r > 0
		var switch_after := r < firsts.size() - 1 or str(segs[lasts[r]]["mode"]) == Wl.SIM
		if not (switch_before and switch_after):
			continue
		var total := 0.0
		for i in range(firsts[r], lasts[r] + 1):
			total += float(segs[i]["dur"])
		if total >= SWITCH_SPACING_S - EPS:
			continue
		var s: Dictionary = segs[lasts[r]]
		var before := float(s["dur"])
		s["dur"] = before + (SWITCH_SPACING_S - total)
		_record_len(ctx, s, RULE_SWITCH_SPACING, before, float(s["dur"]), "SIM_ZWO_REASON_SPACING")


static func _apply_warmup_limits(segs: Array[Dictionary], ctx: Dictionary) -> void:
	var start := 0.0
	var i := 0
	while i < segs.size():
		var s: Dictionary = segs[i]
		if start >= WARMUP_S - EPS:
			break
		var d := float(s["dur"])
		if str(s["mode"]) == Wl.ERG and _peak(s) > WARMUP_MAX_PCT + EPS:
			if start + d > WARMUP_S + EPS:
				var cut := WARMUP_S - start
				var a := float(s["from"])
				var b := float(s["to"])
				var mid := _round_pct(lerpf(a, b, cut / d))
				var tail := s.duplicate()
				tail["id"] = int(ctx["next_id"])
				ctx["next_id"] = int(ctx["next_id"]) + 1
				tail["from"] = mid
				tail["dur"] = d - cut
				tail["lap"] = false
				s["to"] = mid
				s["dur"] = cut
				segs.insert(i + 1, tail)
				_record_pct(
					ctx,
					s,
					RULE_WARMUP_SPLIT,
					[a, b],
					[a, mid],
					"SIM_ZWO_REASON_WARMUP",
					"SIM_ZWO_SPLIT"
				)
			_clamp_to(ctx, s, WARMUP_MAX_PCT, RULE_WARMUP, "SIM_ZWO_REASON_WARMUP")
		start += float(s["dur"])
		i += 1


static func _apply_ceiling(segs: Array[Dictionary], ctx: Dictionary) -> void:
	for s in segs:
		if str(s["mode"]) == Wl.ERG:
			_clamp_to(ctx, s, ABS_MAX_PCT, RULE_CEILING, "SIM_ZWO_REASON_CEILING")


static func _apply_long_phase_cap(segs: Array[Dictionary], ctx: Dictionary) -> void:
	for s in segs:
		var length := maxf(float(s["dur"]), float(s["span"]))
		if str(s["mode"]) == Wl.ERG and length > LONG_PHASE_S + EPS:
			_clamp_to(ctx, s, LONG_PHASE_CAP_PCT, RULE_LONG_PHASE, "SIM_ZWO_REASON_LONG_PHASE")


static func _apply_duration_limits(segs: Array[Dictionary], ctx: Dictionary) -> void:
	var acc_105 := 0.0
	var acc_120 := 0.0
	var reset_run := 0.0
	for s in segs:
		if str(s["mode"]) != Wl.ERG:
			reset_run = 0.0
			continue
		var d := float(s["dur"])
		if _peak(s) > LIMIT_120_PCT + EPS and acc_120 + d > LIMIT_120_S + EPS:
			_clamp_to(ctx, s, LIMIT_120_PCT, RULE_LIMIT_120, "SIM_ZWO_REASON_LIMIT_120")
		if _peak(s) > LIMIT_105_PCT + EPS and acc_105 + d > LIMIT_105_S + EPS:
			_clamp_to(ctx, s, LIMIT_105_PCT, RULE_LIMIT_105, "SIM_ZWO_REASON_LIMIT_105")
		var peak := _peak(s)
		if peak > LIMIT_120_PCT + EPS:
			acc_120 += d
		if peak > LIMIT_105_PCT + EPS:
			acc_105 += d
		if peak <= RESET_PCT + EPS:
			reset_run += d
			if reset_run >= RESET_S - EPS:
				acc_105 = 0.0
				acc_120 = 0.0
		else:
			reset_run = 0.0


## Clamps both ends of an ERG phase to <= cap_pct and records it when that changed anything.
static func _clamp_to(
	ctx: Dictionary, s: Dictionary, cap_pct: float, rule: String, reason_key: String
) -> void:
	var a := float(s["from"])
	var b := float(s["to"])
	if maxf(a, b) <= cap_pct + EPS:
		return
	s["from"] = minf(a, cap_pct)
	s["to"] = minf(b, cap_pct)
	_record_pct(
		ctx, s, rule, [a, b], [float(s["from"]), float(s["to"])], reason_key, "SIM_ZWO_CLAMP"
	)


static func _record_pct(
	ctx: Dictionary,
	s: Dictionary,
	rule: String,
	from_pct: Array,
	to_pct: Array,
	reason_key: String,
	text_key: String
) -> void:
	var text := _t(
		text_key,
		{
			"block": int(s["block"]),
			"label": str(s["orig"]),
			"from": _range_text(float(from_pct[0]), float(from_pct[1])),
			"to": _range_text(float(to_pct[0]), float(to_pct[1])),
			"reason": _t(reason_key)
		}
	)
	(ctx["records"] as Array).append(
		{
			"seg_id": int(s["id"]),
			"block": int(s["block"]),
			"rule": rule,
			"from_pct": from_pct,
			"to_pct": to_pct,
			"from_s": -1.0,
			"to_s": -1.0,
			"text": text
		}
	)


static func _record_len(
	ctx: Dictionary, s: Dictionary, rule: String, from_s: float, to_s: float, reason_key: String
) -> void:
	var text := _t(
		"SIM_ZWO_EXTEND",
		{
			"block": int(s["block"]),
			"label": str(s["orig"]),
			"from": _seconds_text(from_s),
			"to": _seconds_text(to_s),
			"reason": _t(reason_key)
		}
	)
	(ctx["records"] as Array).append(
		{
			"seg_id": int(s["id"]),
			"block": int(s["block"]),
			"rule": rule,
			"from_pct": [],
			"to_pct": [],
			"from_s": from_s,
			"to_s": to_s,
			"text": text
		}
	)


static func _peak(s: Dictionary) -> float:
	return maxf(float(s["from"]), float(s["to"]))


static func _to_phase(s: Dictionary) -> PlanPhase:
	var label := _label(s)
	var p: PlanPhase
	if str(s["mode"]) == Wl.SIM:
		p = PlanPhase.sim(str(s["kind"]), Wl.GRADE_FLAT, float(s["dur"]), label)
	else:
		p = PlanPhase.erg(str(s["kind"]), float(s["from"]), float(s["dur"]), label)
		if absf(float(s["to"]) - float(s["from"])) > EPS:
			p.with_ramp(float(s["to"]))
	p.with_lap(bool(s["lap"]))
	var meta := {"zwo_block": int(s["block"])}
	if float(s["cadence"]) > 0.0:
		meta["cadence_rpm"] = float(s["cadence"])
	p.with_meta(meta)
	return p


static func _label(s: Dictionary) -> String:
	var key := str(s["label_key"])
	return _t(
		key,
		{
			"range": _range_text(float(s["from"]), float(s["to"])),
			"n": int(s["rep"]),
			"count": int(s["reps"])
		}
	)


# ---------------------------------------------------------------------------- text


static func _round_pct(v: float) -> float:
	return roundf(v * 100.0) / 100.0


static func _pct_text(v: float) -> String:
	var r := snappedf(v, 0.1)
	if absf(r - roundf(r)) < 0.05:
		return "%d%%" % int(roundf(r))
	return "%.1f%%" % r


static func _range_text(a: float, b: float) -> String:
	if absf(a - b) <= EPS:
		return _pct_text(a)
	return "%s-%s" % [_pct_text(a).trim_suffix("%"), _pct_text(b)]


static func _seconds_text(s: float) -> String:
	if absf(s - roundf(s)) < 0.005:
		return "%d" % int(roundf(s))
	return "%.1f" % s


## A string from content/strings/sim.csv with {named} placeholders filled.
static func _t(key: String, args: Dictionary = {}) -> String:
	var s := String(TranslationServer.translate(StringName(key)))
	if args.is_empty():
		return s
	return s.format(args)


static func _empty_result() -> Dictionary:
	var phases: Array[PlanPhase] = []
	var blocks: Array[Dictionary] = []
	var clamps: Array[String] = []
	var warnings: Array[String] = []
	var records: Array[Dictionary] = []
	return {
		"ok": false,
		"name": "",
		"description": "",
		"phases": phases,
		"blocks": blocks,
		"clamps": clamps,
		"warnings": warnings,
		"error": "",
		"clamp_records": records,
		"prefix_inserted": false,
		"total_s": 0.0
	}


static func _fail(result: Dictionary, error: String) -> Dictionary:
	result["ok"] = false
	result["error"] = error
	push_warning("ZwoImport: %s" % error)
	return result

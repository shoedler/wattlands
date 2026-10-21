class_name PlanPhase
extends RefCounted
## One phase of a rider's EffortPlan (BRIEF 3.6). Contract, frozen after W0.
##
## ERG phases use `target_pct` (% of the rider's own FTP), an optional linear
## `ramp_to_pct` across the phase, and an optional `range_pct` [lo, hi] that bounds
## how far directives may move the ERG target during the phase (default
## [target_pct, target_pct]; with a ramp, [min, max] of the ramp).
## SIM phases use `grade_source`: "flat" (0%), "course" (follow `course_profile`
## [[distance_m, grade_pct], ...] by the rider's distance from the speed model,
## BRIEF 3.11) or "game" (the game pushes the grade with `ctx.directives.course_grade`).
## `open_ended` phases end when the game calls `end_phase` (after `min_s`) or at
## `max_s`; `duration_s` is then their nominal length (used for previews only).
##
## Build phases with the fluent helpers:
## [codeblock]
## PlanPhase.erg(Wl.WARMUP, 50, 300, "Warm-up").with_ramp(65).with_lap()
## PlanPhase.erg(Wl.WORK, 55, 180, "Advance").with_range(55, 100).with_open(90, 300)
## PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 30, "Sprint")
## [/codeblock]

## Sentinel for "no value" in optional float fields.
const NONE := -1.0

var kind: String = Wl.WORK
var mode: String = Wl.ERG
## ERG: planned target in % FTP at the phase start.
var target_pct: float = 0.0
## ERG: optional linear ramp end in % FTP (NONE = no ramp).
var ramp_to_pct: float = NONE
## ERG: optional [lo_pct, hi_pct] directive range. Empty = default (see effective_range()).
var range_pct: Array = []
## SIM: "flat" | "course" | "game".
var grade_source: String = Wl.GRADE_FLAT
## SIM with grade_source "course": [[distance_m, grade_pct], ...], distance ascending from 0.
var course_profile: Array = []
var duration_s: float = 0.0
var open_ended: bool = false
var min_s: float = 0.0
var max_s: float = 0.0
## True: the ride recorder starts a FIT lap at this phase's start.
var lap: bool = false
## Display label (a string key or plain text); also the FIT lap name.
var label: String = ""
## Game-defined data the platform never reads (for example a wave number).
var meta: Dictionary = {}


static func erg(
	p_kind: String, p_target_pct: float, p_duration_s: float, p_label: String = ""
) -> PlanPhase:
	var p := PlanPhase.new()
	p.kind = p_kind
	p.mode = Wl.ERG
	p.target_pct = p_target_pct
	p.duration_s = p_duration_s
	p.label = p_label
	return p


static func sim(
	p_kind: String, p_grade_source: String, p_duration_s: float, p_label: String = ""
) -> PlanPhase:
	var p := PlanPhase.new()
	p.kind = p_kind
	p.mode = Wl.SIM
	p.grade_source = p_grade_source
	p.duration_s = p_duration_s
	p.label = p_label
	return p


## Linear ramp from target_pct to `to_pct` across the phase.
func with_ramp(to_pct: float) -> PlanPhase:
	ramp_to_pct = to_pct
	return self


## Directive range [lo, hi] in % FTP.
func with_range(lo_pct: float, hi_pct: float) -> PlanPhase:
	range_pct = [lo_pct, hi_pct]
	return self


## Mark open-ended with min_s and max_s; duration_s stays the nominal length.
func with_open(p_min_s: float, p_max_s: float) -> PlanPhase:
	open_ended = true
	min_s = p_min_s
	max_s = p_max_s
	return self


func with_lap(on: bool = true) -> PlanPhase:
	lap = on
	return self


func with_course(profile: Array) -> PlanPhase:
	grade_source = Wl.GRADE_COURSE
	course_profile = profile
	return self


func with_meta(data: Dictionary) -> PlanPhase:
	meta = data
	return self


func has_ramp() -> bool:
	return ramp_to_pct >= 0.0


## Planned ERG target in % FTP after `elapsed_s` seconds (linear ramp if any).
## Open-ended phases ramp over their nominal duration_s and then hold.
func planned_pct_at(elapsed_s: float) -> float:
	if not has_ramp() or duration_s <= 0.0:
		return target_pct
	var f := clampf(elapsed_s / duration_s, 0.0, 1.0)
	return lerpf(target_pct, ramp_to_pct, f)


## [lo, hi] the ERG target may take in this phase, including the ramp's span.
func effective_range() -> Array:
	var lo := target_pct
	var hi := target_pct
	if has_ramp():
		lo = minf(lo, ramp_to_pct)
		hi = maxf(hi, ramp_to_pct)
	if range_pct.size() == 2:
		lo = minf(lo, float(range_pct[0]))
		hi = maxf(hi, float(range_pct[1]))
	return [lo, hi]


## Length the safety rules use (BRIEF 4.6.1): max_s for open-ended phases, else duration_s.
func worst_case_length_s() -> float:
	return max_s if open_ended else duration_s


## Shortest possible length: min_s for open-ended phases, else duration_s.
func best_case_length_s() -> float:
	return min_s if open_ended else duration_s


## Highest ERG % FTP this phase may command (target, ramp end and range top).
func peak_pct() -> float:
	return float(effective_range()[1])


func duplicate_phase() -> PlanPhase:
	return PlanPhase.from_dict(to_dict())


func to_dict() -> Dictionary:
	var d := {
		"kind": kind,
		"mode": mode,
		"duration_s": duration_s,
		"lap": lap,
		"label": label,
	}
	if mode == Wl.ERG:
		d["target_pct"] = target_pct
		if has_ramp():
			d["ramp_to_pct"] = ramp_to_pct
		if range_pct.size() == 2:
			d["range_pct"] = [float(range_pct[0]), float(range_pct[1])]
	else:
		d["grade_source"] = grade_source
		if grade_source == Wl.GRADE_COURSE:
			d["course_profile"] = course_profile.duplicate(true)
	if open_ended:
		d["open_ended"] = true
		d["min_s"] = min_s
		d["max_s"] = max_s
	if not meta.is_empty():
		d["meta"] = meta.duplicate(true)
	return d


static func from_dict(d: Dictionary) -> PlanPhase:
	var p := PlanPhase.new()
	p.kind = str(d.get("kind", Wl.WORK))
	p.mode = str(d.get("mode", Wl.ERG))
	p.target_pct = float(d.get("target_pct", 0.0))
	p.ramp_to_pct = float(d.get("ramp_to_pct", NONE))
	var r: Variant = d.get("range_pct", [])
	if r is Array and (r as Array).size() == 2:
		p.range_pct = [float(r[0]), float(r[1])]
	p.grade_source = str(d.get("grade_source", Wl.GRADE_FLAT))
	var cp: Variant = d.get("course_profile", [])
	if cp is Array:
		for pt: Variant in cp:
			if pt is Array and (pt as Array).size() >= 2:
				p.course_profile.append([float(pt[0]), float(pt[1])])
	p.duration_s = float(d.get("duration_s", 0.0))
	p.open_ended = bool(d.get("open_ended", false))
	p.min_s = float(d.get("min_s", 0.0))
	p.max_s = float(d.get("max_s", 0.0))
	p.lap = bool(d.get("lap", false))
	p.label = str(d.get("label", ""))
	var m: Variant = d.get("meta", {})
	if m is Dictionary:
		p.meta = (m as Dictionary).duplicate(true)
	return p

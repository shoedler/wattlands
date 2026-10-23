class_name FishingSpeciesDef
extends FishingRecord
## One species from content/fishing/species.json (brief 2.3 species table; G0 contract).
##
## species.json: {"species": [entry, ...]}, entry:
##   {"id": "mahi", "label": "FISHING_SPECIES_MAHI", "sprite": "fish_mahi",
##    "t_nom_s": [120, 240], "max_s": 270, "pull_pct": [88, 95], "change_pct": 8,
##    "runs": {"kind": "run", "count": [2, 3], "dur_s": [15, 30], "peak_pct": [105, 110],
##             "peak_factor": 0, "band_shift": 8, "min_gap_s": 0, "leaps": [0, 0],
##             "sounding": false},
##    "band_offset": 8, "kg": [7, 20], "d_max": 80}
## runs.kind is "none" (count [0, 0]), "run" or "jump". A run's peak is either absolute
## (peak_pct [lo, hi], drawn per run) or relative (peak_factor x the slot's base pull, with
## peak_pct [0, 0]). Jumps carry leaps [lo, hi] and min_gap_s (marlin: 90 s apart).

const RUN_NONE := "none"
const RUN_RUN := "run"
const RUN_JUMP := "jump"

var id: String = ""
var label: String = ""
var sprite: String = ""
var t_nom_lo: float = 0.0
var t_nom_hi: float = 0.0
var max_s: float = 0.0
var pull_lo: float = 0.0
var pull_hi: float = 0.0
## a, the pull-change amplitude in % of the base pull (4 = +-4 %).
var change_pct: float = 0.0
var run_kind: String = RUN_NONE
var runs_lo: int = 0
var runs_hi: int = 0
var run_s_lo: float = 0.0
var run_s_hi: float = 0.0
var run_peak_lo: float = 0.0
var run_peak_hi: float = 0.0
var run_peak_factor: float = 0.0
var run_band_shift: float = 0.0
var run_min_gap_s: float = 0.0
var leaps_lo: int = 0
var leaps_hi: int = 0
var sounding: bool = false
var band_offset: float = 0.0
var kg_lo: float = 0.0
var kg_hi: float = 0.0
var d_max: float = 0.0


static func from_dict(d: Dictionary) -> FishingSpeciesDef:
	var s := FishingSpeciesDef.new()
	s.id = str(d.get("id", ""))
	s.label = str(d.get("label", "FISHING_SPECIES_%s" % s.id.to_upper()))
	s.sprite = str(d.get("sprite", "fish_%s" % s.id))
	var t: Array = d.get("t_nom_s", [0, 0])
	s.t_nom_lo = float(t[0])
	s.t_nom_hi = float(t[1])
	s.max_s = float(d.get("max_s", 0))
	var p: Array = d.get("pull_pct", [0, 0])
	s.pull_lo = float(p[0])
	s.pull_hi = float(p[1])
	s.change_pct = float(d.get("change_pct", 0))
	var r: Dictionary = d.get("runs", {})
	s.run_kind = str(r.get("kind", RUN_NONE))
	var c: Array = r.get("count", [0, 0])
	s.runs_lo = int(c[0])
	s.runs_hi = int(c[1])
	var rs: Array = r.get("dur_s", [0, 0])
	s.run_s_lo = float(rs[0])
	s.run_s_hi = float(rs[1])
	var pk: Array = r.get("peak_pct", [0, 0])
	s.run_peak_lo = float(pk[0])
	s.run_peak_hi = float(pk[1])
	s.run_peak_factor = float(r.get("peak_factor", 0))
	s.run_band_shift = float(r.get("band_shift", 0))
	s.run_min_gap_s = float(r.get("min_gap_s", 0))
	var lp: Array = r.get("leaps", [0, 0])
	s.leaps_lo = int(lp[0])
	s.leaps_hi = int(lp[1])
	s.sounding = bool(r.get("sounding", false))
	s.band_offset = float(d.get("band_offset", 0))
	var kg: Array = d.get("kg", [0, 0])
	s.kg_lo = float(kg[0])
	s.kg_hi = float(kg[1])
	s.d_max = float(d.get("d_max", 0))
	return s


## The run peak for a slot with base pull `base_pct` and a draw u in [0, 1]; 0 without runs.
func run_peak(base_pct: float, u: float) -> float:
	if run_kind == RUN_NONE:
		return 0.0
	if run_peak_factor > 0.0:
		return base_pct * run_peak_factor
	return lerpf(run_peak_lo, run_peak_hi, u)


## The highest run peak this species can reach at `base_pct` (for range_pct).
func max_run_peak(base_pct: float) -> float:
	if run_kind == RUN_NONE:
		return 0.0
	if run_peak_factor > 0.0:
		return base_pct * run_peak_factor
	return run_peak_hi


## Every problem with one species.json entry ([] when valid). Pure; FishingContent pushes them.
static func errors(d: Variant) -> Array[String]:
	var out: Array[String] = []
	if not d is Dictionary:
		out.append("species entry is not an object")
		return out
	var e: Dictionary = d
	var entry_id: String = str(e.get("id", ""))
	var at := "species %s" % entry_id
	if not FishingConst.SPECIES.has(entry_id):
		out.append("%s: unknown id (expected one of %s)" % [at, FishingConst.SPECIES])
	for key: String in ["t_nom_s", "pull_pct", "kg"]:
		if not _pair_ok(e.get(key)):
			out.append("%s: %s must be [lo, hi] with 0 < lo <= hi" % [at, key])
	for key: String in ["max_s", "d_max"]:
		if not (e.get(key) is float or e.get(key) is int) or float(e.get(key)) <= 0.0:
			out.append("%s: %s must be a positive number" % [at, key])
	if _pair_ok(e.get("t_nom_s")) and float(e.get("max_s", 0)) < float(e["t_nom_s"][1]):
		out.append("%s: max_s must be >= the T_nom window's high end" % at)
	if _pair_ok(e.get("pull_pct")):
		if float(e["pull_pct"][0]) < 50.0 or float(e["pull_pct"][1]) > FishingConst.SELF_CAP_PCT:
			out.append("%s: pull_pct must lie in 50..110" % at)
	var a: Variant = e.get("change_pct", 0)
	if not (a is float or a is int) or float(a) < 0.0 or float(a) > 10.0:
		out.append("%s: change_pct must be 0..10" % at)
	if not (e.get("band_offset", 0) is float or e.get("band_offset", 0) is int):
		out.append("%s: band_offset must be a number" % at)
	var r: Variant = e.get("runs", {})
	if not r is Dictionary:
		out.append("%s: runs must be an object" % at)
		return out
	var kind := str((r as Dictionary).get("kind", RUN_NONE))
	if not kind in [RUN_NONE, RUN_RUN, RUN_JUMP]:
		out.append("%s: runs.kind must be none, run or jump" % at)
	elif kind != RUN_NONE:
		if not _pair_ok(r.get("count")) or not _pair_ok(r.get("dur_s")):
			out.append("%s: runs.count and runs.dur_s must be [lo, hi]" % at)
		var pk: Variant = r.get("peak_pct", [0, 0])
		var factor := float(r.get("peak_factor", 0))
		if factor <= 0.0 and not _pair_ok(pk):
			out.append("%s: runs need peak_pct [lo, hi] or a peak_factor" % at)
		if factor <= 0.0 and _pair_ok(pk) and float(pk[1]) > FishingConst.SELF_CAP_PCT:
			out.append("%s: a run peak above 110 %%" % at)
		if factor > 1.2:
			out.append("%s: runs.peak_factor above 1.2" % at)
		if _pair_ok(r.get("dur_s")) and float(r["dur_s"][1]) > FishingConst.RUN_MAX_ABOVE_105_S:
			out.append("%s: a run longer than 30 s" % at)
		if kind == RUN_JUMP and not _pair_ok(r.get("leaps")):
			out.append("%s: jumps need leaps [lo, hi]" % at)
	return out


static func _pair_ok(v: Variant) -> bool:
	if not v is Array or (v as Array).size() != 2:
		return false
	for x: Variant in v:
		if not (x is float or x is int) or float(x) <= 0.0:
			return false
	return float(v[0]) <= float(v[1])

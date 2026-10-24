class_name FishingSpeciesDef
extends FishingRecord
## One species from content/fishing/species.json (the species table; contract v2).
##
## species.json: {"species": [entry, ...]}, one entry per FishingConst.SPECIES id, e.g.
##   {"id": "mahi", "label": "FISHING_SPECIES_MAHI", "sprite": "fish_mahi",
##    "zones": ["reef"], "rarity": 45, "depth_m": [3, 15], "near_floor": false, "kg": [7, 20],
##    "t_nom_s": [100, 170], "max_s": 210, "pull_pct": [82, 88], "change_pct": 8,
##    "runs": {"kind": "run", "count": [2, 3], "dur_s": [15, 25], "peak_pct": [0, 0],
##             "peak_factor": 1.1, "band_shift": 8, "min_gap_s": 0, "leaps": [0, 0],
##             "sounding": false},
##    "band_offset": 8, "d_max": 70}
## zones: FishingWorld.ZONES ids where the species shows in Free Roam (never "dock"); rarity:
## its relative weight among the zone's species when hints are drawn; depth_m: the swimming
## depth range in metres (near_floor true: the fish holds 3-10 m above the sea floor instead,
## the giant grouper); kg: the weight range (a hint's size w in [0, 1] sets kg = lerp(lo, hi, w)
## and the fight's base pull and T_nom). sprite: the view's sprite id, fish_<id>.
## The fight model: T_nom window, max_s (the Fight phase's max_s; above 300 s every target caps at
## 105 %, BRIEF 4.6.1), pull_pct (base pull window, 50..110), change_pct, runs, band_offset and
## d_max (the farthest the fish swims from the boat in a fight, m). runs.kind is "none" (count
## [0, 0]), "run" or "jump". A run's peak is either absolute (peak_pct [lo, hi], drawn per run) or
## relative (peak_factor x the base pull, with peak_pct [0, 0]). Jumps carry leaps [lo, hi] and
## min_gap_s (90 s apart). floor(0.8 x the T_nom low end) must be >= 30 s, so every Fight lasts at
## least 30 s (BRIEF 4.5 switch spacing between its ERG and the SIM phases around it).

const RUN_NONE := "none"
const RUN_RUN := "run"
const RUN_JUMP := "jump"

var id: String = ""
var label: String = ""
var sprite: String = ""
## FishingWorld.ZONES ids where the species bites in Free Roam.
var zones: Array[String] = []
var rarity: float = 1.0
var depth_lo: float = 0.0
var depth_hi: float = 0.0
var near_floor: bool = false
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
	for z: Variant in d.get("zones", []):
		s.zones.append(str(z))
	s.rarity = float(d.get("rarity", 1))
	var dp: Array = d.get("depth_m", [0, 0])
	s.depth_lo = float(dp[0])
	s.depth_hi = float(dp[1])
	s.near_floor = bool(d.get("near_floor", false))
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


## kg for a hint size w in [0, 1].
func kg_at(w: float) -> float:
	return lerpf(kg_lo, kg_hi, clampf(w, 0.0, 1.0))


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
	if (
		_pair_ok(e.get("t_nom_s"))
		and floorf(FishingConst.FIGHT_MIN_FRAC * float(e["t_nom_s"][0])) < FishingConst.FIGHT_MIN_S
	):
		out.append("%s: floor(0.8 x the T_nom low end) must be >= 30 s" % at)
	var zs: Variant = e.get("zones", [])
	if not zs is Array or (zs as Array).is_empty():
		out.append("%s: zones must be a non-empty array" % at)
	else:
		for z: Variant in zs:
			if not FishingWorld.ZONES.has(str(z)) or str(z) == "dock":
				out.append("%s: unknown zone %s" % [at, z])
	if (
		not (e.get("rarity", 0) is float or e.get("rarity", 0) is int)
		or float(e.get("rarity", 0)) <= 0.0
	):
		out.append("%s: rarity must be positive" % at)
	var dp: Variant = e.get("depth_m", [0, 0])
	if (
		not dp is Array
		or (dp as Array).size() != 2
		or float(dp[0]) < 0.0
		or float(dp[1]) < float(dp[0])
		or (float(dp[1]) <= 0.0 and not bool(e.get("near_floor", false)))
	):
		out.append(
			"%s: depth_m must be [lo, hi] with 0 <= lo <= hi (hi > 0 unless near_floor)" % at
		)
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

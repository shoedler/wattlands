class_name WorkoutImport
extends RefCounted
## .zwo import (BRIEF 3.7, Workout Director, P0). Owned by sim; public API frozen after W0.
## Parses SteadyState, Warmup, Ramp, Cooldown, IntervalsT and FreeRide (as SIM flat) with
## power as a fraction of FTP. Unsupported tags are skipped with a warning. Inserts a
## warm-up prefix if missing and clamps each block to BRIEF 4.6 and the warm-up limits
## before the PlanValidator runs, listing each clamp and its reason for the session
## preview. Games reuse the parser (Siege waves, fishing bites).


## Parse .zwo XML text. Returns:
## {"ok": bool, "name": String, "description": String,
##  "phases": Array[PlanPhase] (clamped, warm-up prefixed, no cool-down),
##  "blocks": Array[Dictionary] (raw parsed blocks before clamping: {tag, duration_s,
##     power_lo, power_hi, repeat, on_s, off_s, on_power, off_power, cadence}),
##  "clamps": Array[String] (human-readable "block 3: 1.30 -> 1.05 (phase > 300 s cap)"),
##  "warnings": Array[String] (skipped tags, ...), "error": String}
static func parse_zwo(_xml_text: String) -> Dictionary:
	return {"ok": false, "name": "", "description": "", "phases": [], "blocks": [],
		"clamps": [], "warnings": [], "error": "not implemented"}


static func parse_zwo_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "missing file %s" % path, "phases": [], "blocks": [],
			"clamps": [], "warnings": [], "name": "", "description": ""}
	return parse_zwo(FileAccess.get_file_as_string(path))

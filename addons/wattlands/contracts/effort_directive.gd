class_name EffortDirective
extends RefCounted
## A game's request to change one rider's trainer load inside the current phase
## (BRIEF 3.6, 5.5 `directive`). Contract, frozen after W0.
##
## Directives work per channel. A request changes only the channels whose fields it
## sets; a later request on a channel replaces it and cancels that channel's pending
## expiry. Channels:
##   - ERG target: `target_pct`, `target_wkg` or `target_w` (converted to % FTP first)
##   - SIM block: `mode = "SIM"` inside an ERG phase (10 s <= duration_s <= 30 s). A SIM
##     block exists only in an ERG phase: in a SIM phase `mode: "SIM"` is a no-op
##     confirmation (no channel, no length or spacing rule, no expiry) and `mode: "ERG"` is
##     refused (Wl.REFUSE_ERG_IN_SIM). Use channels_for_phase(), not channels(), to route.
##   - mode grade: `mode_grade` (only inside a SIM block or a SIM phase)
##   - haptic: `haptic` (grade %) or `haptic_wind` (m/s headwind), at most 8 s
##   - factors: `crr` and `cw`, relative factors in [0.5, 1.0]
## `duration_s` applies to the channels this request sets; 0 means "until the phase
## ends". On expiry only those channels revert to the plan.
## Unset fields are NAN (floats) or "" (strings); `to_dict()` emits set fields only, so
## a report shows exactly what the game asked for.
##
## [codeblock]
## ctx.directives.request(peer, EffortDirective.from_dict(
##     {"mode": "SIM", "duration_s": 30, "reason": "overdrive", "source": "siege"}))
## [/codeblock]

const FLOAT_FIELDS: Array[String] = [
	"target_pct", "target_wkg", "target_w", "mode_grade", "haptic", "haptic_wind", "crr", "cw",
]

## "" (unset), "ERG" or "SIM".
var mode: String = ""
var target_pct: float = NAN
var target_wkg: float = NAN
var target_w: float = NAN
var mode_grade: float = NAN
## Haptic grade in % (before the rider's intensity setting).
var haptic: float = NAN
## Haptic headwind in m/s (bounded to the force of +3% grade at the current speed).
var haptic_wind: float = NAN
var crr: float = NAN
var cw: float = NAN
var duration_s: float = 0.0
var reason: String = ""
var source: String = ""
## Assigned by the DirectiveSink; echoed in applied records and acks.
var id: int = 0


static func make(fields: Dictionary) -> EffortDirective:
	return from_dict(fields)


func is_set(field: String) -> bool:
	if field == "mode":
		return mode != ""
	if FLOAT_FIELDS.has(field):
		return not is_nan(float(get(field)))
	return false


func sets_erg_target() -> bool:
	return is_set("target_pct") or is_set("target_wkg") or is_set("target_w")


func sets_sim_block() -> bool:
	return mode == Wl.SIM


func sets_haptic() -> bool:
	return is_set("haptic") or is_set("haptic_wind")


func sets_factors() -> bool:
	return is_set("crr") or is_set("cw")


## Names of the channels this request touches: "erg_target", "sim_block", "mode_grade",
## "haptic", "factors". A request with mode "ERG" and no target touches "sim_block"
## (it ends a running SIM block).
func channels() -> Array[String]:
	var out: Array[String] = []
	if sets_erg_target():
		out.append("erg_target")
	if mode != "":
		out.append("sim_block")
	if is_set("mode_grade"):
		out.append("mode_grade")
	if sets_haptic():
		out.append("haptic")
	if sets_factors():
		out.append("factors")
	return out


## The channels this request touches when the rider's current phase has mode `phase_mode`
## ("ERG" or "SIM"): like channels(), but "sim_block" only in an ERG phase.
func channels_for_phase(phase_mode: String) -> Array[String]:
	var out := channels()
	if phase_mode == Wl.SIM:
		out.erase("sim_block")
	return out


## Set fields only. Keys: mode, target_pct, target_wkg, target_w, mode_grade, haptic,
## haptic_wind, crr, cw, duration_s, reason, source (and id when non-zero).
func to_dict() -> Dictionary:
	var d := {}
	if mode != "":
		d["mode"] = mode
	for f in FLOAT_FIELDS:
		var v: float = get(f)
		if not is_nan(v):
			d[f] = v
	d["duration_s"] = duration_s
	if reason != "":
		d["reason"] = reason
	if source != "":
		d["source"] = source
	if id != 0:
		d["id"] = id
	return d


static func from_dict(d: Dictionary) -> EffortDirective:
	var e := EffortDirective.new()
	e.mode = str(d.get("mode", ""))
	for f in FLOAT_FIELDS:
		if d.has(f) and d[f] != null:
			e.set(f, float(d[f]))
	e.duration_s = float(d.get("duration_s", 0.0))
	e.reason = str(d.get("reason", ""))
	e.source = str(d.get("source", ""))
	e.id = int(d.get("id", 0))
	return e


func duplicate_directive() -> EffortDirective:
	return EffortDirective.from_dict(to_dict())

class_name AppScriptedReport
extends RefCounted
## The scripted peer's JSON report (docs/ARCHITECTURE.md, scripted peers), written on exit:
## {role, peer_id, room, game_id, content_id, exit_reason,
##  events: [{t, type, peer, ...}]  session states ("session_state", state), phase_started per
##          rider ("phase_started", index), game events in arrival order ("game_event", event,
##          event_type) and results ("results", grade, session_id),
##  directives: [applied records, each with "peer"],
##  trace: [{t, mode, applied_target_w, applied_pct, applied_grade_pct, warmup_active,
##           clamped_by, rescue, afk}] (1 Hz, local rider),
##  fit_paths: [...], uploads: [{state, activity_id}], desync_warnings, script_errors,
##  final_state: {...}}
## `t` is the peer's platform time in seconds. No secret or token is ever written here.

const SCHEMA := 1

var role: String = ""
var peer_id: int = 0
var room: String = ""
var game_id: String = ""
var content_id: String = ""
var exit_reason: String = ""
var events: Array = []
var directives: Array = []
var trace: Array = []
var fit_paths: Array = []
var uploads: Array = []
var desync_warnings: int = 0
var script_errors: int = 0
var errors: int = 0
var final_state: Dictionary = {}
var _directive_keys: Dictionary = {}


func add_event(t: float, type: String, peer: int, extra: Dictionary = {}) -> Dictionary:
	var e := {"t": snappedf(t, 0.001), "type": type, "peer": peer}
	for k: Variant in extra.keys():
		e[k] = extra[k]
	events.append(e)
	return e


## An applied directive record (deduplicated: the bus and the rider may both report it).
func add_directive(peer: int, record: Dictionary) -> bool:
	var r := record.duplicate(true)
	r["peer"] = peer
	var key := (
		"%d|%s|%s|%s" % [peer, str(r.get("id", "")), str(r.get("kind", "")), str(r.get("t", ""))]
	)
	if r.get("id", null) == null and not r.has("t"):
		key = JSON.stringify(r)
	if _directive_keys.has(key):
		return false
	_directive_keys[key] = true
	directives.append(r)
	return true


## One 1 Hz trace entry from a governor status (or telemetry) dictionary.
func add_trace(t: float, status: Dictionary) -> Dictionary:
	var clamps: Array = []
	for c: Variant in status.get("clamped_by", []):
		clamps.append(str(c))
	var e := {
		"t": snappedf(t, 0.001),
		"mode": str(status.get("mode", Wl.OFF)),
		"applied_target_w": int(status.get("applied_target_w", 0)),
		"applied_pct": float(status.get("applied_pct", 0.0)),
		"applied_grade_pct": float(status.get("applied_grade_pct", 0.0)),
		"warmup_active": bool(status.get("warmup_active", false)),
		"clamped_by": clamps,
		"rescue": bool(status.get("rescue", false)),
		"afk": bool(status.get("afk", false)),
	}
	trace.append(e)
	return e


func add_fit(path: String) -> void:
	if path != "" and not fit_paths.has(path):
		fit_paths.append(path)


func add_upload(state: String, activity_id: Variant) -> void:
	uploads.append({"state": state, "activity_id": activity_id})


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA,
		"role": role,
		"peer_id": peer_id,
		"room": room,
		"game_id": game_id,
		"content_id": content_id,
		"exit_reason": exit_reason,
		"events": events.duplicate(true),
		"directives": directives.duplicate(true),
		"trace": trace.duplicate(true),
		"fit_paths": fit_paths.duplicate(),
		"uploads": uploads.duplicate(true),
		"desync_warnings": desync_warnings,
		"script_errors": script_errors,
		"errors": errors,
		"final_state": final_state.duplicate(true),
	}


## Write the report as JSON (creating folders). Returns false on failure.
func write(path: String) -> bool:
	if path == "":
		return false
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("scripted report: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return true

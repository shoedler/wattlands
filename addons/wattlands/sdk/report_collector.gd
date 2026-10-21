class_name ReportCollector
extends RefCounted
## Collects the run_game_sim report data on one peer (BRIEF 3.6; docs/OWNERSHIP.md SIM4,
## C9): events in order, every directive as requested (with the host's verdict) and as
## applied by the rider's governor (clamped_by or the refusal reason), the 1 Hz trace per
## rider, and each snapshot's sha256 and JSON byte size. The GameHost fills it when
## setup(report = true); GameSimRunner.build_report() reads to_dict() and adds the rest.
##
## Times: `t` is game seconds (the game clock stops while paused) and `pt` platform seconds.
## Snapshot bytes are the UTF-8 length of JSON.stringify(state) (state only, no envelope);
## the sha256 is over the same bytes (3.1 C9).

## Relay limit for one message (BRIEF 5.3).
const MAX_MESSAGE_BYTES := NetMessages.MAX_MESSAGE_BYTES

var events: Array = []
## Ordered directive entries: {id, peer, t, kind, requested, accepted, reason, applied}.
var directives: Array = []
## peer (int) -> Array of 1 Hz trace rows.
var traces: Dictionary = {}
## [{seq, tick, sha256, bytes}]
var snapshots: Array = []
var max_snapshot_bytes: int = 0
var oversize_snapshots: int = 0
## Applied records whose id matched no requested entry (kept, never dropped).
var orphan_applied: Array = []
var _by_id: Dictionary = {}


func event(t: float, pt: float, type: String, fields: Dictionary = {}) -> void:
	var e := {"t": t, "pt": pt, "type": type}
	for k: Variant in fields.keys():
		e[k] = fields[k]
	events.append(e)


## A directive call as the game made it, with the host's verdict.
func directive_requested(peer: int, id: int, kind: String, requested: Dictionary, t: float, accepted: bool, reason: String) -> void:
	var d := {
		"id": id, "peer": peer, "t": t, "kind": kind, "requested": requested.duplicate(true),
		"accepted": accepted, "reason": reason, "applied": null,
	}
	directives.append(d)
	if id != 0:
		_by_id[id] = d


## What the rider's governor did with it (the record from LocalRider.apply_directive or a
## telemetry ack): {id, kind, requested, applied, clamped_by, refused, reason, t}.
func directive_applied(peer: int, record: Dictionary) -> void:
	var id := int(record.get("id", 0))
	var rec := record.duplicate(true)
	if id != 0 and _by_id.has(id):
		(_by_id[id] as Dictionary)["applied"] = rec
		return
	rec["peer"] = peer
	orphan_applied.append(rec)


func trace(peer: int, row: Dictionary) -> void:
	if not traces.has(peer):
		traces[peer] = []
	(traces[peer] as Array).append(row)


## Record a snapshot; returns {sha256, bytes}.
func snapshot(seq: int, tick: int, state: Dictionary) -> Dictionary:
	var m := measure(state)
	var entry := {"seq": seq, "tick": tick, "sha256": m["sha256"], "bytes": m["bytes"]}
	snapshots.append(entry)
	max_snapshot_bytes = maxi(max_snapshot_bytes, int(m["bytes"]))
	return m


## {sha256, bytes} of JSON.stringify(state) (UTF-8).
static func measure(state: Dictionary) -> Dictionary:
	var text := JSON.stringify(state)
	return {"sha256": text.sha256_text(), "bytes": text.to_utf8_buffer().size()}


func count_oversize() -> void:
	oversize_snapshots += 1


func snapshot_hashes() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in snapshots:
		out.append(str(s["sha256"]))
	return out


## JSON-safe copy (peer-keyed dictionaries use string keys).
func to_dict() -> Dictionary:
	var tr := {}
	for peer: Variant in traces.keys():
		tr[str(peer)] = (traces[peer] as Array).duplicate(true)
	return {
		"events": events.duplicate(true),
		"directives": directives.duplicate(true),
		"directives_unmatched": orphan_applied.duplicate(true),
		"trace": tr,
		"snapshots": snapshots.duplicate(true),
		"max_snapshot_bytes": max_snapshot_bytes,
		"oversize_snapshots": oversize_snapshots,
	}

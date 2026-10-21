class_name NetRoster
extends RefCounted
## The BRIEF 5.5 roster (host -> all, 2 Hz): per slot raw W, cadence, %FTP, rescue, afk,
## connected and the latest teammate_status, keyed by int peer id. The teammate strip draws
## it on every peer and games read it as ctx.roster (OWNERSHIP CTX12). The GameHost builds
## it with build() from its slots, the latest telemetry and the statuses from
## ctx.hud.teammate_status, and sends it with WlNetSession.send_roster(). Owned by
## net-client; pure functions.

## Entry keys, in order.
const FIELDS: Array[String] = ["peer_id", "name", "slot_index", "is_bot", "raw_w", "cadence_rpm",
	"ftp_pct", "rescue", "afk", "connected", "status"]


## One rider's roster entry. `tm` may be null (no telemetry yet: zeros, connected).
static func entry(slot: PlayerSlot, tm: Telemetry, status: Dictionary = {}) -> Dictionary:
	var e := {
		"peer_id": slot.peer_id,
		"name": slot.name,
		"slot_index": slot.slot_index,
		"is_bot": slot.is_bot,
		"raw_w": 0.0,
		"cadence_rpm": 0.0,
		"ftp_pct": 0.0,
		"rescue": false,
		"afk": false,
		"connected": true,
		"status": status.duplicate(true),
	}
	if tm != null:
		e["raw_w"] = tm.power_w
		e["cadence_rpm"] = tm.cadence_rpm
		e["ftp_pct"] = tm.ftp_pct if tm.ftp_pct > 0.0 else EffortScaling.ftp_pct(tm.power_w, slot.ftp)
		e["rescue"] = tm.rescue
		e["afk"] = tm.afk
		e["connected"] = tm.connected
	return e


## {peer_id: entry} for every slot in slot order. `telemetry` maps peer -> Telemetry,
## `statuses` peer -> {in_band, icon, text} (both may miss peers).
static func build(slots: Array[PlayerSlot], telemetry: Dictionary, statuses: Dictionary = {}) -> Dictionary:
	var ordered := slots.duplicate()
	ordered.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.slot_index < b.slot_index)
	var out: Dictionary = {}
	for s: PlayerSlot in ordered:
		var tm: Variant = telemetry.get(s.peer_id)
		var st: Variant = statuses.get(s.peer_id, {})
		out[s.peer_id] = entry(s, tm as Telemetry if tm is Telemetry else null,
			st as Dictionary if st is Dictionary else {})
	return out

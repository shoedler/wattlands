class_name TemplateRules
extends RefCounted
## Pure, deterministic rules (BRIEF 3.6): step(state, inputs, dt) reads only its arguments, never
## the wall clock or a global RNG. state: {tick, track_m, mps_per_w, boost_mult, boost_s, riders:
## [{peer, slot, dist_m, laps, boost_s, rescue, afk}] in slot order}; inputs: {peer: {p_eff_w, boost}}.

const CONTENT_KEYS: Array[String] = ["phases", "nudge_pct", "nudge_at_s", "nudge_s",
	"lap_marker_at_s", "mps_per_w", "boost_mult", "boost_s"]


## "" when a content file is usable, else the reason (content is validated at load, BRIEF 6).
static func content_error(c: Variant) -> String:
	if not (c is Dictionary):
		return "content is not a JSON object"
	var missing := CONTENT_KEYS.filter(func(k: String) -> bool: return not (c as Dictionary).has(k))
	if not missing.is_empty():
		return "missing \"%s\"" % missing[0]
	return "" if c["phases"] is Array and not (c["phases"] as Array).is_empty() else "\"phases\" is empty"


static func new_state(c: Dictionary, peers: Array[int], track_m: float) -> Dictionary:
	var riders: Array = []
	for i in peers.size():
		riders.append({"peer": peers[i], "slot": i, "dist_m": 0.0, "laps": 0, "boost_s": 0.0, "rescue": false, "afk": false})
	return {"tick": 0, "track_m": track_m, "mps_per_w": float(c["mps_per_w"]),
		"boost_mult": float(c["boost_mult"]), "boost_s": float(c["boost_s"]), "riders": riders}


## Marker speed in m/s: proportional to P_eff, so every FTP plays fair (BRIEF 3.3).
static func speed(state: Dictionary, p_eff_w: float, boosting: bool) -> float:
	return maxf(p_eff_w, 0.0) * float(state["mps_per_w"]) * (float(state["boost_mult"]) if boosting else 1.0)


## Advances the state by dt; returns the game events raised ({"type": "boost" | "lap", ...}).
static func step(state: Dictionary, inputs: Dictionary, dt: float) -> Array:
	var events: Array = []
	state["tick"] = int(state["tick"]) + 1
	for rd: Dictionary in state["riders"]:
		var inp: Dictionary = inputs.get(rd["peer"], {})
		if bool(inp.get("boost", false)) and float(rd["boost_s"]) <= 0.0:
			rd["boost_s"] = float(state["boost_s"])
			events.append({"type": "boost", "slot": rd["slot"]})
		var stopped: bool = rd["rescue"] or rd["afk"]
		var v := 0.0 if stopped else speed(state, float(inp.get("p_eff_w", 0.0)), float(rd["boost_s"]) > 0.0)
		rd["boost_s"] = maxf(snappedf(float(rd["boost_s"]) - dt, 0.001), 0.0)  # whole ms: ends exactly
		rd["dist_m"] = float(rd["dist_m"]) + v * dt
		var laps := int(floorf(float(rd["dist_m"]) / float(state["track_m"])))
		if laps > int(rd["laps"]):
			rd["laps"] = laps
			events.append({"type": "lap", "slot": rd["slot"], "laps": laps})
	return events


## The rider entry for `peer` (or for slot index `slot` when peer is null); {} if unknown.
static func rider(state: Dictionary, peer: Variant, slot: int = -1) -> Dictionary:
	for rd: Dictionary in state.get("riders", []):
		if (peer != null and int(rd["peer"]) == int(peer)) or (peer == null and int(rd["slot"]) == slot):
			return rd
	return {}

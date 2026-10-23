class_name SiegeEvents
extends RefCounted
## The event schema (brief 2.6; G0 contract). The rules return these dictionaries from step();
## the module sends each with send_event() (batched, in order, to every client) and raises the
## host's own effects for its local rider; clients raise theirs in apply_event(). Every number
## is an int on the wire (declared in int_fields()); strings stay strings.
##
## type           fields
## wave_start     ph (phase index), role (String), n (wave number; 0 = the warm-up wave),
##                waves, b (threat budget, rounded), roads [road ids active]
## wave_end       ph, n, hp (gate HP), max (gate max), leaks (this wave)
## roads          roads [the next active road ids], in_ms (the horn: they switch in 5000 ms)
## push           roads [road ids that got a ram] (the ram push at 60 s left)
## rush           on (1 start, 0 end), i (rush index 0..)
## kill           id (enemy), et (enemy type), pad (the tower; 0 none), road, x2 (1: double bounty)
## leak           id, et, road, dmg (gate HP lost; a ram's battering: one leak per whole HP)
## breach         n (breaches so far)
## gate_restored  hp
## buy            slot, item (String), pad (0 unless a pad item), ok (1 / 0), why (String; "" when
##                ok, else a SiegeIds.BUY_* reason), lvl (the pad's level / generator level /
##                iron bands after it; 0 when refused)
## route          slot, to (TARGET_GEN or a pad)
## overdrive      slot, st (SiegeIds.OD_EV_START 1 / END 0 / REFUSED 2), scored (1: the sprint
##                rule held >= 10 s; END only), why (String; REFUSED: the refusal reason)

const INT_FIELDS := {
	SiegeIds.EV_WAVE_START: ["ph", "n", "waves", "b", "roads[]"],
	SiegeIds.EV_WAVE_END: ["ph", "n", "hp", "max", "leaks"],
	SiegeIds.EV_ROADS: ["roads[]", "in_ms"],
	SiegeIds.EV_PUSH: ["roads[]"],
	SiegeIds.EV_RUSH: ["on", "i"],
	SiegeIds.EV_KILL: ["id", "et", "pad", "road", "x2"],
	SiegeIds.EV_LEAK: ["id", "et", "road", "dmg"],
	SiegeIds.EV_BREACH: ["n"],
	SiegeIds.EV_GATE_RESTORED: ["hp"],
	SiegeIds.EV_BUY: ["slot", "pad", "ok", "lvl"],
	SiegeIds.EV_ROUTE: ["slot", "to"],
	SiegeIds.EV_OVERDRIVE: ["slot", "st", "scored"],
}


## int_fields() for GameModule: the snapshot's paths plus every event type's.
static func int_fields() -> Dictionary:
	var out := {"snapshot": SiegeSnapshotSchema.INT_PATHS.duplicate()}
	for k: String in INT_FIELDS:
		out[k] = (INT_FIELDS[k] as Array).duplicate()
	return out


## A copy of `event` with every declared int field cast with int() (nested arrays included);
## apply_event calls it on everything it reads.
static func cast(event: Dictionary) -> Dictionary:
	var out := event.duplicate(true)
	for path: String in INT_FIELDS.get(str(event.get("type", "")), []):
		var key := path.trim_suffix("[]")
		if not out.has(key):
			continue
		if path.ends_with("[]") and out[key] is Array:
			out[key] = (out[key] as Array).map(func(v: Variant) -> int: return int(v))
		elif out[key] is float or out[key] is int or out[key] is bool:
			out[key] = int(out[key])
	return out


## "" when `event` has a known type and every declared field, else the problem.
static func check(event: Dictionary) -> String:
	var type := str(event.get("type", ""))
	if not INT_FIELDS.has(type):
		return "unknown type %s" % type
	for path: String in INT_FIELDS[type]:
		if not event.has(path.trim_suffix("[]")):
			return "%s: missing %s" % [type, path.trim_suffix("[]")]
	if type == SiegeIds.EV_BUY and not (event.get("item") is String and event.get("why") is String):
		return "buy: item and why are strings"
	if type == SiegeIds.EV_WAVE_START and not (event.get("role") is String):
		return "wave_start: role is a string"
	if type == SiegeIds.EV_OVERDRIVE and not (event.get("why") is String):
		return "overdrive: why is a string"
	return ""


static func wave_start(
	ph: int, role: String, n: int, waves: int, budget: float, roads: Array[int]
) -> Dictionary:
	return {
		"type": SiegeIds.EV_WAVE_START,
		"ph": ph,
		"role": role,
		"n": n,
		"waves": waves,
		"b": roundi(budget),
		"roads": roads.duplicate()
	}


static func wave_end(ph: int, n: int, gate_hp: float, gate_max: float, leaks: int) -> Dictionary:
	return {
		"type": SiegeIds.EV_WAVE_END,
		"ph": ph,
		"n": n,
		"hp": ceili(gate_hp),
		"max": roundi(gate_max),
		"leaks": leaks
	}


static func roads(next_roads: Array[int], in_ms: int) -> Dictionary:
	return {"type": SiegeIds.EV_ROADS, "roads": next_roads.duplicate(), "in_ms": in_ms}


static func push(push_roads: Array[int]) -> Dictionary:
	return {"type": SiegeIds.EV_PUSH, "roads": push_roads.duplicate()}


static func rush(on: bool, i: int) -> Dictionary:
	return {"type": SiegeIds.EV_RUSH, "on": int(on), "i": i}


static func kill(id: int, et: int, pad: int, road: int, double: bool) -> Dictionary:
	return {
		"type": SiegeIds.EV_KILL, "id": id, "et": et, "pad": pad, "road": road, "x2": int(double)
	}


static func leak(id: int, et: int, road: int, dmg: int) -> Dictionary:
	return {"type": SiegeIds.EV_LEAK, "id": id, "et": et, "road": road, "dmg": dmg}


static func breach(n: int) -> Dictionary:
	return {"type": SiegeIds.EV_BREACH, "n": n}


static func gate_restored(hp: float) -> Dictionary:
	return {"type": SiegeIds.EV_GATE_RESTORED, "hp": ceili(hp)}


static func buy(slot: int, item: String, pad: int, ok: bool, why: String, lvl: int) -> Dictionary:
	return {
		"type": SiegeIds.EV_BUY,
		"slot": slot,
		"item": item,
		"pad": pad,
		"ok": int(ok),
		"why": why,
		"lvl": lvl if ok else 0
	}


static func route(slot: int, to: int) -> Dictionary:
	return {"type": SiegeIds.EV_ROUTE, "slot": slot, "to": to}


static func overdrive(slot: int, st: int, scored: bool = false, why: String = "") -> Dictionary:
	return {
		"type": SiegeIds.EV_OVERDRIVE, "slot": slot, "st": st, "scored": int(scored), "why": why
	}

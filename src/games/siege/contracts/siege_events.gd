class_name SiegeEvents
extends RefCounted
## The event schema (brief 2.6). The rules return these dictionaries from step(); the module
## sends each with send_event() (batched, in order, to every client) and raises the host's own
## effects for its local rider; clients raise theirs in apply_event(). Every number is an int on
## the wire (declared in int_fields()); strings stay strings.
##
## type           fields
## wave_start     ph (phase index), role (String), n (wave number; 0 = the warm-up wave),
##                waves, b (threat budget, rounded)
## wave_end       ph, n, hp (gate HP), max (gate max), leaks (this wave)
## rush           on (1 start, 0 end), i (rush index 0..)
## push           id (the engine), et (SiegeIds.ENEMY_RAM or ENEMY_TOWER), prog_dm (where it
##                entered): a siege engine entered the road
## dock           id: the siege tower docked at the moat edge (its boarders are on the wall)
## reach          id, et: a ram reached the gate (it batters from now on)
## shot           tk (tick), src (a station 1..3, or 10 + pad), kind (SiegeIds.SHOT_*),
##                o [x_cm, y_cm, z_cm], v [vx_mms, vy_mms, vz_mms] (before spread), n (count:
##                a rack of arrows is one event with 12), sd (the spread seed)
## kill           id (enemy), et (enemy type), src (as shot; 0: none), x2 (1: double bounty)
## leak           id, et, dmg (gate HP lost, the curtain's share included; a ram's battering:
##                one leak per whole HP)
## breach         n (breaches so far)
## gate_restored  hp
## buy            slot, item (String), station (0 unless a station item), pad (0 unless a pad
##                item), ok (1 / 0), why (String; "" when ok, else a SiegeIds.BUY_* reason), lvl
##                (the station's / pad's / mine's level or the iron bands after it, the gate HP
##                after a repair, 1 for a perk; 0 when refused)
## route          slot, to (a station 0..4)
## overdrive      slot, st (SiegeIds.OD_EV_START 1 / END 0 / REFUSED 2), scored (1: the sprint
##                rule held >= 10 s; END only), why (String; REFUSED: the refusal reason)

const INT_FIELDS := {
	SiegeIds.EV_WAVE_START: ["ph", "n", "waves", "b"],
	SiegeIds.EV_WAVE_END: ["ph", "n", "hp", "max", "leaks"],
	SiegeIds.EV_RUSH: ["on", "i"],
	SiegeIds.EV_PUSH: ["id", "et", "prog_dm"],
	SiegeIds.EV_DOCK: ["id"],
	SiegeIds.EV_REACH: ["id", "et"],
	SiegeIds.EV_SHOT: ["tk", "src", "kind", "o[]", "v[]", "n", "sd"],
	SiegeIds.EV_KILL: ["id", "et", "src", "x2"],
	SiegeIds.EV_LEAK: ["id", "et", "dmg"],
	SiegeIds.EV_BREACH: ["n"],
	SiegeIds.EV_GATE_RESTORED: ["hp"],
	SiegeIds.EV_BUY: ["slot", "station", "pad", "ok", "lvl"],
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
			out[key] = (out[key] as Array).map(_to_int)
		elif out[key] is float or out[key] is int or out[key] is bool:
			out[key] = WireRead.int_of(out[key])
	return out


static func _to_int(v: Variant) -> int:
	return WireRead.int_of(v)


## "" when `event` has a known type and every declared field, else the problem.
static func check(event: Dictionary) -> String:
	var type := str(event.get("type", ""))
	if not INT_FIELDS.has(type):
		return "unknown type %s" % type
	var problem := WireRead.int_path_problem(event, INT_FIELDS[type])
	if problem != "":
		return "%s: %s" % [type, problem]
	if type == SiegeIds.EV_BUY and not (event.get("item") is String and event.get("why") is String):
		return "buy: item and why are strings"
	if type == SiegeIds.EV_WAVE_START and not (event.get("role") is String):
		return "wave_start: role is a string"
	if type == SiegeIds.EV_OVERDRIVE and not (event.get("why") is String):
		return "overdrive: why is a string"
	if type == SiegeIds.EV_SHOT:
		for k: String in ["o", "v"]:
			if not (event[k] is Array) or (event[k] as Array).size() != 3:
				return "shot: %s needs 3 numbers" % k
	return ""


static func wave_start(ph: int, role: String, n: int, waves: int, budget: float) -> Dictionary:
	return {
		"type": SiegeIds.EV_WAVE_START,
		"ph": ph,
		"role": role,
		"n": n,
		"waves": waves,
		"b": roundi(budget),
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


static func rush(on: bool, i: int) -> Dictionary:
	return {"type": SiegeIds.EV_RUSH, "on": int(on), "i": i}


static func push(id: int, et: int, prog_m: float) -> Dictionary:
	return {"type": SiegeIds.EV_PUSH, "id": id, "et": et, "prog_dm": roundi(prog_m * 10.0)}


static func dock(id: int) -> Dictionary:
	return {"type": SiegeIds.EV_DOCK, "id": id}


static func reach(id: int, et: int) -> Dictionary:
	return {"type": SiegeIds.EV_REACH, "id": id, "et": et}


## A shot from already quantized origin (cm) and velocity (mm/s) ints.
static func shot(
	tk: int, src: int, kind: int, o_cm: Array[int], v_mms: Array[int], n: int, sd: int
) -> Dictionary:
	return {
		"type": SiegeIds.EV_SHOT,
		"tk": tk,
		"src": src,
		"kind": kind,
		"o": o_cm.duplicate(),
		"v": v_mms.duplicate(),
		"n": n,
		"sd": sd,
	}


static func kill(id: int, et: int, src: int, double: bool) -> Dictionary:
	return {"type": SiegeIds.EV_KILL, "id": id, "et": et, "src": src, "x2": int(double)}


static func leak(id: int, et: int, dmg: int) -> Dictionary:
	return {"type": SiegeIds.EV_LEAK, "id": id, "et": et, "dmg": dmg}


static func breach(n: int) -> Dictionary:
	return {"type": SiegeIds.EV_BREACH, "n": n}


static func gate_restored(hp: float) -> Dictionary:
	return {"type": SiegeIds.EV_GATE_RESTORED, "hp": ceili(hp)}


static func buy(
	slot: int, item: String, station: int, pad: int, ok: bool, why: String, lvl: int
) -> Dictionary:
	return {
		"type": SiegeIds.EV_BUY,
		"slot": slot,
		"item": item,
		"station": station,
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


## Origin in whole centimetres and velocity in whole mm/s, the shot event's resolution.
static func quantize_o(p: Vector3) -> Array[int]:
	return [roundi(p.x * 100.0), roundi(p.y * 100.0), roundi(p.z * 100.0)]


static func quantize_v(v: Vector3) -> Array[int]:
	return [roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0)]


## The origin (m) and velocity (m/s) a shot event carries, as every peer reads them.
static func shot_origin(e: Dictionary) -> Vector3:
	var o: Array = e.get("o", [0, 0, 0])
	return Vector3(int(o[0]) / 100.0, int(o[1]) / 100.0, int(o[2]) / 100.0)


static func shot_velocity(e: Dictionary) -> Vector3:
	var v: Array = e.get("v", [0, 0, 0])
	return Vector3(int(v[0]) / 1000.0, int(v[1]) / 1000.0, int(v[2]) / 1000.0)

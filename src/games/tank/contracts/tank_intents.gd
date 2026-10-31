class_name TankIntents
extends RefCounted
## The intent schema (brief 2.6), its validator and its ownership rule (G0 contract). Clients
## send intents in Telemetry.intents at 5 Hz; the platform never converts their numbers, so the
## host runs every intent through normalize() (ints with int(), junk rejected), owned() (only the
## rider on the matching engine) and TankIntentLimiter (5 a second per peer) before the rules
## see it; accepted intents apply on the next tick.
##
## Wire forms (what local_intents(), autopilot_intents() and Tank Controls send):
##   {"k": "seat", "to": "diesel" | "dynamo" | "steam" | "arc" | "feed" | "repair" | "next" | "prev",
##    "via"?}
##                                              v3: move to that seat (or step through TankIds.SEATS)
##   {"k": "aim", "d": 1 | -1, "via"?}          nudge the elevation up / down (auto-aim pauses 5 s)
##   {"k": "target", "d": 1 | -1, "via"?}       cycle targets
##   {"k": "traverse", "via"?}                  flip the turret's facing
##   {"k": "fire", "via"?}                      fire the loaded shell
##   {"k": "latch", "via"?}                     latch a light shell at >= 40% (steam, Bulwark hoist)
##   {"k": "over", "via"?}                      Overpressure inside the window (steam)
##   {"k": "turn", "via"?}                      free roam: turn the tank round (diesel)
##   (v2: the Ram and its "ram" intent are gone, brief 2.4; "Surge to evade" has no intent: the
##   legs are the input. The diesel owns `turn`, which the rules refuse outside free roam. v3: the
##   Bulwark's "lever" is gone too: junk to normalize.)
##   "via": "action" (default) | "surge" | "button" | "auto"; "auto": 1 marks Autopilot output.
## Normalized form (what TankRiderInput.intents holds):
##   {"k": String, "to": int (seat: the named seat's TankIds engine code, or -1 for a step), "d":
##    int (seat step +1 next / -1 prev, aim or target direction; 0 when unused), "auto": bool,
##    "via": String}
## `auto` is true for "auto": 1 (any non-zero number or true) or "via": "auto". Auto intents and
## over never end a human's Autopilot fallback (TankIds.DELIBERATE_KINDS); local_intents turns a
## surge only into over, never fire or latch (brief 2.5).

const MAX_KEYS := 6
## Which seat may send which intent (brief 2.2, 2.6; v3 seat table): the Gun (dynamo) aims, picks
## targets, traverses and fires; the Loader (steam engine) latches and overpressures; Drive (the
## diesel) owns the free-roam `turn` (brief 2.10); Lights (arc), Secondaries (feed) and Repairs own no
## action. v3: every seat owns `seat` (any rider may ask to move; the rules judge the move).
const OWNERS := {
	TankIds.ENGINE_DIESEL: [TankIds.INTENT_TURN, TankIds.INTENT_SEAT],
	TankIds.ENGINE_DYNAMO:
	[
		TankIds.INTENT_AIM,
		TankIds.INTENT_TARGET,
		TankIds.INTENT_TRAVERSE,
		TankIds.INTENT_FIRE,
		TankIds.INTENT_SEAT
	],
	TankIds.ENGINE_STEAM: [TankIds.INTENT_LATCH, TankIds.INTENT_OVER, TankIds.INTENT_SEAT],
	TankIds.ENGINE_ARC: [TankIds.INTENT_SEAT],
	TankIds.ENGINE_FEED: [TankIds.INTENT_SEAT],
	TankIds.ENGINE_REPAIR: [TankIds.INTENT_SEAT],
}
## Seat "to" words that step instead of naming a seat (d: next +1, prev -1).
const SEAT_STEPS := {TankIds.SEAT_TO_NEXT: 1, TankIds.SEAT_TO_PREV: -1}


## The normalized intent, or {} when `raw` is junk (not a Dictionary, unknown "k", a bad "to" or
## "d", too many keys).
static func normalize(raw: Variant) -> Dictionary:
	if not (raw is Dictionary) or (raw as Dictionary).size() > MAX_KEYS:
		return {}
	var d: Dictionary = raw
	var k: Variant = d.get("k")
	if not (k is String) or not TankIds.INTENT_KINDS.has(k):
		return {}
	var via := str(d.get("via", TankIds.VIA_ACTION)) if d.get("via", "") is String else ""
	if via == "":
		via = TankIds.VIA_ACTION
	if not TankIds.VIAS.has(via):
		return {}
	var auto := via == TankIds.VIA_AUTO or _truthy(d.get("auto", 0))
	if auto:
		via = TankIds.VIA_AUTO
	var out := {"k": k, "to": -1, "d": 0, "auto": auto, "via": via}
	match str(k):
		TankIds.INTENT_SEAT:
			var to: Variant = d.get("to")
			if not (to is String):
				return {}
			if TankIds.SEATS.has(to):
				out["to"] = TankIds.engine_code(to)
			elif SEAT_STEPS.has(to):
				out["d"] = int(SEAT_STEPS[to])
			else:
				return {}
		TankIds.INTENT_AIM, TankIds.INTENT_TARGET:
			var dir: Variant = d.get("d")
			if not _whole(dir) or absi(int(dir)) != 1:
				return {}
			out["d"] = int(dir)
	return out


## True when a rider working `engine` may send an intent of kind `kind`.
static func owned(kind: String, engine: String) -> bool:
	return (OWNERS.get(engine, []) as Array).has(kind)


## True when `n` (normalized) ends a human's Autopilot fallback (brief 2.5).
static func is_deliberate(n: Dictionary) -> bool:
	return not bool(n.get("auto", false)) and TankIds.DELIBERATE_KINDS.has(str(n.get("k", "")))


## Wire-form helpers for local_intents(), autopilot_intents() and the HUD.
static func make(kind: String, via: String = TankIds.VIA_ACTION) -> Dictionary:
	return {"k": kind, "via": via}


## v3: a seat move to `to` (an engine id, or TankIds.SEAT_TO_NEXT / SEAT_TO_PREV).
static func seat(to: String, via: String = TankIds.VIA_ACTION) -> Dictionary:
	return {"k": TankIds.INTENT_SEAT, "to": to, "via": via}


## v3: the seat a normalized seat intent `n` asks for, from a rider on `engine`: the named seat,
## else the step from `engine` through TankIds.SEATS; "" for anything else.
static func seat_wanted(n: Dictionary, engine: String) -> String:
	if str(n.get("k", "")) != TankIds.INTENT_SEAT:
		return ""
	var to := int(n.get("to", -1))
	if to > 0:
		return TankIds.engine_of(to)
	var step := int(n.get("d", 0))
	return TankIds.seat_step(engine, step) if step != 0 else ""


static func aim(dir: int, via: String = TankIds.VIA_ACTION) -> Dictionary:
	return {"k": TankIds.INTENT_AIM, "d": dir, "via": via}


static func target(dir: int, via: String = TankIds.VIA_ACTION) -> Dictionary:
	return {"k": TankIds.INTENT_TARGET, "d": dir, "via": via}


## An Autopilot intent (tagged "auto": 1 so it never ends a fallback).
static func auto(kind: String) -> Dictionary:
	return {"k": kind, "auto": 1}


## Normalizes a list, drops junk and intents `engine` doesn't own (order kept).
static func filter_owned(list: Array, engine: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in list:
		var n := normalize(raw)
		if not n.is_empty() and owned(str(n["k"]), engine):
			out.append(n)
	return out


static func _whole(v: Variant) -> bool:
	return (v is int) or (v is float and is_finite(v) and float(v) == floorf(v))


static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) != 0.0
	return false

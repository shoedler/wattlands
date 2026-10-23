class_name SiegeIntents
extends RefCounted
## The intent schema (brief 2.6) and its validator (G0 contract). Clients send intents in
## Telemetry.intents at 5 Hz; the platform never converts their numbers, so the host runs every
## intent through normalize() (ints with int(), junk rejected) and SiegeIntentLimiter (5 a
## second per peer) before the rules see it.
##
## Wire forms (what local_intents() and the shop panel send):
##   {"k": "route", "to": "gen" | 1..8 | "next" | "prev" | "hot", "via"?: String}
##   {"k": "buy", "item": <SiegeIds.ITEMS>, "pad": 1..8 (build_* and upgrade only), "auto"?: 1,
##    "via"?: String}  -- "auto": 1 when the PedalScanList auto-confirmed it (item_picked via "auto")
##   {"k": "overdrive", "via": "action" | "surge" | "button"}  -- ability_1, a surge, the HUD button
## Normalized form (what SiegeRiderInput.intents holds):
##   {"k": String, "to": int (route: TARGET_GEN, a pad, ROUTE_NEXT / PREV / HOT; else 0),
##    "item": String ("" unless buy), "pad": int (0 unless a pad item), "auto": bool, "via": String}
## `auto` is true for "auto": 1 (any non-zero number or true) or "via": "auto". Auto intents
## never end a zero-input fallback and never start Overdrive.

const MAX_KEYS := 8


## The normalized intent, or {} when `raw` is junk (not a Dictionary, unknown "k", a bad
## target, item or pad, too many keys).
static func normalize(raw: Variant) -> Dictionary:
	if not (raw is Dictionary) or (raw as Dictionary).size() > MAX_KEYS:
		return {}
	var d: Dictionary = raw
	var k: Variant = d.get("k")
	if not (k is String) or not SiegeIds.INTENT_KINDS.has(k):
		return {}
	var via := str(d.get("via", SiegeIds.VIA_ACTION)) if d.get("via", "") is String else ""
	if via == "":
		via = SiegeIds.VIA_ACTION
	if not SiegeIds.VIAS.has(via):
		return {}
	var auto := via == SiegeIds.VIA_AUTO or _truthy(d.get("auto", 0))
	if auto:
		via = SiegeIds.VIA_AUTO
	var out := {"k": k, "to": 0, "item": "", "pad": 0, "auto": auto, "via": via}
	match str(k):
		SiegeIds.INTENT_ROUTE:
			var to: Variant = d.get("to")
			if to is String and SiegeIds.ROUTE_WORDS.has(to):
				out["to"] = int(SiegeIds.ROUTE_WORDS[to])
			elif _whole(to) and SiegeIds.is_pad(int(to)):
				out["to"] = int(to)
			else:
				return {}
		SiegeIds.INTENT_BUY:
			var item: Variant = d.get("item")
			if not (item is String) or not SiegeIds.ITEMS.has(item):
				return {}
			out["item"] = item
			if SiegeIds.PAD_ITEMS.has(item):
				var pad: Variant = d.get("pad")
				if not _whole(pad) or not SiegeIds.is_pad(int(pad)):
					return {}
				out["pad"] = int(pad)
		SiegeIds.INTENT_OVERDRIVE:
			pass
	return out


## Wire-form helpers for local_intents() and the HUD.
static func route(to: Variant, via: String = SiegeIds.VIA_ACTION) -> Dictionary:
	return {"k": SiegeIds.INTENT_ROUTE, "to": to, "via": via}


static func buy(item: String, pad: int = 0, auto: bool = false) -> Dictionary:
	var d := {"k": SiegeIds.INTENT_BUY, "item": item}
	if SiegeIds.PAD_ITEMS.has(item):
		d["pad"] = pad
	if auto:
		d["auto"] = 1
	return d


static func overdrive(via: String) -> Dictionary:
	return {"k": SiegeIds.INTENT_OVERDRIVE, "via": via}


## Normalizes a list and drops the junk (order kept).
static func normalize_all(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in list:
		var n := normalize(raw)
		if not n.is_empty():
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

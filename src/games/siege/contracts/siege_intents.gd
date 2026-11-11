class_name SiegeIntents
extends RefCounted
## The intent schema (brief 2.6) and its validator. Clients send intents in
## Telemetry.intents at 5 Hz; the platform never converts their numbers, so the host runs every
## intent through normalize() (ints with int(), junk rejected) and SiegeIntentLimiter (5 a
## second per peer) before the rules see it.
##
## Wire forms (what local_intents() and the shop panel send):
##   {"k": "route", "to": "mine" | 0..4 | "next" | "prev" | "hot", "via"?: String}  ("gen" is
##    accepted as "mine")
##   {"k": "pick", "item": <SiegeIds.ITEMS>, "station": 1..4 (upgrade only), "pad": 1..4
##    (scorpion and pad_upgrade only), "lvl"?: 1..3 (the level of an upgrade, mine level or pad
##    upgrade the pick is about; absent: the lowest on the receipt, else the next), "auto"?: 1,
##    "via"?: String}  -- one pick: the host adds
##    the item to the shared receipt, takes your own back, or votes on someone else's (the next
##    pick of it returns the vote). Nothing is spent until the break ends. "auto": 1 when the
##    PedalScanList auto-confirmed it (item_picked via "auto"): the rules ignore it. "buy" is
##    the old wire word and reads as "pick".
##   {"k": "overdrive", "via": "action" | "surge" | "button"}  -- ability_1, a surge, the HUD button
## Normalized form (what SiegeRiderInput.intents holds):
##   {"k": String, "to": int (route: a station 0..4, ROUTE_NEXT / PREV / HOT; else 0),
##    "item": String ("" unless pick), "station": int (0 unless a station item), "pad": int (0
##    unless a pad item), "lvl": int (0 unless pick), "auto": bool, "via": String}
## `auto` is true for "auto": 1 (any non-zero number or true) or "via": "auto". Auto intents
## never end a zero-input fallback, never start Overdrive and never touch the receipt.

const MAX_KEYS := 8


## The normalized intent, or {} when `raw` is junk (not a Dictionary, unknown "k", a bad
## target, item or pad, too many keys).
static func normalize(raw: Variant) -> Dictionary:
	if not (raw is Dictionary) or (raw as Dictionary).size() > MAX_KEYS:
		return {}
	var d: Dictionary = raw
	var k: Variant = d.get("k")
	if k is String and k == SiegeIds.INTENT_BUY_WIRE:
		k = SiegeIds.INTENT_PICK
	if not (k is String) or not SiegeIds.INTENT_KINDS.has(k):
		return {}
	var via := str(d.get("via", SiegeIds.VIA_ACTION)) if d.get("via", "") is String else ""
	if via == "":
		via = SiegeIds.VIA_ACTION
	if not SiegeIds.VIAS.has(via):
		return {}
	var auto := via == SiegeIds.VIA_AUTO or IntentValue.truthy(d.get("auto", 0))
	if auto:
		via = SiegeIds.VIA_AUTO
	var out := {
		"k": k, "to": 0, "item": "", "station": 0, "pad": 0, "lvl": 0, "auto": auto, "via": via
	}
	match str(k):
		SiegeIds.INTENT_ROUTE:
			var to: Variant = d.get("to")
			if to is String and SiegeIds.ROUTE_WORDS.has(to):
				out["to"] = int(SiegeIds.ROUTE_WORDS[to])
			elif IntentValue.whole(to) and SiegeIds.is_station(int(to)):
				out["to"] = int(to)
			else:
				return {}
		SiegeIds.INTENT_PICK:
			var item: Variant = d.get("item")
			if not (item is String) or not SiegeIds.ITEMS.has(item):
				return {}
			out["item"] = item
			if SiegeIds.STATION_ITEMS.has(item):
				var st: Variant = d.get("station")
				if not IntentValue.whole(st) or not SiegeIds.UPGRADABLE.has(int(st)):
					return {}
				out["station"] = int(st)
			if SiegeIds.PAD_ITEMS.has(item):
				var pad: Variant = d.get("pad")
				if not IntentValue.whole(pad) or not SiegeIds.is_pad(int(pad)):
					return {}
				out["pad"] = int(pad)
			var lvl: Variant = d.get("lvl", 0)
			if not IntentValue.whole(lvl) or int(lvl) < 0 or int(lvl) > SiegeIds.MAX_LEVEL:
				return {}
			out["lvl"] = int(lvl)
		SiegeIds.INTENT_OVERDRIVE:
			pass
	return out


## Wire-form helpers for local_intents() and the HUD.
static func route(to: Variant, via: String = SiegeIds.VIA_ACTION) -> Dictionary:
	return {"k": SiegeIds.INTENT_ROUTE, "to": to, "via": via}


## A pick intent; `at` is the station (upgrade) or the pad (scorpion, pad_upgrade), else unused.
static func pick(item: String, at: int = 0, auto: bool = false, lvl: int = 0) -> Dictionary:
	var d := {"k": SiegeIds.INTENT_PICK, "item": item}
	if lvl > 0:
		d["lvl"] = lvl
	if SiegeIds.STATION_ITEMS.has(item):
		d["station"] = at
	if SiegeIds.PAD_ITEMS.has(item):
		d["pad"] = at
	if auto:
		d["auto"] = 1
	return d


## The station or pad a normalized pick names (0 for an item with neither).
static func at_of(it: Dictionary) -> int:
	var item := str(it.get("item", ""))
	if SiegeIds.PAD_ITEMS.has(item):
		return int(it.get("pad", 0))
	if SiegeIds.STATION_ITEMS.has(item):
		return int(it.get("station", 0))
	return 0


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

class_name FishingIntents
extends RefCounted
## The intent schema (brief 2.5, 2.6, 2.8; G0 contract). Clients and the host's own rider send
## them from FishingGame.local_intents() and the HUD; the host normalizes each before the rules
## see it. Intents are never int-converted by the platform: cast here.
##
##   {"k": "spot", "dir": -1 | 1, "via": "action"}     move the highlighted hint left / right
##   {"k": "confirm", "via": "action" | "button" | "surge"}
##       cast the highlighted hint while picking, set the hook during a strike prompt
##   {"k": "summary", "xp": total XP, "rec": {species id: kg x 10}, "cos": [line, canopy, trim, pennant]}
##       sent once from configure on every peer (the automatic summary, brief 2.8)
## Zero input (2.5): only "spot" and "confirm" with via "action" or "button" are deliberate and
## end the lane's Autopilot fallback; a surge and the summary never do, and the host's own
## pedal-scan auto-confirm makes no intent at all. A surge that arrives with a confirm in the same
## tick counts as the surge (the confirm is dropped).

const SPOT := "spot"
const CONFIRM := "confirm"
const SUMMARY := "summary"
const VIA_ACTION := "action"
const VIA_BUTTON := "button"
const VIA_SURGE := "surge"


static func spot(dir: int) -> Dictionary:
	return {"k": SPOT, "dir": signi(dir), "via": VIA_ACTION}


static func confirm(via: String) -> Dictionary:
	return {"k": CONFIRM, "via": via}


static func summary(xp: int, records: Dictionary, cosmetics: Array[int]) -> Dictionary:
	var rec := {}
	for k: Variant in records:
		rec[str(k)] = roundi(float(records[k]) * 10.0)
	return {"k": SUMMARY, "xp": xp, "rec": rec, "cos": cosmetics.duplicate()}


## A clean copy of a raw intent, or {} for junk. Numbers are cast; unknown keys dropped.
static func normalize(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var d: Dictionary = raw
	match str(d.get("k", "")):
		SPOT:
			var dir := signi(int(d.get("dir", 0)))
			return {} if dir == 0 else {"k": SPOT, "dir": dir, "via": VIA_ACTION}
		CONFIRM:
			var via := str(d.get("via", VIA_ACTION))
			if not via in [VIA_ACTION, VIA_BUTTON, VIA_SURGE]:
				via = VIA_ACTION
			return {"k": CONFIRM, "via": via}
		SUMMARY:
			var rec := {}
			var raw_rec: Variant = d.get("rec", {})
			if raw_rec is Dictionary:
				for k: Variant in raw_rec:
					if FishingConst.SPECIES.has(str(k)):
						rec[str(k)] = maxi(int(raw_rec[k]), 0)
			var cos: Array[int] = [0, 0, 0, 0]
			var raw_cos: Variant = d.get("cos", [])
			if raw_cos is Array:
				for i in mini((raw_cos as Array).size(), 4):
					cos[i] = maxi(int(raw_cos[i]), 0)
			return {"k": SUMMARY, "xp": maxi(int(d.get("xp", 0)), 0), "rec": rec, "cos": cos}
	return {}


## True for an intent that ends the zero-input fallback (a button or key action).
static func is_deliberate(intent: Dictionary) -> bool:
	var k := str(intent.get("k", ""))
	var via := str(intent.get("via", ""))
	return (k == SPOT or k == CONFIRM) and (via == VIA_ACTION or via == VIA_BUTTON)


## One tick's raw intents, normalized, junk dropped, and a confirm dropped when a surge confirm
## came in the same tick (brief 2.5: treat it as the surge).
static func normalize_tick(raw: Array) -> Array:
	var out: Array = []
	var has_surge := false
	for r: Variant in raw:
		var n := normalize(r)
		if not n.is_empty():
			out.append(n)
			has_surge = has_surge or (n["k"] == CONFIRM and n["via"] == VIA_SURGE)
	if has_surge:
		out = out.filter(
			func(n: Dictionary) -> bool: return n["k"] != CONFIRM or n["via"] == VIA_SURGE
		)
	return out

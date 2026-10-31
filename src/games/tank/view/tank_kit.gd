class_name TankKit
extends RefCounted
## The content cards of the v2 kit (assets/tank/v2/kit.json). The tank is TankRig's (assets/tank/v3/), the
## enemies TankEnemyKit's (assets/tank/v4/). check() lists what is wrong with a manifest for the tests.

const DIR := "res://assets/tank/v2/"
const MANIFEST := DIR + "kit.json"


static func load_manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


## Every problem of manifest `m` (empty when sound): a missing card file, or enemy rows, which are gone.
static func check(m: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if m.has("enemies"):
		out.append("an enemies section")
	if (m.get("cards", {}) as Dictionary).is_empty():
		out.append("no cards")
	for c: String in m.get("cards", {}):
		var rel := str(m["cards"][c])
		if rel == "" or not ResourceLoader.exists(DIR + rel):
			out.append("missing file %s" % rel)
	return out

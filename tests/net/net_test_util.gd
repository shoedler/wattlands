extends RefCounted
## Shared helpers for tests/net (preloaded, no class_name).


## Strict deep equality: same types (int is not float), same keys (int 2 is not "2"),
## same values, any key order.
static func same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_DICTIONARY:
			var da: Dictionary = a
			var db: Dictionary = b
			if da.size() != db.size():
				return false
			for k: Variant in da.keys():
				if not db.has(k):
					return false
				# Dictionary.has() treats 2 and 2.0 alike; keys must match in type too.
				var found := false
				for kb: Variant in db.keys():
					if typeof(kb) == typeof(k) and kb == k:
						found = true
						break
				if not found or not same(da[k], db[k]):
					return false
			return true
		TYPE_ARRAY:
			var aa: Array = a
			var ab: Array = b
			if aa.size() != ab.size():
				return false
			for i in aa.size():
				if not same(aa[i], ab[i]):
					return false
			return true
		_:
			return a == b


## Where two values first differ (for failure messages).
static func diff(a: Variant, b: Variant, path: String = "") -> String:
	if typeof(a) != typeof(b):
		return (
			"%s: type %s vs %s (%s vs %s)"
			% [path, type_string(typeof(a)), type_string(typeof(b)), str(a), str(b)]
		)
	match typeof(a):
		TYPE_DICTIONARY:
			for k: Variant in (a as Dictionary).keys():
				var match_key: Variant = null
				var ok := false
				for kb: Variant in (b as Dictionary).keys():
					if typeof(kb) == typeof(k) and kb == k:
						match_key = kb
						ok = true
						break
				if not ok:
					return "%s.%s (%s): missing in second" % [path, str(k), type_string(typeof(k))]
				var d := diff(
					(a as Dictionary)[k], (b as Dictionary)[match_key], "%s.%s" % [path, str(k)]
				)
				if d != "":
					return d
			if (a as Dictionary).size() != (b as Dictionary).size():
				return (
					"%s: %d vs %d keys" % [path, (a as Dictionary).size(), (b as Dictionary).size()]
				)
			return ""
		TYPE_ARRAY:
			if (a as Array).size() != (b as Array).size():
				return "%s: %d vs %d items" % [path, (a as Array).size(), (b as Array).size()]
			for i in (a as Array).size():
				var d := diff((a as Array)[i], (b as Array)[i], "%s[%d]" % [path, i])
				if d != "":
					return d
			return ""
		_:
			return "" if a == b else "%s: %s vs %s" % [path, str(a), str(b)]


## JSON.stringify -> JSON.parse_string, the way the brief states the round trip.
static func json_round_trip(d: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	return parsed if parsed is Dictionary else {}


## Poll every session `n` times, in order.
static func pump(sessions: Array, n: int = 4) -> void:
	for _i in n:
		for s: Variant in sessions:
			if s != null and is_instance_valid(s):
				s.call("poll")

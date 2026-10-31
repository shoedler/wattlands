class_name CadenceVoice
extends RefCounted
## One machine's stroke pattern. plan() partitions the revs axis; every event k+f falls in exactly one interval.
## The kit hands it `revs` and `rpm` as plain floats: it never integrates cadence (SPEC_AUDIO 2.1, S1), so
## the stroke and the crank on screen read one number, less the kit's bounded FrameClockLock offset. Pure: no audio
## device, no clock, no RNG.
## Each returned event: {"sound": String, "variant": int, "at_s": float, "db": float, "pitch": float, "pos": float,
## "priority": int}. `variant` is a running count per sound; AudioBank.stream wraps it by the sound's variants.
const LATE_MAX_S := 0.08
var fired: int = 0
var late: int = 0  ## fired with at_s == 0 because the frame overran the horizon
var dropped: int = 0  ## skipped by the LATE_MAX_S hitch cap
var gated: int = 0  ## walked but not fired: `when` or `lead_only` said no

var _events: Array[Dictionary] = []
var _cycle: PackedInt32Array = PackedInt32Array()
var _variant: Dictionary = {}
var _primed: bool = false
var _to: float = 0.0


## Bank-validated events (schema 1.5); sorted by at; each `at` value one internal entry.
func _init(p_events: Array) -> void:
	_cycle.resize(p_events.size())
	for i in p_events.size():
		var src: Dictionary = p_events[i]
		var ats: Array = src.get("at", [])
		for at: Variant in ats:
			var entry := {
				"at": float(at),
				"src": i,
				"order": _events.size(),
				"sound": str(src.get("sound", "")),
				"db": float(src.get("db", 0.0)),
				"db_by": src.get("db_by", []),
				"pitch_by": src.get("pitch_by", []),
				"pitch_table": src.get("pitch_table", []),
				"when": src.get("when", {}),
				"lead_only": bool(src.get("lead_only", false)),
				"priority": int(src.get("priority", 5)),
			}
			_events.append(entry)
	_events.sort_custom(_sooner)


func plan(
	revs: float, rpm: float, horizon_s: float, params: Dictionary, lead: bool
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _primed or revs < _to - 1.0:  # first call, or the source was reset
		_primed = true
		_to = revs
	if rpm <= CrankClock.STOP_RPM:
		_to = maxf(_to, revs)
		return out
	var rate := rpm / 60.0
	var from := _to
	var oldest := revs - rate * LATE_MAX_S
	if from < oldest:  # hitch: a stroke older than 80 ms is dropped; several at at_s 0 would be a burst
		dropped += _count_between(from, oldest)
		from = oldest
	var to := maxf(revs + rate * horizon_s, from)
	for rev in range(floori(from), floori(to) + 1):
		for ev: Dictionary in _events:
			var pos: float = float(rev) + float(ev["at"])
			if pos <= from:
				continue
			if pos > to:
				break
			if not _passes(ev, params, lead):
				continue
			out.append(_emit(ev, pos, maxf((pos - revs) / rate, 0.0), params))
	_to = to
	return out


## How far the walk has reached on the revs axis (tests read it).
func planned_to() -> float:
	return _to


func _passes(ev: Dictionary, params: Dictionary, lead: bool) -> bool:
	if (bool(ev["lead_only"]) and not lead) or not AudioCurve.passes(ev["when"], params):
		gated += 1
		return false
	return true


func _emit(ev: Dictionary, pos: float, at_s: float, params: Dictionary) -> Dictionary:
	fired += 1
	if at_s <= 0.0:
		late += 1
	var sound: String = ev["sound"]
	var variant: int = _variant.get(sound, 0)
	_variant[sound] = variant + 1
	var pitch := AudioCurve.product(ev["pitch_by"], params)
	var table: Array = ev["pitch_table"]
	if not table.is_empty():
		var src: int = ev["src"]
		pitch += float(table[_cycle[src] % table.size()])
		_cycle[src] += 1
	return {
		"sound": sound,
		"variant": variant,
		"at_s": at_s,
		"db": float(ev["db"]) + AudioCurve.sum_db(ev["db_by"], params),
		"pitch": pitch,
		"pos": pos,
		"priority": ev["priority"],
	}


func _count_between(from: float, to: float) -> int:
	var n := 0
	for rev in range(floori(from), floori(to) + 1):
		for ev: Dictionary in _events:
			var pos: float = float(rev) + float(ev["at"])
			if pos > to:
				break
			if pos > from:
				n += 1
	return n


static func _sooner(a: Dictionary, b: Dictionary) -> bool:
	var at_a: float = a["at"]
	var at_b: float = b["at"]
	return at_a < at_b or (at_a == at_b and int(a["order"]) < int(b["order"]))

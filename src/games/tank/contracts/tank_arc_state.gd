class_name TankArcState
extends TankStationState
## The arc generator (v2, brief 2.4 Arc generator; v3: the Lights seat, ERG 65-80%): steady ERG
## tempo under the searchlight load. It lights the searchlights while its rider is in band (v3: the
## gun's full range and normal dispersion; an empty Lights seat leaves only the headlight's range,
## about 260 rules px, and doubles the dispersion). The director turns `duty` into the ERG target
## 65 + 15 x duty % FTP (brief 2.3 pattern 2, in sub-steps); the rules never read that target back.
## Rescue stalls it: the searchlights dim ("Arc generator stalled").
##
## v3: `duty` means the searchlight load (0..1), what the rules builder decides loads the lamps
## (v2 fed it the bow guns' firing share through note_fire; the bow guns are the Secondaries seat's
## now). The fields, the ring and the director pattern are unchanged.

## The load window: `duty` is the share of the last WINDOW_S game seconds the load was on.
const WINDOW_S := 10.0

## [snap] The searchlight load 0..1 (v2: the share of the last 10 s in which the bow guns fired;
## note_fire keeps it as such a share of the last WINDOW_S seconds).
var duty: float = 0.0
## [snap] The searchlights are lit (the Lights rider in band, brief 2.4; v3 the turret searchlight
## the view draws forward and about 11 degrees down).
var lit: bool = false
## [snap] Rescue: searchlights dimmed ("Arc generator stalled").
var stalled: bool = false

# --- Host-only fire history (never serialized: "_" names are skipped by TankRecord) ---------------
## One byte per game tick of the last WINDOW_S seconds (ring indexed by tick mod its size): 1 when
## the load was on during that tick. note_fire() keeps it and `duty` up to date.
var _ring := PackedByteArray()
## Firing ticks in the ring.
var _count: int = 0
## The last tick note_fire() recorded; -1 before the first.
var _last_tick: int = -1


## Host only: records whether the load was on during game tick `tick` and refreshes `duty`. Ticks
## skipped since the last call count as not firing; a tick at or before the last one recorded is
## ignored (each tick counts once). The rules call it once per tick for the arc room.
func note_fire(tick: int, fired: bool) -> void:
	var n := window_ticks()
	if _ring.size() != n:
		_ring.resize(n)
		_ring.fill(0)
		_count = 0
	if _last_tick >= 0 and tick <= _last_tick:
		return
	var gap := tick - _last_tick if _last_tick >= 0 else 1
	if gap >= n:
		_ring.fill(0)
		_count = 0
	else:
		for i in range(1, gap):
			_set_slot(posmod(_last_tick + i, n), 0)
	_set_slot(posmod(tick, n), 1 if fired else 0)
	_last_tick = tick
	duty = clampf(float(_count) / float(n), 0.0, 1.0)


## Clears the fire history (a new segment or a rider change may call it); `duty` drops to 0.
func reset_fire() -> void:
	_ring.fill(0)
	_count = 0
	_last_tick = -1
	duty = 0.0


## The window in ticks (WINDOW_S at Wl.SIM_DT: 200).
static func window_ticks() -> int:
	return roundi(WINDOW_S / Wl.SIM_DT)


func _set_slot(i: int, v: int) -> void:
	_count += v - int(_ring[i])
	_ring[i] = v

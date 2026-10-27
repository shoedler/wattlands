class_name TankArcState
extends TankStationState
## The arc generator (v2, brief 2.4 Arc generator; the Bastion's fourth room): steady ERG tempo
## that lifts while the bow guns fire. It lights the searchlights (halving the main gun's
## dispersion while its rider is in band) and powers the Bastion's bow guns (full rate in band,
## half under band, none while AFK). The director turns `duty` into the ERG target
## 65 + 15 x duty % FTP (brief 2.3 pattern 2, in sub-steps); the rules never read that target back.
## Rescue stalls it: the bow guns stop and the searchlights dim ("Arc generator stalled").

## The arc load's window: `duty` is the share of the last WINDOW_S game seconds the bow guns fired.
const WINDOW_S := 10.0

## [snap] The arc load 0..1: the share of the last 10 s in which the bow guns were firing.
var duty: float = 0.0
## [snap] The searchlights are lit (the arc rider in band, brief 2.4).
var lit: bool = false
## [snap] Rescue: bow guns stopped, searchlights dimmed ("Arc generator stalled").
var stalled: bool = false

# --- Host-only fire history (never serialized: "_" names are skipped by TankRecord) ---------------
## One byte per game tick of the last WINDOW_S seconds (ring indexed by tick mod its size): 1 when
## the bow guns fired on that tick. note_fire() keeps it and `duty` up to date.
var _ring := PackedByteArray()
## Firing ticks in the ring.
var _count: int = 0
## The last tick note_fire() recorded; -1 before the first.
var _last_tick: int = -1


## Host only: records whether the bow guns fired on game tick `tick` and refreshes `duty`. Ticks
## skipped since the last call count as not firing; a tick at or before the last one recorded is
## ignored (each tick counts once). The rules call it once per tick for the Bastion's arc room.
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

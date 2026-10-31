class_name TankRepairState
extends TankStationState
## v4: the Repairs seat: rebuilds hull per joule in band, only below the hull's maximum.

const FIRE_RING := 200

## [snap] Patches riveted so far (one per tanks.json repair.patch_hp rebuilt): the view's press.
var patches: int = 0
## [snap] 0..1 towards the next patch.
var press_t: float = 0.0
## [snap] The share of the last 10 s the hull was below its maximum (TankDirector pattern 10).
var duty: float = 0.0
## [snap] Working now (manned, in band, hull below maximum).
var working: bool = false
var _ring: PackedByteArray = PackedByteArray()
var _sum: int = 0


func note_work(tick: int, busy: bool) -> void:
	if _ring.is_empty():
		_ring.resize(FIRE_RING)
		_ring.fill(0)
	var i := posmod(tick, FIRE_RING)
	_sum += int(busy) - int(_ring[i])
	_ring[i] = int(busy)
	duty = float(_sum) / float(FIRE_RING)

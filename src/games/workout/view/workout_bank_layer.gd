class_name WorkoutBankLayer
extends Node2D
## The earth bank under the road, in flat colours of the time of day (so no LUT), with a light top
## line and seeded earth speckle fixed to the world. The interval strip is drawn on it.

const TOP_BELOW_CONTACT := 32
const BOTTOM := 540
const SPECKLE_PX := 16

var bank: Color = Color.BLACK
var bank_hi: Color = Color.WHITE
var seed_value: int = 0
var _runs: PackedInt32Array = PackedInt32Array()
var _scroll: int = 0


func set_view(runs: PackedInt32Array, scroll: int, p_bank: Color, p_hi: Color) -> void:
	if scroll == _scroll and runs == _runs and p_bank == bank:
		return
	_runs = runs
	_scroll = scroll
	bank = p_bank
	bank_hi = p_hi
	queue_redraw()


func _draw() -> void:
	for i in range(0, _runs.size(), 3):
		var x0 := _runs[i]
		var w := _runs[i + 1] - x0
		var top := _runs[i + 2] + TOP_BELOW_CONTACT
		draw_rect(Rect2(x0, top, w, BOTTOM - top), bank)
		draw_rect(Rect2(x0, top, w, 1), bank_hi)
		_speckle(x0, _runs[i + 1], top)


## Two-pixel flecks, one per SPECKLE_PX of world or none, drawn by the run that holds their column.
func _speckle(x0: int, x1: int, top: int) -> void:
	var fleck := bank.lerp(bank_hi, 0.45)
	var k := floori(float(x0 + _scroll) / float(SPECKLE_PX))
	while k * SPECKLE_PX - _scroll < x1:
		var h := WorkoutPropLayer.bucket_hash(k, seed_value)
		var x := k * SPECKLE_PX - _scroll + (h >> 8) % SPECKLE_PX
		if h % 3 != 0 and x >= x0 and x < x1:
			var y := top + 3 + (h >> 13) % maxi(BOTTOM - top - 5, 1)
			draw_rect(Rect2(x, y, 2, 1), fleck)
		k += 1

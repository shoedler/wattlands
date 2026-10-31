class_name WorkoutBankLayer
extends Node2D
## The earth bank under the road, painted (WorkoutBankTile): the ground follows the road run by run,
## so its bands and ditch run with the slope, and tufts, stones and clods stand on it by a hash of the
## world, so the tile's repeat does not show. The time of day only changes the shader's ramp. The
## interval strip is drawn on it.

const SHADER_PATH := "res://src/games/workout/view/workout_bank.gdshader"
const TOP_BELOW_CONTACT := 32
const BOTTOM := 540
const STAMP_BUCKET_PX := 44
## Stamps keep off the ditch.
const STAMP_BELOW_TOP := 12

var bank: Color = Color.BLACK
var bank_hi: Color = Color.WHITE
var seed_value: int = 0
var _runs: PackedInt32Array = PackedInt32Array()
var _scroll: int = 0
var _shader_material: ShaderMaterial = null


func prepare(p_seed: int) -> WorkoutBankLayer:
	seed_value = p_seed
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = load(SHADER_PATH) as Shader
	material = _shader_material
	return self


## The row's colours: called only when the row changes.
func set_light(p_bank: Color, p_hi: Color, tint: Color) -> void:
	bank = p_bank
	bank_hi = p_hi
	_shader_material.set_shader_parameter("ramp", WorkoutBankTile.ramp(p_bank, p_hi, tint))


func set_view(runs: PackedInt32Array, scroll: int) -> void:
	if scroll == _scroll and runs == _runs:
		return
	_runs = runs
	_scroll = scroll
	queue_redraw()


func _draw() -> void:
	var tex := WorkoutBankTile.texture()
	for i in range(0, _runs.size(), 3):
		_ground(tex, _runs[i], _runs[i + 1], _runs[i + 2] + TOP_BELOW_CONTACT)
	_stamps(tex)


func _ground(tex: Texture2D, x0: int, x1: int, top: int) -> void:
	var h := mini(BOTTOM - top, WorkoutBankTile.GROUND_H)
	var x := x0
	while x < x1:
		var u := posmod(x + _scroll, WorkoutBankTile.W)
		var n := mini(x1 - x, WorkoutBankTile.W - u)
		draw_texture_rect_region(tex, Rect2(x, top, n, h), Rect2(u, 0, n, h))
		x += n


## One stamp per bucket of the world or none, standing on the ground of the run under it.
func _stamps(tex: Texture2D) -> void:
	if _runs.is_empty():
		return
	var cell := WorkoutBankTile.STAMP_CELL
	var run := 0
	var last := _runs[_runs.size() - 2]
	var k := floori(float(_scroll - cell.x) / float(STAMP_BUCKET_PX))
	while k * STAMP_BUCKET_PX - _scroll < last:
		var h := WorkoutPropLayer.bucket_hash(k, seed_value)
		var x := k * STAMP_BUCKET_PX - _scroll + (h >> 8) % STAMP_BUCKET_PX
		k += 1
		if h % 5 < 2:
			continue
		var column := clampi(x + cell.x / 2, _runs[0], last - 1)
		while column >= _runs[run + 1]:
			run += 3
		var top := _runs[run + 2] + TOP_BELOW_CONTACT
		var room := BOTTOM - top - STAMP_BELOW_TOP - cell.y
		if room <= 0:
			continue
		var y := top + STAMP_BELOW_TOP + (h >> 13) % room
		var kind := (h >> 5) % WorkoutBankTile.stamp_count()
		draw_texture_rect_region(
			tex,
			Rect2(x, y, cell.x, cell.y),
			Rect2(kind * cell.x, WorkoutBankTile.GROUND_H, cell.x, cell.y)
		)

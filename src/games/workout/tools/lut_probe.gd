extends SceneTree
## Proves the time-of-day LUT in a real render (needs a renderer, so run it windowed): world/sky.png
## under workout_tod.gdshader at two LUT rows must come out exactly as tod_lut.png says, read from
## the PNG's own bytes. Exit 1 on a difference over 1/255: an import or colour conversion broke the
## indices, and the world art would come out wrong.
##
##   tools/godot.sh --timeout=120 --path . -s src/games/workout/tools/lut_probe.gd

const SKY := "res://assets/workout/world/sky.png"
const LUT := "res://assets/workout/world/tod_lut.png"
const SHADER := "res://src/games/workout/view/workout_tod.gdshader"
const ROWS: Array[int] = [0, 20]
## Probed rows of the sky, top to horizon, so several palette indices are read.
const SAMPLE_Y: Array[int] = [0, 150, 300, 450, 700]
const SAMPLE_X := 17
const TOLERANCE := 1.0 / 255.0 + 1e-4
const SETTLE_FRAMES := 5

var _viewports: Array[SubViewport] = []
var _frames: int = 0


func _initialize() -> void:
	var sky := load(SKY) as Texture2D
	var lut := load(LUT) as Texture2D
	var shader := load(SHADER) as Shader
	if sky == null or lut == null or shader == null:
		_fail("cannot load the sky, the LUT or the shader (import first)")
		return
	for row in ROWS:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("lut", lut)
		material.set_shader_parameter("row", row)
		var sprite := Sprite2D.new()
		sprite.texture = sky
		sprite.centered = false
		sprite.material = material
		var viewport := SubViewport.new()
		viewport.size = Vector2i(sky.get_width(), sky.get_height())
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.canvas_item_default_texture_filter = (
			Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		)
		viewport.add_child(sprite)
		root.add_child(viewport)
		_viewports.append(viewport)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	var sky := _png(SKY)
	var lut := _png(LUT)
	if sky == null or lut == null:
		_fail("cannot decode the PNGs")
		return true
	var rendered: Array[Image] = []
	for viewport in _viewports:
		var img := viewport.get_texture().get_image()
		if img == null:
			_fail("no image (run without --headless)")
			return true
		rendered.append(img)
	var bad := 0
	var differs := false
	for y in SAMPLE_Y:
		var index := sky.get_pixel(SAMPLE_X, y).r8 / 2
		for i in ROWS.size():
			var want := lut.get_pixel(index, ROWS[i])
			var got := rendered[i].get_pixel(SAMPLE_X, y)
			var off := maxf(maxf(absf(want.r - got.r), absf(want.g - got.g)), absf(want.b - got.b))
			print("lut_probe: y %d index %d row %d want %s got %s" % [y, index, ROWS[i], want, got])
			if off > TOLERANCE:
				bad += 1
		if not rendered[0].get_pixel(SAMPLE_X, y).is_equal_approx(
			rendered[1].get_pixel(SAMPLE_X, y)
		):
			differs = true
	if bad > 0:
		_fail("%d probed pixels differ from the LUT by more than 1/255" % bad)
	elif not differs:
		_fail("both LUT rows rendered the same: the row uniform has no effect")
	else:
		print("lut_probe: ok")
		quit(0)
	return true


func _png(path: String) -> Image:
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return img


func _fail(why: String) -> void:
	printerr("lut_probe: %s" % why)
	quit(1)

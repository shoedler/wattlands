class_name PixelViewport
extends SubViewportContainer
## Renders a 2D game's Node2D at its game.json pixel_base with nearest filtering and
## integer scaling to the window, letterboxing the rest (BRIEF 3.9). Owned by world-kits;
## public API frozen after W0. The HUD draws at native resolution above it and maps art-pixel
## Rect2i positions through art_rect_to_screen().
##
## How it works: an internal SubViewport of exactly `pixel_base` renders the game view with
## nearest texture filtering, no mipmaps and 2D pixel snapping. A TextureRect shows that frame
## scaled by a whole number of device pixels per art pixel, centred in this control; the rest
## of the control is filled with `bar_color` (black bars). The layout is recomputed whenever
## the control is resized, the window changes size or `pixel_base` changes, and
## `layout_changed` fires when the result differs.
##
## Units: the window uses `canvas_items` stretch from a 1920 x 1080 base, so one canvas unit
## (what a Control's position and size are measured in) is not always one device pixel. The
## scale is chosen in device pixels, so every art pixel is exactly `integer_scale()` screen
## pixels wide (1280 x 720 window: 2; 1920 x 1080: 3; 2560 x 1440: 4; 1366 x 768: 2 with
## bars). `art_scale()` is the same scale in canvas units (3.0 for all 16:9 windows above).
## Headless runs have no real window and measure in canvas units (device scale 1), so there
## integer_scale() == art_scale().
##
## [codeblock]
## var pv := PixelViewport.new()        # full-rect anchors by default
## pv.pixel_base = Vector2i(640, 360)
## add_child(pv)
## pv.set_game_view(my_view_node2d)
## var r: Rect2 = pv.art_rect_to_screen(Rect2i(427, 24, 212, 80))  # place a HUD Control
## pv.layout_changed.connect(_relayout_hud)
## [/codeblock]
##
## Put screen-space parts (ParallaxStrip, backgrounds) in a view without a Camera2D, or in
## a CanvasLayer inside the view. Everything in the view renders at art resolution, so
## rotated sprites (SpinningPart) keep the chunky pixel look. The SubViewport has 3D
## disabled and ignores GUI input (input reaches games through InputRouter).

## Emitted after the integer scale, the letterbox offset or the image rect changed.
## When that happens without this control changing size (the window was resized at a fixed
## 1920 x 1080 canvas, so only the device scale moved, or pixel_base changed), `resized` is
## emitted as well, so code written against the W0 API, which re-lays out on `resized`
## (HudLayer), follows every layout change.
signal layout_changed

## Art resolution, e.g. Vector2i(640, 360).
var pixel_base: Vector2i = Vector2i(640, 360):
	set(value):
		pixel_base = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		if _sub != null:
			_sub.size = pixel_base
		refresh_layout()

## Color of the letterbox bars around the scaled image.
var bar_color: Color = Color.BLACK:
	set(value):
		bar_color = value
		queue_redraw()

## Clear color of the art canvas, drawn behind the game view inside the pixel viewport.
var background_color: Color = Color.BLACK:
	set(value):
		background_color = value
		if _bg != null:
			_bg.color = value

## Device pixels per canvas unit. 0 (the default) measures it from the window's stretch
## transform (1.0 in headless runs). Tests and nested viewports may set it explicitly.
var screen_scale_override: float = 0.0:
	set(value):
		screen_scale_override = maxf(value, 0.0)
		refresh_layout()

var _sub: SubViewport = null
var _screen: TextureRect = null
var _bg_layer: CanvasLayer = null
var _bg: ColorRect = null
var _view: Node2D = null
var _scale: int = 1
var _art_scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO
var _image_size: Vector2 = Vector2(640, 360)
var _device_scale: float = 1.0
## [size, pixel_base, device scale] of the last layout; getters re-lay out when it is stale
## (a size set outside the tree gets no RESIZED notification).
var _layout_key: Array = []


func _init() -> void:
	stretch = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_screen = TextureRect.new()
	_screen.name = "Screen"
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_screen, false, Node.INTERNAL_MODE_FRONT)

	# The SubViewport is a child of the TextureRect, not of this container, so the
	# container's own drawing (which would show it unscaled at the origin) never sees it.
	_sub = SubViewport.new()
	_sub.name = "Art"
	_sub.size = pixel_base
	_sub.disable_3d = true
	_sub.transparent_bg = false
	_sub.gui_disable_input = true
	_sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sub.canvas_item_default_texture_repeat = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_REPEAT_DISABLED
	_sub.snap_2d_transforms_to_pixel = true
	_sub.snap_2d_vertices_to_pixel = true
	_sub.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	_screen.add_child(_sub)

	_bg_layer = CanvasLayer.new()
	_bg_layer.name = "Background"
	_bg_layer.layer = -128
	_sub.add_child(_bg_layer)
	_bg = ColorRect.new()
	_bg.name = "Clear"
	_bg.color = background_color
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_layer.add_child(_bg)

	_screen.texture = _sub.get_texture()
	set_process(true)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			refresh_layout()
		NOTIFICATION_ENTER_TREE:
			var vp := get_viewport()
			if vp != null and not vp.size_changed.is_connected(refresh_layout):
				vp.size_changed.connect(refresh_layout)
			refresh_layout()
		NOTIFICATION_EXIT_TREE:
			var vp := get_viewport()
			if vp != null and vp.size_changed.is_connected(refresh_layout):
				vp.size_changed.disconnect(refresh_layout)


func _process(_delta: float) -> void:
	# The window's stretch factor can change without this control changing size (a 1280 x 720
	# window maximised to 1920 x 1080 keeps its 1920 x 1080 canvas), so watch it.
	if not is_equal_approx(device_scale(), _device_scale):
		refresh_layout()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), bar_color)


## Put the game's view root inside the pixel viewport (replaces any previous one).
## The previous view is removed and freed (queue_free); null just clears the view. A view
## that already has a parent is moved here.
func set_game_view(view: Node2D) -> void:
	if _view != null and is_instance_valid(_view) and _view != view:
		if _view.get_parent() == _sub:
			_sub.remove_child(_view)
		_view.queue_free()
	_view = view
	if view == null or view.get_parent() == _sub:
		return
	if view.get_parent() != null:
		view.get_parent().remove_child(view)
	_sub.add_child(view)


func game_view() -> Node2D:
	if _view != null and not is_instance_valid(_view):
		_view = null
	return _view


## The current integer scale (>= 1): device pixels per art pixel.
func integer_scale() -> int:
	_ensure_layout()
	return _scale


## Top-left offset of the scaled image inside this control (letterbox), screen pixels.
## Measured in this control's local units (canvas units; equal to screen pixels at 1080p and
## in headless runs), snapped so the image starts on a whole device pixel.
func letterbox_offset() -> Vector2:
	_ensure_layout()
	return _offset


## An art-pixel rect -> screen rect (global coordinates of this control's viewport).
## These are the canvas coordinates a HUD Control in the same viewport (or in a CanvasLayer
## with an identity transform, such as HudLayer) uses for its position and size.
func art_rect_to_screen(r: Rect2i) -> Rect2:
	_ensure_layout()
	var local := Rect2(_offset + Vector2(r.position) * _art_scale, Vector2(r.size) * _art_scale)
	if is_inside_tree():
		return get_global_transform_with_canvas() * local
	return Rect2(position + local.position, local.size)


## The rendered frame as an Image (screenshots).
## Returns the art-resolution frame (pixel_base, RGBA8) with exact pixels; capture_scaled()
## gives the on-screen size. In headless runs (no renderer) and outside the tree it returns
## a pixel_base image filled with background_color.
func capture() -> Image:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return _blank_frame()
	var img: Image = _sub.get_texture().get_image()
	if img == null or img.is_empty():
		return _blank_frame()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


# --- Additions to the W0 API (world-kits) ----------------------------------------------


## Canvas units per art pixel: integer_scale() divided by the device scale. Use it to size
## HUD Controls in art pixels (art_rect_to_screen already applies it).
func art_scale() -> float:
	_ensure_layout()
	return _art_scale


## The scaled image's rect inside this control, local canvas units.
func image_rect() -> Rect2:
	_ensure_layout()
	return Rect2(_offset, _image_size)


## Device pixels per canvas unit used for the layout (see screen_scale_override).
func device_scale() -> float:
	if screen_scale_override > 0.0:
		return screen_scale_override
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return 1.0
	var vp := get_viewport()
	if vp == null:
		return 1.0
	var s: float = absf(vp.get_final_transform().get_scale().x)
	s *= absf(get_global_transform_with_canvas().get_scale().x)
	if is_nan(s) or is_inf(s) or s < 0.0001:
		return 1.0
	return s


## An art-pixel point -> the viewport's canvas coordinates (as art_rect_to_screen).
func art_to_screen(p: Vector2) -> Vector2:
	_ensure_layout()
	var local := _offset + p * _art_scale
	if is_inside_tree():
		return get_global_transform_with_canvas() * local
	return position + local


## The viewport's canvas coordinates -> art pixels (fractional; outside 0..pixel_base when
## the point lies in the bars). For mouse picking in a game view.
func screen_to_art(p: Vector2) -> Vector2:
	_ensure_layout()
	var local := p - position
	if is_inside_tree():
		local = get_global_transform_with_canvas().affine_inverse() * p
	return (local - _offset) / _art_scale


## The internal SubViewport (size pixel_base) that renders the game view.
func subviewport() -> SubViewport:
	return _sub


## The frame scaled by integer_scale() with nearest filtering, as it appears on screen.
func capture_scaled() -> Image:
	_ensure_layout()
	var img := capture()
	if _scale > 1:
		img.resize(img.get_width() * _scale, img.get_height() * _scale, Image.INTERPOLATE_NEAREST)
	return img


## Recompute scale, offset and image rect now (it also runs on every resize).
func refresh_layout() -> void:
	if _screen == null:
		return
	var ds := device_scale()
	var had_layout := not _layout_key.is_empty()
	var prev_size: Vector2 = _layout_key[0] if had_layout else Vector2(-1.0, -1.0)
	_layout_key = [size, pixel_base, ds]
	var l: Dictionary = fit_layout(size, pixel_base, ds)
	var new_scale: int = l["scale"]
	var new_offset: Vector2 = l["offset"]
	var new_size: Vector2 = l["size"]
	var new_art_scale: float = l["art_scale"]
	# The raw measurement, so _process compares like with like (fit_layout sanitizes it).
	_device_scale = ds
	var changed: bool = (
		new_scale != _scale
		or not new_offset.is_equal_approx(_offset)
		or not new_size.is_equal_approx(_image_size)
		or not is_equal_approx(new_art_scale, _art_scale)
	)
	_scale = new_scale
	_offset = new_offset
	_image_size = new_size
	_art_scale = new_art_scale
	_screen.position = _offset
	_screen.size = _image_size
	queue_redraw()
	if changed:
		layout_changed.emit()
		# A size change emits `resized` by itself (Control); any other layout change says so
		# too, for listeners that only know the frozen W0 API.
		if had_layout and is_inside_tree() and prev_size == size:
			resized.emit()


## The largest integer scale (>= 1) at which `base` fits in `available` device pixels.
static func fit_scale(available: Vector2, base: Vector2i) -> int:
	if base.x <= 0 or base.y <= 0:
		return 1
	var fit: float = minf(available.x / float(base.x), available.y / float(base.y))
	return maxi(int(floor(fit + 0.0001)), 1)


## Pure layout math: {"scale": int (device px per art px), "art_scale": float (canvas units
## per art px), "offset": Vector2 (canvas units, top-left of the image in the control),
## "size": Vector2 (canvas units), "device_scale": float}. The image is centred and its
## offset snapped to whole device pixels; an image larger than the control (scale 1 in a
## tiny window) gets a negative offset and is clipped.
static func fit_layout(
	control_size: Vector2, base: Vector2i, screen_scale: float = 1.0
) -> Dictionary:
	var s: float = screen_scale
	if is_nan(s) or is_inf(s) or s < 0.0001:
		s = 1.0
	var b := Vector2(maxi(base.x, 1), maxi(base.y, 1))
	var dev: Vector2 = (control_size * s).round()
	var k: int = fit_scale(dev, Vector2i(b))
	var img_dev: Vector2 = b * float(k)
	var off_dev: Vector2 = ((dev - img_dev) * 0.5).floor()
	return {
		"scale": k,
		"art_scale": float(k) / s,
		"offset": off_dev / s,
		"size": img_dev / s,
		"device_scale": s,
	}


func _ensure_layout() -> void:
	if _layout_key != [size, pixel_base, device_scale()]:
		refresh_layout()


func _blank_frame() -> Image:
	var img := Image.create_empty(pixel_base.x, pixel_base.y, false, Image.FORMAT_RGBA8)
	img.fill(background_color)
	return img

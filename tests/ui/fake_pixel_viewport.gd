extends PixelViewport
## Test double for ui tests: a PixelViewport with a settable scale and letterbox offset, so a
## test can put the HUD at any scale without a window. art_rect_to_screen follows the
## documented contract: offset + rect * scale (the real class also divides by the device scale,
## 1 headless; test_hud_layer.gd covers the real PixelViewport too). It emits the real class's
## `layout_changed` for layout changes without a resize.

const LAYOUT_SIGNAL := &"layout_changed"

var fake_scale: int = 2
var fake_offset: Vector2 = Vector2.ZERO


func integer_scale() -> int:
	return fake_scale


func letterbox_offset() -> Vector2:
	return fake_offset


func art_rect_to_screen(r: Rect2i) -> Rect2:
	return Rect2(fake_offset + Vector2(r.position) * fake_scale, Vector2(r.size) * fake_scale)


func art_to_screen(p: Vector2) -> Vector2:
	return fake_offset + p * fake_scale


func screen_to_art(p: Vector2) -> Vector2:
	return (p - fake_offset) / float(fake_scale)


## Change scale and letterbox as a window resize would, and emit `resized`.
func set_fake(p_scale: int, p_offset: Vector2) -> void:
	fake_scale = p_scale
	fake_offset = p_offset
	resized.emit()


## Change scale and letterbox without a resize (a stretch-factor change) and emit only
## `layout_changed`.
func set_fake_layout(p_scale: int, p_offset: Vector2) -> void:
	fake_scale = p_scale
	fake_offset = p_offset
	layout_changed.emit()

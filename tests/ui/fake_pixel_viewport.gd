extends PixelViewport
## Test double for ui tests: a PixelViewport with a settable integer scale and letterbox
## offset (the world-kits implementation is a stub in this worktree). art_rect_to_screen
## follows the documented contract: offset + rect * scale.

var fake_scale: int = 2
var fake_offset: Vector2 = Vector2.ZERO


func integer_scale() -> int:
	return fake_scale


func letterbox_offset() -> Vector2:
	return fake_offset


func art_rect_to_screen(r: Rect2i) -> Rect2:
	return Rect2(fake_offset + Vector2(r.position) * fake_scale, Vector2(r.size) * fake_scale)


## Change scale and letterbox as a window resize would, and emit `resized`.
func set_fake(p_scale: int, p_offset: Vector2) -> void:
	fake_scale = p_scale
	fake_offset = p_offset
	resized.emit()

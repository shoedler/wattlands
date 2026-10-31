extends GutTest
## HudArtControl: what every game's own HUD Control inherits.


class Probe:
	extends HudArtControl
	var state: bool = true
	var ticked: float = 0.0
	var refreshes: int = 0
	var paints: int = 0

	func tick(delta: float) -> void:
		ticked += delta

	func refresh() -> void:
		refreshes += 1

	func paint() -> void:
		paints += 1

	func has_state() -> bool:
		return state


func _probe() -> Probe:
	var p: Probe = add_child_autofree(Probe.new())
	p.set_process(false)
	return p


func test_it_ignores_the_mouse_fills_its_rect_and_filters_nearest() -> void:
	var c: HudArtControl = autofree(HudArtControl.new())
	assert_eq(c.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(c.size_flags_horizontal, Control.SIZE_FILL)
	assert_eq(c.size_flags_vertical, Control.SIZE_EXPAND_FILL)
	assert_eq(c.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_false(c.clip_contents)
	assert_eq(c.art_rect, Rect2i(0, 0, 960, 540))


func test_place_at_takes_the_rect_and_the_class_name() -> void:
	var c: HudArtControl = autofree(HudArtControl.new())
	c.place_at(Rect2i(4, 5, 60, 70))
	assert_eq(c.art_rect, Rect2i(4, 5, 60, 70))
	assert_eq(String(c.name), "HudArtControl")


func test_set_telemetry_keeps_the_latest() -> void:
	var c: HudArtControl = autofree(HudArtControl.new())
	assert_null(c.tm)
	var t := Telemetry.new()
	c.set_telemetry(t)
	assert_same(c.tm, t)


func test_a_frame_ticks_then_refreshes_only_with_state() -> void:
	var p := _probe()
	p._process(0.25)
	assert_eq(p.ticked, 0.25)
	assert_eq(p.refreshes, 1)
	p.state = false
	p._process(0.25)
	assert_eq(p.ticked, 0.5, "the wall clock runs without a state")
	assert_eq(p.refreshes, 1)


func test_u_is_screen_px_per_art_px_and_the_default_without_a_size() -> void:
	var c: HudArtControl = add_child_autofree(HudArtControl.new())
	c.set_process(false)
	c.art_rect = Rect2i(0, 0, 100, 50)
	assert_eq(c.u(), 2.0, "no size yet")
	c.default_u = 3.0
	assert_eq(c.u(), 3.0, "the default a game sets")
	c.size = Vector2(400, 200)
	assert_eq(c.u(), 4.0)
	c.art_rect = Rect2i(0, 0, 0, 50)
	assert_eq(c.u(), 3.0, "an empty rect has no scale")


func test_it_paints_only_with_state_and_counts_every_draw() -> void:
	var p := _probe()
	p.size = Vector2(200, 100)
	p.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(p.draws, 0)
	assert_eq(p.paints, p.draws)
	p.state = false
	var before := p.paints
	var drew := p.draws
	p.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(p.draws, drew)
	assert_eq(p.paints, before, "no state, nothing painted")


func test_hud_layer_is_null_alone_and_found_through_any_parent() -> void:
	var c: HudArtControl = add_child_autofree(HudArtControl.new())
	c.set_process(false)
	assert_null(c.hud_layer())
	var layer: HudLayer = add_child_autofree(HudLayer.new())
	layer.set_process(false)
	var box := Control.new()
	layer.add_child(box)
	var inner := HudArtControl.new()
	inner.set_process(false)
	box.add_child(inner)
	assert_same(inner.hud_layer(), layer)


func test_canvas_or_is_the_base_without_a_layer_or_a_canvas() -> void:
	var c: HudArtControl = add_child_autofree(HudArtControl.new())
	c.set_process(false)
	assert_eq(c.canvas_or(Vector2i(960, 540)), Vector2i(960, 540))
	var layer: HudLayer = add_child_autofree(HudLayer.new())
	layer.set_process(false)
	var inner := HudArtControl.new()
	inner.set_process(false)
	layer.add_child(inner)
	assert_eq(inner.canvas_or(Vector2i(640, 360)), Vector2i(640, 360), "a layer with no viewport")


func test_canvas_or_reads_the_flex_canvas_of_the_layer() -> void:
	var holder := Control.new()
	holder.size = Vector2(3440, 1440)
	add_child_autofree(holder)
	var pv := PixelViewport.new()
	pv.pixel_base = Vector2i(640, 360)
	pv.flex_min = Vector2i(568, 320)
	holder.add_child(pv)
	pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pv.refresh_layout()
	var layer: HudLayer = add_child_autofree(HudLayer.new())
	layer.screen_size_override = Vector2(1920, 1080)
	layer.sounds = false
	layer.set_process(false)
	layer.build(HudSpec.new(), GameContext.new(), pv)
	var inner := HudArtControl.new()
	inner.set_process(false)
	layer.add_child(inner)
	assert_eq(inner.canvas_or(Vector2i(640, 360)), Vector2i(860, 360))

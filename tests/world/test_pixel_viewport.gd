extends GutTest
## PixelViewport (BRIEF 3.9; OWNERSHIP W2D1, W2D8, HUD2): integer scale and letterbox math
## for several window sizes, art_rect_to_screen mapping, the nearest-filtered SubViewport,
## game view placement, headless capture, and the world2d demo scene.

const BASE := Vector2i(640, 360)


func _make(size: Vector2, base: Vector2i = BASE, screen_scale: float = 0.0) -> PixelViewport:
	var pv := PixelViewport.new()
	pv.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pv.pixel_base = base
	pv.screen_scale_override = screen_scale
	add_child_autofree(pv)
	pv.position = Vector2.ZERO
	pv.size = size
	return pv


# --- Pure layout math ----------------------------------------------------------------------

func test_fit_scale_common_sizes() -> void:
	assert_eq(PixelViewport.fit_scale(Vector2(1920, 1080), BASE), 3)
	assert_eq(PixelViewport.fit_scale(Vector2(1280, 720), BASE), 2)
	assert_eq(PixelViewport.fit_scale(Vector2(2560, 1440), BASE), 4)
	assert_eq(PixelViewport.fit_scale(Vector2(3840, 2160), BASE), 6)
	assert_eq(PixelViewport.fit_scale(Vector2(1366, 768), BASE), 2)
	assert_eq(PixelViewport.fit_scale(Vector2(1920, 1200), BASE), 3)
	assert_eq(PixelViewport.fit_scale(Vector2(1279, 720), BASE), 1, "one pixel short of 2x")


func test_fit_scale_is_at_least_one() -> void:
	assert_eq(PixelViewport.fit_scale(Vector2(320, 200), BASE), 1)
	assert_eq(PixelViewport.fit_scale(Vector2(0, 0), BASE), 1)
	assert_eq(PixelViewport.fit_scale(Vector2(100, 100), Vector2i(0, 0)), 1)


func test_fit_layout_letterbox_16_10() -> void:
	var l := PixelViewport.fit_layout(Vector2(1920, 1200), BASE)
	assert_eq(l["scale"], 3)
	assert_eq(l["offset"], Vector2(0, 60), "bars top and bottom")
	assert_eq(l["size"], Vector2(1920, 1080))
	assert_almost_eq(float(l["art_scale"]), 3.0, 0.0001)


func test_fit_layout_letterbox_both_axes() -> void:
	var l := PixelViewport.fit_layout(Vector2(1366, 768), BASE)
	assert_eq(l["scale"], 2)
	assert_eq(l["size"], Vector2(1280, 720))
	assert_eq(l["offset"], Vector2(43, 24))


func test_fit_layout_device_scale_720p_window() -> void:
	# A 1280 x 720 window shows the 1920 x 1080 canvas at 2/3: two device pixels per art pixel.
	var l := PixelViewport.fit_layout(Vector2(1920, 1080), BASE, 2.0 / 3.0)
	assert_eq(l["scale"], 2)
	assert_almost_eq(float(l["art_scale"]), 3.0, 0.0001)
	assert_almost_eq((l["offset"] as Vector2).length(), 0.0, 0.0001)
	assert_almost_eq((l["size"] as Vector2).x, 1920.0, 0.01)


func test_fit_layout_device_scale_1366_window() -> void:
	# 1366 x 768 with canvas_items stretch: the canvas is about 1920 x 1080 at 768 / 1080.
	var s := 768.0 / 1080.0
	var l := PixelViewport.fit_layout(Vector2(1366.0 / s, 1080), BASE, s)
	assert_eq(l["scale"], 2, "pixel-perfect 2x instead of an uneven 2.13x")
	assert_almost_eq(float(l["art_scale"]), 2.0 / s, 0.0001)
	var off: Vector2 = l["offset"]
	# Offsets land on whole device pixels.
	assert_almost_eq(off.x * s, roundf(off.x * s), 0.001)
	assert_almost_eq(off.y * s, roundf(off.y * s), 0.001)
	assert_almost_eq(off.y * s, 24.0, 0.001)


func test_fit_layout_too_small_is_clipped_not_shrunk() -> void:
	var l := PixelViewport.fit_layout(Vector2(600, 300), BASE)
	assert_eq(l["scale"], 1)
	assert_eq(l["offset"], Vector2(-20, -30))


func test_fit_layout_bad_device_scale_falls_back_to_one() -> void:
	var l := PixelViewport.fit_layout(Vector2(1920, 1080), BASE, 0.0)
	assert_eq(l["scale"], 3)
	l = PixelViewport.fit_layout(Vector2(1920, 1080), BASE, NAN)
	assert_eq(l["scale"], 3)


# --- The node -------------------------------------------------------------------------------

func test_node_scale_and_letterbox_for_sizes() -> void:
	var cases: Array[Array] = [
		[Vector2(1920, 1080), 3, Vector2(0, 0)],
		[Vector2(1280, 720), 2, Vector2(0, 0)],
		[Vector2(1920, 1200), 3, Vector2(0, 60)],
		[Vector2(2560, 1080), 3, Vector2(320, 0)],
		[Vector2(1366, 768), 2, Vector2(43, 24)],
		[Vector2(800, 450), 1, Vector2(80, 45)],
	]
	var pv := _make(Vector2(1920, 1080))
	for c: Array in cases:
		pv.size = c[0]
		assert_eq(pv.integer_scale(), c[1], "scale at %s" % c[0])
		assert_eq(pv.letterbox_offset(), c[2], "offset at %s" % c[0])
		assert_eq(pv.image_rect().size, Vector2(BASE) * float(c[1]))


func test_art_rect_to_screen_scale_3_with_letterbox() -> void:
	var pv := _make(Vector2(1920, 1200))
	# Fishing's 4-lane HUD zone: 213 x 84 art px -> 639 x 252 px at 1080p, 60 px bar on top.
	var r := pv.art_rect_to_screen(Rect2i(427, 24, 213, 84))
	assert_eq(r, Rect2(1281, 132, 639, 252))


func test_art_rect_to_screen_scale_2_with_letterbox() -> void:
	var pv := _make(Vector2(1366, 768))
	var r := pv.art_rect_to_screen(Rect2i(0, 300, 640, 60))
	assert_eq(r, Rect2(43, 624, 1280, 120))


func test_art_rect_to_screen_follows_control_position() -> void:
	var pv := _make(Vector2(1920, 1080))
	pv.position = Vector2(100, 50)
	var r := pv.art_rect_to_screen(Rect2i(10, 10, 1, 1))
	assert_eq(r, Rect2(130, 80, 3, 3))


func test_art_rect_to_screen_with_device_scale() -> void:
	var pv := _make(Vector2(1920, 1080), BASE, 2.0 / 3.0)
	assert_eq(pv.integer_scale(), 2)
	assert_almost_eq(pv.art_scale(), 3.0, 0.0001)
	var r := pv.art_rect_to_screen(Rect2i(100, 100, 10, 10))
	assert_almost_eq(r.position.x, 300.0, 0.01)
	assert_almost_eq(r.size.x, 30.0, 0.01)


func test_art_to_screen_and_back() -> void:
	var pv := _make(Vector2(1366, 768))
	var p := Vector2(123, 45)
	var s := pv.art_to_screen(p)
	assert_eq(s, Vector2(43 + 246, 24 + 90))
	assert_eq(pv.screen_to_art(s), p)


func test_layout_changed_fires_on_resize() -> void:
	var pv := _make(Vector2(1920, 1080))
	watch_signals(pv)
	pv.size = Vector2(1280, 720)
	assert_signal_emitted(pv, "layout_changed")
	assert_eq(pv.integer_scale(), 2)


func test_layout_changed_quiet_when_nothing_changes() -> void:
	var pv := _make(Vector2(1920, 1080))
	watch_signals(pv)
	pv.refresh_layout()
	assert_signal_not_emitted(pv, "layout_changed")
	assert_signal_not_emitted(pv, "resized")


func test_device_scale_change_also_emits_resized_for_the_hud() -> void:
	# A 1920 x 1080 window shrunk to 1600 x 900 keeps the 1920 x 1080 canvas, so the control
	# keeps its size; the HUD (HudLayer re-lays out on `resized`) must still hear about it.
	var pv := _make(Vector2(1920, 1080))
	assert_eq(pv.integer_scale(), 3)
	watch_signals(pv)
	pv.screen_scale_override = 1600.0 / 1920.0
	assert_signal_emitted(pv, "layout_changed")
	assert_signal_emit_count(pv, "resized", 1)
	assert_eq(pv.size, Vector2(1920, 1080), "the control kept its size")
	assert_eq(pv.integer_scale(), 2, "1600 x 900 device px fit 2x")
	assert_almost_eq(pv.art_scale(), 2.4, 0.0001)
	assert_almost_eq(pv.letterbox_offset().x, 192.0, 0.001)
	assert_almost_eq(pv.letterbox_offset().y, 108.0, 0.001)
	var r := pv.art_rect_to_screen(Rect2i(10, 10, 10, 10))
	assert_almost_eq(r.position.x, 192.0 + 24.0, 0.001)
	assert_almost_eq(r.size.y, 24.0, 0.001)


func test_size_change_emits_resized_once() -> void:
	var pv := _make(Vector2(1920, 1080))
	watch_signals(pv)
	pv.size = Vector2(1280, 720)
	assert_signal_emit_count(pv, "resized", 1, "Control's own signal, not a second one")
	assert_signal_emit_count(pv, "layout_changed", 1)


func test_pixel_base_change_emits_resized() -> void:
	var pv := _make(Vector2(1920, 1080))
	watch_signals(pv)
	pv.pixel_base = Vector2i(480, 270)
	assert_signal_emitted(pv, "layout_changed")
	assert_signal_emit_count(pv, "resized", 1)
	assert_eq(pv.integer_scale(), 4)


func test_parallax_strip_in_the_view_covers_the_art_width() -> void:
	var pv := _make(Vector2(1920, 1080), Vector2i(320, 180))
	var view := Node2D.new()
	pv.set_game_view(view)
	var strip := ParallaxStrip.new()
	var img := Image.create_empty(48, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	strip.texture = ImageTexture.create_from_image(img)
	strip.mirror_alternate = true
	view.add_child(strip)
	assert_eq(strip.covered_width(), 320.0, "the art width, not the window's")
	strip.world_x = 1000.0
	var tiles := strip.visible_tiles()
	var last: Dictionary = tiles[tiles.size() - 1]
	assert_true(float(last["x"]) + 48.0 >= 320.0)
	assert_true(float(tiles[0]["x"]) <= 0.0)


func test_pixel_base_change_resizes_subviewport_and_rescales() -> void:
	var pv := _make(Vector2(1920, 1080))
	pv.pixel_base = Vector2i(320, 180)
	assert_eq(pv.subviewport().size, Vector2i(320, 180))
	assert_eq(pv.integer_scale(), 6)


func test_subviewport_renders_pixel_art() -> void:
	var pv := _make(Vector2(1920, 1080))
	var sv := pv.subviewport()
	assert_eq(sv.size, BASE)
	assert_eq(sv.canvas_item_default_texture_filter, Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
	assert_true(sv.snap_2d_transforms_to_pixel)
	assert_true(sv.snap_2d_vertices_to_pixel)
	assert_true(sv.disable_3d)
	var screen := sv.get_parent() as TextureRect
	assert_not_null(screen, "the frame is shown by a TextureRect")
	assert_eq(screen.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(screen.position, pv.letterbox_offset())
	assert_eq(screen.size, pv.image_rect().size)


func test_set_game_view_places_and_replaces() -> void:
	var pv := _make(Vector2(1920, 1080))
	var a := Node2D.new()
	pv.set_game_view(a)
	assert_eq(pv.game_view(), a)
	assert_eq(a.get_parent(), pv.subviewport())
	var b := Node2D.new()
	pv.set_game_view(b)
	assert_eq(pv.game_view(), b)
	assert_eq(b.get_parent(), pv.subviewport())
	assert_null(a.get_parent(), "the old view is removed")
	await wait_process_frames(2)
	assert_false(is_instance_valid(a), "and freed")
	pv.set_game_view(null)
	assert_null(pv.game_view())
	await wait_process_frames(2)
	assert_false(is_instance_valid(b))


func test_game_view_freed_elsewhere_reads_null() -> void:
	var pv := _make(Vector2(1920, 1080))
	var v := Node2D.new()
	pv.set_game_view(v)
	v.free()
	assert_null(pv.game_view())
	var w := Node2D.new()
	pv.set_game_view(w)
	assert_eq(pv.game_view(), w, "a new view after the old one was freed")


func test_set_game_view_moves_a_parented_view() -> void:
	var pv := _make(Vector2(1920, 1080))
	var holder := Node.new()
	add_child_autofree(holder)
	var v := Node2D.new()
	holder.add_child(v)
	pv.set_game_view(v)
	assert_eq(v.get_parent(), pv.subviewport())
	pv.set_game_view(v)
	assert_eq(pv.game_view(), v, "setting the same view twice keeps it")


func test_capture_headless_returns_base_sized_frame() -> void:
	var pv := _make(Vector2(1920, 1080))
	pv.background_color = Color(0.2, 0.4, 0.6)
	var img := pv.capture()
	assert_not_null(img)
	assert_eq(img.get_size(), BASE)
	assert_eq(img.get_format(), Image.FORMAT_RGBA8)
	var px := img.get_pixel(5, 5)
	assert_almost_eq(px.b, 0.6, 0.01)
	var big := pv.capture_scaled()
	assert_eq(big.get_size(), BASE * 3)


func test_layout_outside_the_tree() -> void:
	# Outside the tree a Control gets no RESIZED notification; the getters re-lay out.
	var pv: PixelViewport = autofree(PixelViewport.new())
	pv.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pv.size = Vector2(1920, 1200)
	assert_eq(pv.integer_scale(), 3)
	assert_eq(pv.letterbox_offset(), Vector2(0, 60))
	assert_eq(pv.art_rect_to_screen(Rect2i(0, 0, 10, 10)), Rect2(0, 60, 30, 30))


func test_full_rect_child_follows_its_parent() -> void:
	var parent := Control.new()
	parent.size = Vector2(1366, 768)
	add_child_autofree(parent)
	var pv := PixelViewport.new()
	parent.add_child(pv)
	await wait_process_frames(2)
	assert_eq(pv.size, Vector2(1366, 768))
	assert_eq(pv.integer_scale(), 2)
	assert_eq(pv.letterbox_offset(), Vector2(43, 24))


func test_capture_outside_tree() -> void:
	var pv: PixelViewport = autofree(PixelViewport.new())
	var img := pv.capture()
	assert_eq(img.get_size(), BASE)


func test_device_scale_headless_is_one() -> void:
	var pv := _make(Vector2(1920, 1080))
	assert_eq(pv.device_scale(), 1.0)
	pv.screen_scale_override = 1.5
	assert_eq(pv.device_scale(), 1.5)
	assert_eq(pv.integer_scale(), 4, "2880 x 1620 device px fit 4x")


func test_defaults_full_rect_and_mouse_ignore() -> void:
	var pv: PixelViewport = autofree(PixelViewport.new())
	assert_eq(pv.anchor_right, 1.0)
	assert_eq(pv.anchor_bottom, 1.0)
	assert_eq(pv.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(pv.pixel_base, BASE)


# --- Demo scene (W2D8) --------------------------------------------------------------------

func test_demo_scene_runs_headless() -> void:
	var scene: PackedScene = load("res://addons/wattlands/world2d/demo.tscn")
	assert_not_null(scene)
	var demo: Control = scene.instantiate()
	add_child_autofree(demo)
	await wait_process_frames(6)
	var pv: PixelViewport = demo.get("pixel_viewport")
	assert_not_null(pv)
	assert_eq(pv.pixel_base, BASE)
	assert_not_null(pv.game_view())
	var strips: Array = demo.get("strips")
	assert_gt(strips.size(), 4, "parallax strips")
	var mirrored := 0
	for s: ParallaxStrip in strips:
		if s.mirror_alternate:
			mirrored += 1
	assert_gt(mirrored, 0, "at least one mirrored strip")
	var gears: Array = demo.get("gears")
	assert_gt(gears.size(), 1)
	var dirs := {}
	for g: SpinningPart in gears:
		dirs[signf(g.ratio)] = true
	assert_true(dirs.has(1.0) and dirs.has(-1.0), "gears turn both ways")
	assert_not_null(demo.get("piston"))
	assert_not_null(demo.get("chain"))
	var boats: Array = demo.get("boats")
	assert_eq(boats.size(), 4)
	for b: Sprite2D in boats:
		assert_true(b.material is ShaderMaterial, "palette-swapped boat")
	var fish: Array = demo.get("fish")
	for f: Sprite2D in fish:
		assert_true(f.material is ShaderMaterial, "wobbling fish")
	assert_ne((demo.get("caption") as Label).text, "")
	assert_false((demo.get("caption") as Label).text.begins_with("WORLD_"), "the caption is translated")


func test_demo_scene_animates_over_time() -> void:
	var scene: PackedScene = load("res://addons/wattlands/world2d/demo.tscn")
	var demo: Control = scene.instantiate()
	add_child_autofree(demo)
	await wait_process_frames(4)
	var strips: Array = demo.get("strips")
	var gears: Array = demo.get("gears")
	var chain: ScrollingChain = demo.get("chain")
	var fish: Array = demo.get("fish")
	var fish_x: float = (fish[0] as Sprite2D).position.x
	var spun := 0.0
	for g: SpinningPart in gears:
		spun += absf(g.revolutions())
	var chain_before := chain.travel()
	await wait_process_frames(8)
	# Headless frames are very short, so also step half a second explicitly: the demo sets
	# the drive signal and moves the fish, each part advances itself.
	demo.call("_process", 0.5)
	for g: SpinningPart in gears:
		g.tick(0.5)
	chain.tick(0.5)
	assert_gt((strips[0] as ParallaxStrip).world_x, 0.0, "the backdrop scrolls")
	var spun_after := 0.0
	for g: SpinningPart in gears:
		spun_after += absf(g.revolutions())
	assert_gt(spun_after, spun, "gears turn")
	assert_ne(chain.travel(), chain_before, "the chain scrolls")
	assert_lt((fish[0] as Sprite2D).position.x, fish_x, "fish swim left")

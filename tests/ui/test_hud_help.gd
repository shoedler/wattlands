extends GutTest
## The help overlay (HudSpec.help, v0.3.0): HudLayer resolves and places the entries, shows a
## toast when a game has none, toggles, hides itself after 20 s, follows the palette, draws
## pixel arrows on the art grid for 2D games with grid_px; HelpSeen remembers the games.

const FakePV := preload("res://tests/ui/fake_pixel_viewport.gd")
const LOCAL := 1

var _ctx: GameContext = null
var _hud: HudLayer = null
var _dir: String = ""


func before_each() -> void:
	_ctx = GameContext.new()
	_ctx.events = autofree(WlEventBus.new())
	_ctx.local_peer = LOCAL
	_ctx.strings = GameStrings.new()
	var me := PlayerSlot.new()
	me.peer_id = LOCAL
	me.apply_look(0)
	_ctx.players = [me]
	_hud = HudLayer.new()
	_hud.screen_size_override = Vector2(1920, 1080)
	_hud.sounds = false
	_hud.wkg_weight_kg = 0.0
	add_child_autofree(_hud)
	_hud.set_process(false)


func after_each() -> void:
	if not _dir.is_empty():
		for f in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(f))
		DirAccess.remove_absolute(_dir)
		_dir = ""


func _spec(help: Array[Dictionary], palette: Dictionary = {}) -> HudSpec:
	var spec := HudSpec.new().add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
	spec.help = help
	spec.palette = palette
	return spec


func _two_entries() -> Array[Dictionary]:
	return [
		{"text": "UI_HELP_TITLE", "at": Vector2(0.5, 0.5)},
		{"text": "Pedal hard here", "at": Vector2(0.25, 0.75), "arrow_to": Vector2(0.1, 0.9)},
	]


func test_entries_resolve_and_sit_where_asked() -> void:
	_hud.build(_spec(_two_entries()), _ctx)
	var h := _hud.help_overlay()
	assert_true(_hud.has_help())
	assert_false(_hud.help_visible(), "closed until asked")
	assert_true(_hud.show_help())
	assert_true(_hud.help_visible())
	assert_eq(h.texts(), [tr("UI_HELP_TITLE"), "Pedal hard here"], "keys resolve, text stays")
	var p0 := h.panel(0)
	var c0 := p0.position + p0.size * 0.5
	assert_almost_eq(c0.x, 960.0, 1.0)
	assert_almost_eq(c0.y, 540.0, 1.0)
	assert_eq(h.arrow_of(0), [] as Array[Vector2], "no arrow_to, no arrow")
	var a := h.arrow_of(1)
	assert_eq(a.size(), 2)
	assert_almost_eq(a[1].x, 192.0, 1e-3)
	assert_almost_eq(a[1].y, 972.0, 1e-3)
	var r := Rect2(h.panel(1).position, h.panel(1).size)
	assert_true(r.grow(1.0).has_point(a[0]), "the arrow starts on the panel's edge")
	assert_false(r.grow(-1.0).has_point(a[0]))
	assert_false(h.pixel_arrows(), "no PixelViewport: a screen-space arrow")


func test_it_draws_above_the_hud_below_the_pause_badge() -> void:
	_hud.build(_spec(_two_entries()), _ctx)
	_hud.show_help()
	var root := _hud.root()
	var kids := root.get_children()
	assert_eq(kids[kids.size() - 1], _hud.pause_badge())
	assert_eq(kids[kids.size() - 2], _hud.help_overlay())


func test_panels_stay_on_screen() -> void:
	var help: Array[Dictionary] = [{"text": "Corner", "at": Vector2(1.0, 1.0)}]
	_hud.build(_spec(help), _ctx)
	_hud.show_help()
	var p := _hud.help_overlay().panel(0)
	assert_lte(p.position.x + p.size.x, 1920.0 - HudHelp.MARGIN + 0.5)
	assert_lte(p.position.y + p.size.y, 1080.0 - HudHelp.MARGIN + 0.5)


func test_no_help_shows_a_toast() -> void:
	_hud.build(_spec([]), _ctx)
	assert_false(_hud.has_help())
	assert_false(_hud.show_help())
	assert_false(_hud.help_visible())
	assert_eq(_hud.toasts().texts(), [tr("UI_HELP_NONE")] as Array[String])
	assert_ne(tr("UI_HELP_NONE"), "UI_HELP_NONE", "the string exists")
	_hud.toggle_help()
	assert_eq(_hud.toasts().texts().size(), 2, "F1 again: the toast again")
	assert_false(_hud.help_visible())


func test_toggle_and_hide_after_20_s() -> void:
	_hud.build(_spec(_two_entries()), _ctx)
	_hud.toggle_help()
	assert_true(_hud.help_visible())
	_hud.toggle_help()
	assert_false(_hud.help_visible())
	_hud.show_help()
	for i in 199:
		_hud.tick(0.1)
	assert_true(_hud.help_visible(), "19.9 s")
	_hud.tick(0.1)
	assert_false(_hud.help_visible(), "gone at 20 s")
	_hud.show_help()
	_hud.hide_help()
	assert_false(_hud.help_visible())


func test_palette_styles_panels_and_text() -> void:
	var pal := {
		"panel": Color(0.2, 0.1, 0.0),
		"panel_border": Color(0.9, 0.8, 0.1),
		"text": Color(0.1, 0.9, 0.3),
	}
	_hud.build(_spec(_two_entries(), pal), _ctx)
	_hud.show_help()
	var p := _hud.help_overlay().panel(0)
	var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(sb.bg_color, pal["panel"])
	assert_eq(sb.border_color, pal["panel_border"])
	var l := p.get_child(0) as Label
	assert_eq(l.label_settings.font_color, pal["text"])
	assert_eq(_hud.help_overlay().title_label().label_settings.font_color, pal["text"])


func test_bad_entries_are_skipped() -> void:
	var help: Array[Dictionary] = [
		{"text": "", "at": Vector2(0.5, 0.5)},
		{"text": "no position"},
		{"text": "bad arrow", "at": Vector2(0.5, 0.5), "arrow_to": "there"},
		{"text": "fine", "at": Vector2i(1, 0)},
	]
	_hud.build(_spec(help), _ctx)
	assert_eq(_hud.help_overlay().texts(), ["fine"] as Array[String])


func test_pixel_arrows_on_the_art_grid() -> void:
	var pv: PixelViewport = FakePV.new()
	pv.set("fake_scale", 3)
	pv.set("fake_offset", Vector2(0, 0))
	add_child_autofree(pv)
	var help: Array[Dictionary] = [
		{"text": "Rod tip", "at": Vector2(200, 60), "arrow_to": Vector2(420, 300)},
	]
	_hud.build(_spec(help, {"grid_px": 3, "accent": Color.YELLOW}), _ctx, pv)
	_hud.show_help()
	var h := _hud.help_overlay()
	assert_true(h.pixel_arrows())
	var p := h.panel(0)
	assert_almost_eq(fposmod(p.position.x, 3.0), 0.0, 1e-3, "panels on whole art pixels")
	assert_almost_eq(fposmod(p.position.y, 3.0), 0.0, 1e-3)
	var px := h.arrow_pixels(0)
	assert_has(px, Vector2i(420, 300), "the arrow ends on arrow_to")
	var line := HudHelp.line_pixels(px[0], Vector2i(420, 300))
	for i in range(1, line.size()):
		var d := line[i] - line[i - 1]
		assert_true(absi(d.x) <= 1 and absi(d.y) <= 1, "one art pixel at a time")
	assert_gt(px.size(), line.size(), "plus a head")


func test_line_pixels() -> void:
	assert_eq(
		HudHelp.line_pixels(Vector2i(0, 0), Vector2i(3, 1)),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 1), Vector2i(3, 1)] as Array[Vector2i]
	)
	assert_eq(
		HudHelp.line_pixels(Vector2i(2, 2), Vector2i(2, 0)),
		[Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0)] as Array[Vector2i]
	)
	assert_eq(
		HudHelp.line_pixels(Vector2i(5, 5), Vector2i(5, 5)), [Vector2i(5, 5)] as Array[Vector2i]
	)


func test_help_seen_per_profile_and_game() -> void:
	_dir = Paths.make_temp_dir("wl_help_seen")
	var path := _dir.path_join("help_seen.json")
	assert_false(HelpSeen.has("fishing", path))
	assert_true(HelpSeen.mark("fishing", path))
	assert_true(HelpSeen.has("fishing", path))
	assert_false(HelpSeen.has("tank", path), "per game")
	assert_true(HelpSeen.mark("fishing", path), "marking twice is fine")
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq((d as Dictionary)["games"], ["fishing"])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	assert_false(HelpSeen.has("fishing", path), "an unreadable file starts fresh")
	Paths.set_override(_dir)
	assert_eq(Paths.help_seen_path(), path, "the profile's user dir")
	Paths.set_override("")


func test_art_map_moves_help_points() -> void:
	var pv: PixelViewport = FakePV.new()
	pv.set("fake_scale", 2)
	add_child_autofree(pv)
	var help: Array[Dictionary] = [
		{"text": "Edge", "at": Vector2(100, 50), "arrow_to": Vector2(300, 200)},
	]
	_hud.build(_spec(help), _ctx, pv)
	var h := _hud.help_overlay()
	h.art_map = func(p: Vector2) -> Vector2: return p + Vector2(40, 0)
	_hud.show_help()
	assert_eq(h.to_screen(Vector2(100, 50)), Vector2(280, 100), "a flex layout's anchoring")
	assert_eq(h.arrow_of(0)[1], Vector2(680, 400))


## Flex mode (pixel_flex): HudLayer anchors help points like its HUD rects, so a point inside a
## rect moves with that rect and any other point with the art pixel under it.
func test_help_points_follow_a_flex_layout() -> void:
	var holder := Control.new()
	holder.size = Vector2(3440, 1440)
	add_child_autofree(holder)
	var pv := PixelViewport.new()
	pv.pixel_base = Vector2i(640, 360)
	pv.flex_min = Vector2i(568, 320)
	holder.add_child(pv)
	pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pv.refresh_layout()
	assert_eq(pv.art_size(), Vector2i(860, 360), "220 art px wider than pixel_base")
	var spec := _spec(
		[
			{"text": "Left", "at": Vector2(100, 50)},
			{"text": "Right", "at": Vector2(500, 50), "arrow_to": Vector2(600, 20)},
			{"text": "Middle", "at": Vector2(200, 200), "arrow_to": Vector2(300, 320)},
		]
	)
	spec.add_control(Control.new(), Rect2i(270, 300, 100, 40))
	_hud.build(spec, _ctx, pv)
	var h := _hud.help_overlay()
	assert_true(h.art_map.is_valid(), "HudLayer sets the anchoring")
	assert_eq(h.art_point(Vector2(100, 50)), Vector2(100, 50), "left half stays")
	assert_eq(h.art_point(Vector2(500, 50)), Vector2(720, 50), "right half follows the edge")
	assert_eq(
		h.art_point(Vector2(300, 320)), Vector2(410, 320), "inside a centred rect: moves with it"
	)
	assert_eq(h.art_point(Vector2(300, 100)), Vector2(300, 100), "the same x outside it stays")
	_hud.show_help()
	_hud.relayout()
	assert_eq(h.to_screen(Vector2(500, 50)), pv.art_to_screen(Vector2(720, 50)))
	assert_eq(h.arrow_of(2)[1], pv.art_to_screen(Vector2(410, 320)))


func test_help_points_stay_without_flex() -> void:
	var pv: FakePV = add_child_autofree(FakePV.new())
	pv.set("fake_scale", 2)
	_hud.build(_spec([{"text": "Right", "at": Vector2(500, 50)}]), _ctx, pv)
	assert_eq(_hud.help_art_point(Vector2(500, 50)), Vector2(500, 50))
	_hud.build(_spec([]), _ctx)
	assert_eq(_hud.help_art_point(Vector2(500, 50)), Vector2(500, 50), "no PixelViewport")

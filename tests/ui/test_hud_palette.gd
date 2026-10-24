extends GutTest
## HudSpec.palette: a game recolors the neutral chrome of the HUD kit (panels, text, bars,
## toasts, the game banner); the default palette is the kit look, and safety and warning colors
## never follow it.

const PANEL := Color("#1c4d65d9")
const TEXT := Color("#ebf2e7")
const DIM := Color("#b6d7cf")
const BAR_BG := Color("#2c6778")
const BAR_FG := Color("#90c1c1")
const BANNER_BG := Color("#1c4d65e6")

var _palette: HudPalette = null


func before_each() -> void:
	_palette = (
		HudPalette
		. from_dict(
			{
				"panel": PANEL,
				"panel_border": BAR_BG,
				"text": TEXT,
				"text_dim": DIM,
				"bar_bg": BAR_BG,
				"bar_fg": BAR_FG,
				"accent": Color("#c98a5e"),
				"banner_bg": BANNER_BG,
				"banner_text": TEXT,
			}
		)
	)


func _panel_of(w: Control) -> StyleBoxFlat:
	return w.get_theme_stylebox("panel") as StyleBoxFlat


func test_default_palette_leaves_the_kit_look() -> void:
	var plain := autofree(HudWbal.new()) as HudWbal
	var same := autofree(HudWbal.new()) as HudWbal
	same.set_palette(HudPalette.from_dict({}))
	assert_eq(_panel_of(same).bg_color, _panel_of(plain).bg_color)
	assert_eq(_panel_of(plain).bg_color, Color(0.055, 0.067, 0.086, 0.74))
	assert_eq(_panel_of(same).border_color, Color(0.227, 0.271, 0.322, 0.9))
	assert_eq(_panel_of(same).content_margin_left, 12.0)
	assert_eq(same.pct_label().label_settings.font_color, WlTheme.TEXT)
	assert_eq(same.bar().fill_color, WlTheme.ACCENT)
	assert_true(HudSpec.new().palette.is_empty())
	assert_true(HudPalette.new().is_default())


func test_palette_recolors_gauge_panel_label_and_bar() -> void:
	var g := autofree(HudPowerGauge.new()) as HudPowerGauge
	g.set_palette(_palette)
	assert_eq(_panel_of(g).bg_color, PANEL)
	assert_eq(_panel_of(g).border_color, BAR_BG)
	assert_eq(g._unit.label_settings.font_color, DIM)
	assert_eq(g.bar().palette.pick("bar_bg", Color.BLACK), BAR_BG)
	assert_eq(g.bar().fill_color, BAR_FG)
	var t := Telemetry.new()
	t.power_w = 150.0
	g.set_telemetry(t)
	assert_eq(g._watts.label_settings.font_color, TEXT)


func test_missing_keys_keep_the_default_and_panel_false_stays_empty() -> void:
	var w := autofree(HudWbal.new()) as HudWbal
	w.set_palette(HudPalette.from_dict({"text": TEXT}))
	assert_eq(_panel_of(w).bg_color, Color(0.055, 0.067, 0.086, 0.74))
	assert_eq(w.pct_label().label_settings.font_color, TEXT)
	var bare := autofree(HudWbal.new()) as HudWbal
	bare.configure({"panel": false})
	bare.set_palette(_palette)
	assert_true(bare.get_theme_stylebox("panel") is StyleBoxEmpty)


func test_warning_colors_ignore_the_palette() -> void:
	var w := autofree(HudWbal.new()) as HudWbal
	w.set_palette(_palette)
	w.set_wbal(w.wprime_j * 0.1)
	assert_true(w.is_low())
	assert_eq(w.bar().fill_color, WlTheme.WARN)
	assert_eq(w.pct_label().label_settings.font_color, WlTheme.WARN)
	w.set_wbal(w.wprime_j)
	assert_eq(w.bar().fill_color, BAR_FG)
	var b := autofree(HudBanner.new()) as HudBanner
	b.set_palette(_palette)
	b.set_safety(false, true)
	var rescue := b._safety_panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(rescue.bg_color, Color(WlTheme.WARN, 0.95))
	b.set_trainer_notice("x")
	var trainer := b._trainer_panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(trainer.border_color, WlTheme.WARN)
	b.set_safety(true, false)
	var warm := b._safety_panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(warm.bg_color, Color(WlTheme.WARMUP, 0.95))


func test_game_banner_and_toasts_follow_the_palette() -> void:
	var b := autofree(HudBanner.new()) as HudBanner
	b.set_palette(_palette)
	b.show_game_banner("hi")
	var sb := b._game_panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(sb.bg_color, BANNER_BG)
	assert_eq(b.game_label().label_settings.font_color, TEXT)
	var t := autofree(HudToasts.new()) as HudToasts
	t.push("early")
	t.set_palette(_palette)
	t.push("late")
	for it in t._items:
		assert_eq((it["panel"].get_theme_stylebox("panel") as StyleBoxFlat).bg_color, BANNER_BG)
		assert_eq((it["label"] as Label).label_settings.font_color, TEXT)


func test_layer_passes_the_spec_palette_to_every_widget() -> void:
	var hud := HudLayer.new()
	hud.screen_size_override = Vector2(1920, 1080)
	hud.sounds = false
	add_child_autofree(hud)
	hud.set_process(false)
	var spec := (
		HudSpec
		. new()
		. add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.TIMELINE, HudSpec.TOP_LEFT)
		. add(HudSpec.TEAMMATES, HudSpec.BOTTOM)
	)
	spec.palette = {"panel": PANEL, "text": TEXT, "banner_bg": BANNER_BG}
	hud.build(spec, null)
	assert_eq(_panel_of(hud.widget(HudSpec.POWER_GAUGE)).bg_color, PANEL)
	assert_eq(_panel_of(hud.widget(HudSpec.TIMELINE)).bg_color, PANEL)
	assert_true(hud.widget(HudSpec.TEAMMATES).get_theme_stylebox("panel") is StyleBoxEmpty)
	assert_eq(hud.toasts().palette.pick("banner_bg", Color.BLACK), BANNER_BG)
	hud.build(HudSpec.new(), null)
	assert_eq(_panel_of(hud.widget(HudSpec.POWER_GAUGE)).bg_color, Color(0.055, 0.067, 0.086, 0.74))
	assert_true(hud.toasts().palette.is_default())


func test_default_palette_keeps_the_kit_type_and_corners() -> void:
	var g := autofree(HudPowerGauge.new()) as HudPowerGauge
	g.set_palette(HudPalette.from_dict({}))
	assert_gt(g._unit.label_settings.outline_size, 0)
	assert_eq(g._unit.label_settings.font, WlTheme.font())
	assert_eq(_panel_of(g).corner_radius_top_left, WlTheme.CORNER_PX)
	var plain := autofree(HudPowerGauge.new()) as HudPowerGauge
	assert_eq(g._watts.label_settings.font_size, plain._watts.label_settings.font_size)


func test_style_keys_set_the_font_sizes_outline_and_corners() -> void:
	var font: Font = ThemeDB.fallback_font
	var p := HudPalette.from_dict(
		{"font": font, "font_scale_px": 9, "corner_radius": 0, "text_outline": false}
	)
	var g := autofree(HudPowerGauge.new()) as HudPowerGauge
	g.set_palette(p)
	for l: Label in [g._unit, g._watts]:
		assert_eq(l.label_settings.font, font)
		assert_eq(l.label_settings.font_size % 9, 0, "%s snaps to the font's cell" % l.name)
		assert_eq(l.label_settings.outline_size, 0)
	assert_gte(g._watts.label_settings.font_size, WlTheme.KEY_NUMBER_MIN_PX, "key numbers stay big")
	assert_eq(_panel_of(g).corner_radius_top_left, 0)
	assert_false(_panel_of(g).anti_aliasing)
	var t := autofree(HudToasts.new()) as HudToasts
	t.set_palette(p)
	t.push("hi")
	var ls := (t._items[0]["label"] as Label).label_settings
	assert_eq(ls.font, font)
	assert_eq(ls.outline_size, 0)
	assert_eq(HudPalette.from_dict({"font": 3, "corner_radius": -1}).style.size(), 0, "bad types")


func test_band_glow_and_glow_text_keys_recolor_the_in_band_look() -> void:
	var p := HudPalette.from_dict(
		{"band": BAR_BG, "glow": BAR_FG, "glow_text": TEXT, "bar_fg": BAR_FG, "bar_bg": BAR_BG}
	)
	var c := autofree(HudCadence.new()) as HudCadence
	c.set_palette(p)
	c.set_cadence_band(80.0, 100.0)
	var t := Telemetry.new()
	t.cadence_rpm = 90.0
	c.set_telemetry(t)
	assert_true(c.in_band())
	assert_eq(c.rpm_label().label_settings.font_color, TEXT)
	assert_eq(c.bar().palette.pick("band", Color.BLACK), BAR_BG)
	var plain := autofree(HudCadence.new()) as HudCadence
	plain.set_cadence_band(80.0, 100.0)
	plain.set_telemetry(t)
	assert_eq(plain.rpm_label().label_settings.font_color, WlTheme.GLOW, "the kit glow by default")


func test_size_and_grid_keys_set_one_scale_pixel_gaps_and_gear_cells() -> void:
	var p := HudPalette.from_dict(
		{"font": ThemeDB.fallback_font, "text_px": 27, "key_px": 54, "grid_px": 3}
	)
	var g := autofree(HudPowerGauge.new()) as HudPowerGauge
	g.set_palette(p)
	g.fit_to(Vector2(300, 102))
	for l: Label in [g._unit, g._pct, g._target]:
		assert_eq(l.label_settings.font_size, 27, "%s takes text_px at any scale" % l.name)
	assert_eq(g._watts.label_settings.font_size, 54, "key numbers take key_px")
	assert_eq(_panel_of(g).content_margin_left, 9.0, "panels pad three game pixels")
	assert_eq(_panel_of(g).content_margin_bottom, 9.0)
	var top := g._content.get_child(0) as BoxContainer
	assert_eq(top.get_theme_constant("separation"), 9, "a 10 px gap snaps to 3 game pixels")
	assert_eq(g._content.get_theme_constant("separation"), 3, "a 4 px gap snaps to one")
	var small := HudPalette.from_dict({"key_px": 30})
	var g2 := autofree(HudPowerGauge.new()) as HudPowerGauge
	g2.set_palette(small)
	assert_eq(g2._watts.label_settings.font_size, WlTheme.KEY_NUMBER_MIN_PX, "never under 48 px")
	var gear := autofree(HudGear.new()) as HudGear
	gear.set_palette(p)
	var cells_w := gear._bar.get_combined_minimum_size().x
	assert_eq(cells_w, float((2 * HudGear.GEARS - 1) * 3), "one cell per gear, one pixel apart")
	var bad := HudPalette.from_dict({"text_px": 0, "key_px": "54", "grid_px": 1.5})
	assert_eq(bad.style.size(), 0, "size keys need whole numbers above 0")


func test_without_grid_px_the_kit_gaps_margins_and_sizes_stay() -> void:
	var g := autofree(HudPowerGauge.new()) as HudPowerGauge
	var plain := autofree(HudPowerGauge.new()) as HudPowerGauge
	var top := g._content.get_child(0) as BoxContainer
	assert_eq(top.get_theme_constant("separation"), 10)
	g.set_palette(HudPalette.from_dict({"grid_px": 3}))
	assert_eq(top.get_theme_constant("separation"), 9)
	g.set_palette(HudPalette.from_dict({}))
	assert_eq(top.get_theme_constant("separation"), 10, "a palette without grid_px restores it")
	assert_eq(g._content.get_theme_constant("separation"), 4)
	assert_eq(_panel_of(g).content_margin_left, _panel_of(plain).content_margin_left)
	assert_eq(g._watts.label_settings.font_size, plain._watts.label_settings.font_size)
	assert_eq(g._unit.label_settings.font_size, plain._unit.label_settings.font_size)
	var gear := autofree(HudGear.new()) as HudGear
	assert_eq(gear._bar.get_combined_minimum_size().y, 14.0, "the kit gear bar keeps its size")

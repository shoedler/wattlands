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

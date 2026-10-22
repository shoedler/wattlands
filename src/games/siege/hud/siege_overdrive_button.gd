class_name SiegeOverdriveButton
extends Button
## The Overdrive button (brief 3 HUD, bottom right above the PANIC button): ready, the prompt
## ("Surge for Overdrive!", glowing, when the rules say a surge would start it), the seconds
## left while it runs, and the cooldown refilling. Pressing it sends the same intent as ability_1
## (SiegeIntents.overdrive("button")); the rules decide whether it is allowed.

const SIZE := Vector2(400, 84)

var game: SiegeGame = null
var mode: String = SiegeHudModel.OD_CLOSED
var fill: float = 0.0
var _t: float = 0.0


func _init() -> void:
	name = "SiegeOverdriveButton"
	theme = WlTheme.get_theme()
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = SIZE
	add_theme_font_size_override("font_size", WlTheme.TOAST_PX)
	pressed.connect(_on_pressed)
	visible = false


func _process(delta: float) -> void:
	_t += delta
	refresh()


func _on_pressed() -> void:
	if game != null and game.ctx != null and game.ctx.intents != null:
		game.ctx.intents.send(SiegeIntents.overdrive(SiegeIds.VIA_BUTTON))


func refresh() -> void:
	if game == null or game.state == null or SiegeHudModel.own_rider(game) == null:
		visible = false
		return
	visible = true
	var face := SiegeHudModel.overdrive_face(game)
	mode = str(face["mode"])
	fill = float(face["fill"])
	text = str(face["text"])
	disabled = not bool(face["enabled"])
	var bg := WlTheme.PANEL
	var border := WlTheme.PANEL_BORDER
	match mode:
		SiegeHudModel.OD_PROMPT:
			var pulse := 0.5 + 0.5 * sin(_t * 7.0)
			bg = Color(0.13, 0.2, 0.26, 0.95).lerp(Color(0.3, 0.45, 0.55, 0.95), pulse)
			border = WlTheme.GLOW
		SiegeHudModel.OD_ACTIVE:
			bg = Color(0.14, 0.3, 0.4, 0.95)
			border = WlTheme.ACCENT
		SiegeHudModel.OD_READY:
			border = WlTheme.ACCENT
	var sb := WlTheme.panel_style(bg, border, 4 if mode == SiegeHudModel.OD_PROMPT else 2)
	for style_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(style_name, sb)
	for color_name: String in [
		"font_color", "font_disabled_color", "font_hover_color", "font_pressed_color"
	]:
		add_theme_color_override(
			color_name, WlTheme.TEXT if mode != SiegeHudModel.OD_COOLDOWN else WlTheme.TEXT_DIM
		)
	queue_redraw()


func _draw() -> void:
	# The progress under the text: seconds left while it runs, the refill while it recharges.
	if mode != SiegeHudModel.OD_ACTIVE and mode != SiegeHudModel.OD_COOLDOWN:
		return
	var r := Rect2(12, size.y - 14, size.x - 24, 8)
	draw_rect(r, WlTheme.BAR_BG)
	var col := WlTheme.ACCENT if mode == SiegeHudModel.OD_ACTIVE else WlTheme.TEXT_DIM
	draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), col)

class_name SiegeHudPanel
extends PanelContainer
## Base of Siege's own HUD Controls: a dark kit-styled card that reads the module's state every
## frame and never takes the mouse (buttons inside opt in). refresh() is also called by tests.

var game: SiegeGame = null
var _t_accum: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = WlTheme.get_theme()
	add_theme_stylebox_override("panel", WlTheme.panel_style())


func _process(delta: float) -> void:
	_t_accum += delta
	refresh()


## Re-reads the state into the labels. Subclasses override it.
func refresh() -> void:
	pass


func state() -> SiegeState:
	return game.state if game != null else null


func strings() -> GameStrings:
	return SiegeHudModel.strings_of(game)


func own_rider() -> SiegeRiderState:
	return SiegeHudModel.own_rider(game)


func send(intent: Dictionary) -> void:
	if game != null and game.ctx != null and game.ctx.intents != null:
		game.ctx.intents.send(intent)


## A Label in the kit's text style.
static func make_label(px: int, color: Color = WlTheme.TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.label_settings = WlTheme.label_settings(px, color, bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

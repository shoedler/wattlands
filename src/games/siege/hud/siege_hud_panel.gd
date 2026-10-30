class_name SiegeHudPanel
extends PanelContainer
## Base of Siege's own HUD Controls: a dark kit-styled card that reads the module's state every
## frame and never takes the mouse (buttons inside opt in). refresh() is also called by tests.

var game: SiegeGame = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = WlTheme.get_theme()
	add_theme_stylebox_override("panel", WlTheme.panel_style())


func _process(_delta: float) -> void:
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


## The session's look of `slot` (color, shape, pattern, hollow).
static func look_of(game: SiegeGame, slot: int) -> Dictionary:
	if game != null and game.ctx != null:
		for p in game.ctx.players:
			if p.slot_index == slot:
				return {
					"color": p.color, "shape": p.shape, "pattern": p.pattern, "hollow": p.hollow
				}
	return Wl.slot_look(slot)

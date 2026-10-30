class_name SiegeStripOverlay
extends HBoxContainer
## Siege's teammate strip (docs/games/siege.md 3 HUD, bottom centre): one SiegeStripCell per slot
## in one low row. It is the only teammate strip (the kit's card strip is left out of the spec),
## so each rider's raw W and %FTP show once, beside the station they drive.

var game: SiegeGame = null
var cells: Array[SiegeStripCell] = []


func _init() -> void:
	name = "SiegeStripOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_CENTER
	for slot in 4:
		var c := SiegeStripCell.new(slot)
		cells.append(c)
		add_child(c)


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	var s := game.state if game != null else null
	if s == null:
		visible = false
		return
	visible = true
	var tx := SiegeHudModel.strings_of(game)
	var own := SiegeHudModel.own_rider(game)
	for slot in cells.size():
		var rider := s.rider_at(slot)
		cells[slot].set_look(SiegeHudPanel.look_of(game, slot))
		cells[slot].set_local(rider != null and rider == own)
		cells[slot].show_rider(rider, tx)

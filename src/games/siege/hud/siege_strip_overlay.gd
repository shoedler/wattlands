class_name SiegeStripOverlay
extends HBoxContainer
## Siege's own Control beside the kit's teammate strip (brief 3 HUD): one SiegeStripCell per
## slot, in slot order, each 260 px wide with the strip's 10 px gap so the cells line up under
## the kit's cards. Shows every rider's routing target icon and markers, and (from the state,
## so from the snapshot on a client) raw W and %FTP.

var game: SiegeGame = null
var cells: Array[SiegeStripCell] = []


func _init() -> void:
	name = "SiegeStripOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 10)
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
	for slot in cells.size():
		var rider := s.rider_at(slot)
		var look := _look_of(slot)
		cells[slot].set_look(look)
		cells[slot].show_rider(rider, tx, look["color"])


func _look_of(slot: int) -> Dictionary:
	if game != null and game.ctx != null:
		for p in game.ctx.players:
			if p.slot_index == slot:
				return {
					"color": p.color, "shape": p.shape, "pattern": p.pattern, "hollow": p.hollow
				}
	return Wl.slot_look(slot)

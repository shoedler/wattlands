class_name SiegeView
extends Node2D
## The template's 2D view at pixel_base 640 x 360 (BRIEF 3.9): one lane per rider; reads state only.

var game: SiegeGame = null


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("#20242c"))
	if game == null or game.state.is_empty():
		return
	var riders: Array = game.state["riders"]
	var track := float(game.state["track_m"])
	for rd: Dictionary in riders:
		var slot := int(rd["slot"])
		var y := 360.0 * (slot + 0.5) / riders.size()
		var x := 40.0 + 560.0 * fmod(float(rd["dist_m"]), track) / track
		var color: Color = (
			game.ctx.players[slot].color if slot < game.ctx.players.size() else Color.WHITE
		)
		draw_line(Vector2(40, y), Vector2(600, y), Color("#5a6270"), 2.0)
		draw_circle(Vector2(x, y), 6.0, Color.DIM_GRAY if rd["afk"] else color)

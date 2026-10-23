class_name FishingView
extends Node2D
## The 640 x 360 view (brief 3.5): the deck bar plus one lane per slot. It only reads
## `game.state` (and `game.history` on clients). G0 stub: flat lane bands and a boat block, so
## screenshots show the layout; the view builder owns this file.

var game: FishingGame = null


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(FishingLayout.deck_rect(), Color("2b1d14"))
	if game == null or game.state == null:
		return
	var n := game.state.lanes.size()
	for l in game.state.lanes:
		var i := l.slot
		var r := FishingLayout.lane_rect(i, n)
		var rows := FishingLayout.rows(r.size.y)
		draw_rect(Rect2i(r.position, Vector2i(r.size.x, rows["sky"])), Color("7fd3f5"))
		draw_rect(
			Rect2i(
				0,
				FishingLayout.water_y(i, n),
				r.size.x,
				FishingLayout.water_h(n) + int(rows["reef"])
			),
			Color("1f6fb2")
		)
		draw_rect(
			Rect2i(FishingConst.BOAT_X0, FishingLayout.surface_y(i, n) - 12, 80, 14), Color.WHITE
		)
		var border := Color("1a1f3a")
		if game.ctx != null and l.peer == game.ctx.local_peer:
			border = game.ctx.players[i].color
		draw_rect(r, border, false, 1.0)

class_name TankView
extends Node2D
## The 2D view at pixel_base 640 x 360 (brief 3): the dark 2.5D diorama, the cutaway tank, enemies,
## shells and effects. It only reads state (TankGame.state); a client renders other riders from
## snapshot history and its own room from client_predict. Owner: view.
##
## Layout (TankConst): ground line y 296, the hull's rear at screen x 16, enemies entering from the
## right (rear rushers from the left); the HUD covers only y 0-60 and 300-360.
##
## G0 stub: draws the ground, the hull, its rooms and the enemies as flat palette shapes so the
## game is visible end to end. G1 (view) replaces it, keeping `game` and make_view()'s contract.

var game: TankGame = null


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, TankConst.SCREEN_W, TankConst.SCREEN_H), Color("#0e1013"))
	draw_rect(
		Rect2(0, TankConst.GROUND_Y, TankConst.SCREEN_W, TankConst.SCREEN_H - TankConst.GROUND_Y),
		Color("#241d17")
	)
	if game == null or game.state == null:
		return
	var st := game.state
	var hl := st.hull
	var cam := st.camera_x()
	var hull_rect := Rect2(
		TankConst.REAR_SCREEN_X, TankConst.GROUND_Y - 10 - hl.hull_h, hl.hull_w, hl.hull_h
	)
	draw_rect(hull_rect, Color("#363d44"))
	var n := st.stations.size()
	for i in n:
		var room_w := (hl.hull_w - 16.0) / maxf(n, 1)
		var room := Rect2(
			hull_rect.position.x + 8 + i * room_w, hull_rect.position.y + 12, room_w - 4, 40
		)
		draw_rect(room, Color("#ffb35c") if st.stations[i].in_band else Color("#1f2429"))
	for e in st.enemies:
		var x := e.x_px - cam
		draw_rect(
			Rect2(x, TankConst.GROUND_Y - maxf(e.h, 20), maxf(e.w, 40), maxf(e.h, 20)),
			Color("#5a3a2e")
		)
	for sh in st.shells:
		draw_circle(Vector2(sh.x - cam, sh.y), 1.5, Color("#ffd99a"))

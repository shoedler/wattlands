class_name TankDieselRoom
extends TankRoomView
## The diesel's room (brief 3 "Cutaway"): a block with four cylinder windows whose pistons run at the
## rider's cadence (SlidingPart, staggered), a crankshaft with rods, a flywheel (SpinningPart with
## inertia), cylinder glow by watts and an exhaust stack whose smoke follows watts (the rig emits it
## from exhaust_frac()). The Bulwark's room extends this with its gearbox. speed = cadence / 120.

var block_pos: Vector2 = Vector2.ZERO
var windows: Array[Rect2] = []
var crank_y: float = 26.0
var travel: float = 6.0
var pistons: Array[SlidingPart] = []
var flywheel: SpinningPart = null
## The glow strength 0 .. 1.4 (watts / FTP while powered).
var glow: float = 0.0


func build() -> void:
	block_pos = anchor_local("diesel_block")
	var dm: Dictionary = machinery.get("diesel_block", {})
	crank_y = float(dm.get("crank_y", 26))
	travel = float(dm.get("piston_travel_px", 6))
	for w: Variant in dm.get("cylinder_windows", []):
		windows.append(TankRigs.rect(w))
	var block := Sprite2D.new()
	block.name = "Block"
	block.texture = TankSprites.tex("diesel_block")
	block.centered = false
	block.position = block_pos
	add_child(block)
	for i in windows.size():
		var p := SlidingPart.new()
		p.name = "Piston%d" % i
		p.mode = SlidingPart.Mode.RECIPROCATE
		p.axis = Vector2.DOWN
		p.travel_px = travel
		p.max_cps = 2.0
		p.phase = float(i) * 0.25
		p.auto_process = false
		p.position = block_pos + windows[i].position + Vector2(1, 1)
		var head := TankPainter.new()
		head.name = "Head"
		head.painter = _paint_piston
		head.set_meta("w", windows[i].size.x - 2.0)
		p.add_child(head)
		add_child(p)
		pistons.append(p)
	flywheel = SpinningPart.new()
	flywheel.name = "Flywheel"
	flywheel.texture = TankSprites.tex("flywheel_large")
	flywheel.position = anchor_local("flywheel")
	flywheel.max_rpm = 120.0
	flywheel.inertia_s = 0.35
	flywheel.snap_steps = 16
	flywheel.auto_process = false
	add_child(flywheel)
	build_more()


## Hook for the Bulwark's gearbox (after the diesel machinery).
func build_more() -> void:
	pass


func animate(dt: float) -> void:
	var sp := input.speed()
	for p in pistons:
		p.speed = sp
		p.tick(dt)
	flywheel.speed = sp
	flywheel.tick(dt)
	glow = 0.0 if input.unpowered else clampf(input.frac, 0.0, 1.4)
	animate_more(dt)


func animate_more(_dt: float) -> void:
	pass


## The smoke the stack should make: watts / FTP, 0 without power.
func exhaust_frac() -> float:
	return glow


func engine_lights() -> void:
	if glow <= 0.02:
		return
	var origin := hub.to_layer(rect.position + block_pos)
	for i in windows.size():
		var stroke := 1.0 - clampf(pistons[i].offset() / maxf(travel, 1.0), 0.0, 1.0)
		var c := origin + windows[i].position + windows[i].size * 0.5
		hub.lights.add(
			c, 22.0 + 16.0 * glow, TankPalette.FIRE, glow * 0.42 * (0.45 + 0.55 * stroke)
		)


func paint_machinery_front(item: Node2D) -> void:
	var y := block_pos.y + crank_y
	item.draw_line(
		Vector2(block_pos.x + 4, y), Vector2(block_pos.x + 52, y), TankPalette.STEEL_DARK, 2.0
	)
	item.draw_line(
		Vector2(block_pos.x + 4, y - 1), Vector2(block_pos.x + 52, y - 1), TankPalette.STEEL, 1.0
	)
	var ang := flywheel.angle()
	for i in windows.size():
		var cx := block_pos.x + windows[i].position.x + windows[i].size.x * 0.5
		var throw := Vector2(
			cx + cos(ang + float(i) * PI * 0.5) * 2.0, y + sin(ang + float(i) * PI * 0.5) * 2.0
		)
		var base := Vector2(
			cx, block_pos.y + windows[i].position.y + 1.0 + pistons[i].offset() + 4.0
		)
		item.draw_line(base, throw, TankPalette.STEEL, 1.0)
		item.draw_circle(throw, 1.5, TankPalette.STEEL_LIGHT)
		var wr := Rect2(block_pos + windows[i].position, windows[i].size)
		var stroke := 1.0 - clampf(pistons[i].offset() / maxf(travel, 1.0), 0.0, 1.0)
		_window_glow(item, wr, glow * (0.1 + 0.32 * stroke))
	paint_more(item)


func paint_more(_item: Node2D) -> void:
	pass


## The combustion glow in a cylinder window: hottest at the bottom (the piston crown), fading up
## the bore in rows, so the window reads as a lit chamber rather than a flat orange square.
static func _window_glow(item: Node2D, wr: Rect2, a: float) -> void:
	if a <= 0.005:
		return
	var rows := int(wr.size.y)
	for k in rows:
		var t := float(k) / maxf(float(rows - 1), 1.0)
		var col := TankPalette.FIRE.lerp(TankPalette.AMBER, t * t)
		item.draw_rect(
			Rect2(wr.position.x, wr.position.y + float(k), wr.size.x, 1.0),
			TankPalette.with_alpha(col, a * (0.25 + 0.75 * t * t))
		)


func _paint_piston(item: Node2D) -> void:
	var w := float(item.get_meta("w", 6.0))
	item.draw_rect(Rect2(0, 0, w, 4), TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(0, 0, w, 1), TankPalette.STEEL_LIGHT)

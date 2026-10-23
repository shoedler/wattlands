class_name TankBossBars
extends TankHudPanel
## The boss bars (brief 3 HUD): the Behemoth's three bogies (rear to front) and its turret as HP
## bars along the top, plus a warning triangle while its main gun telegraphs (shape and colour: the
## "Surge to dodge" toast carries the words). Nothing shows before the boss appears. 678 x 66 px at
## 1080p in the 226 x 22 art px rect.

const LABEL_PX := 22.0
const BAR_H := 24.0
const LOW_FRAC := 0.34


func _init() -> void:
	super._init()
	name = "TankBossBars"
	design_size = Vector2(678, 66)


func compute(state: TankState) -> Dictionary:
	return TankHudModel.boss_bars(state)


func _draw() -> void:
	if not bool(model.get("show", false)):
		return
	panel()
	var bogies: Array = model["bogies"]
	text(Vector2(10, 2), tr_key("TANK_HUD_BOGIES"), LABEL_PX, WlTheme.TEXT_DIM, 240.0)
	var bw := 98.0
	for i in bogies.size():
		var f := float(bogies[i])
		var r := Rect2(Vector2(10.0 + float(i) * (bw + 8.0), 32.0), Vector2(bw, BAR_H))
		bar(r, f, WlTheme.WARN if f < LOW_FRAC else WlTheme.TEXT)
		if f <= 0.0:
			# A broken bogie: a cross, so the state never depends on colour.
			line(r.position + Vector2(8, 4), r.end - Vector2(8, 4), WlTheme.WARN, 4.0)
			line(
				Vector2(r.position.x + 8.0, r.end.y - 4.0),
				Vector2(r.end.x - 8.0, r.position.y + 4.0),
				WlTheme.WARN,
				4.0
			)
	var tx := 10.0 + 3.0 * (bw + 8.0) + 20.0
	text(Vector2(tx, 2), tr_key("TANK_HUD_TURRET"), LABEL_PX, WlTheme.TEXT_DIM, 200.0)
	var tf := float(model["turret"])
	bar(
		Rect2(Vector2(tx, 32.0), Vector2(design_size.x - tx - 64.0, BAR_H)),
		tf,
		WlTheme.WARN if tf < LOW_FRAC else WlTheme.TEXT
	)
	if bool(model.get("telegraph", false)):
		var cx := design_size.x - 30.0
		var tri := PackedVector2Array(
			[Vector2(cx, 8), Vector2(cx + 22.0, 52), Vector2(cx - 22.0, 52)]
		)
		polygon(tri, WlTheme.WARN if bool(model.get("blink", false)) else WlTheme.TEXT)
		rect(Rect2(cx - 2.0, 22.0, 4.0, 16.0), Color(0.05, 0.06, 0.08))
		rect(Rect2(cx - 2.0, 43.0, 4.0, 4.0), Color(0.05, 0.06, 0.08))

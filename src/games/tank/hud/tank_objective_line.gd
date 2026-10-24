class_name TankObjectiveLine
extends TankHudPanel
## The objective line (brief 3 HUD): "Halt line: 840 m" in an Advance, "Gun line 2/4" at a gun line,
## "Behemoth" in the boss fight, "Regroup" (warning colour) while the tank holds before min_s. One
## line of 30 px text (1080p) in the 132 x 15 art px rect right of the station card.

const TEXT_PX := 30.0


func _init() -> void:
	super._init()
	name = "TankObjectiveLine"
	design_size = Vector2(396, 45)


func compute(state: TankState) -> Dictionary:
	return TankHudModel.objective(state)


func _draw() -> void:
	if model.is_empty():
		return
	panel()
	var s := tr_key(str(model["key"]), model["args"])
	var col := WlTheme.WARN if bool(model.get("warn", false)) else WlTheme.TEXT
	text(Vector2(10, 6), s, TEXT_PX, col, design_size.x - 20.0, HORIZONTAL_ALIGNMENT_CENTER)

extends Node
## Art review of the code-drawn ocean (tools/screenshot
## --scene=res://tests/games/fishing/view/preview/fishing_scenery_preview.tscn): four cameras on
## the roam map (the dock, the reef, the deep, the edge), each a 640 x 360 view, in a 2 x 2 grid.

const CAMS: Array[float] = [-40.0, 2900.0, 7700.0, 8800.0]


class Painter:
	extends Node2D
	var scenery: FishingScenery = null
	var cam: float = 0.0
	var t: float = 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		scenery.paint_back(self, cam, t)


func _ready() -> void:
	var map: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/fishing/map.json")
	)
	var world := FishingWorld.from_map(map, 1)
	for i in CAMS.size():
		var box := SubViewportContainer.new()
		box.position = Vector2((i % 2) * 640, (i / 2) * 360)
		var vp := SubViewport.new()
		vp.size = Vector2i(640, 360)
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		box.add_child(vp)
		var p := Painter.new()
		p.scenery = FishingScenery.new()
		p.scenery.world = world
		p.cam = CAMS[i]
		p.scenery.view_depth_m = p.scenery.target_view_depth(CAMS[i])
		vp.add_child(p)
		add_child(box)

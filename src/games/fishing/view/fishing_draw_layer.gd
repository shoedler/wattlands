class_name FishingDrawLayer
extends Node2D
## One code-drawn layer between sprite nodes: its owner draws on it through `painter`
## (painter.call(layer) inside _draw), so a lane keeps brief 3.5's back-to-front order with
## sprites and code drawing interleaved.

var painter: Callable = Callable()


static func make(p_name: String, p_painter: Callable) -> FishingDrawLayer:
	var layer := FishingDrawLayer.new()
	layer.name = p_name
	layer.painter = p_painter
	return layer


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)

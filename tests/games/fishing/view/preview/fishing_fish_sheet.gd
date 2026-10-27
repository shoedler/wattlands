extends Node
## Art review of every fish in every pose (tools/screenshot
## --scene=res://tests/games/fishing/view/preview/fishing_fish_sheet.tscn --size=1920x1080):
## one row per species on the water band it lives in (tinted as the view tints it), the frames
## left to right: swim 1-3, pull 15 and 30 degrees with the line leaving the mouth, tired with
## the line straight up.

const SHEET := Vector2i(640, 360)
const COL_W := 92
const LABEL_W := 84
const TOP := 14
const LINE := FishingPalette.DEEP
const LABELS: Array[String] = ["swim 1", "swim 2", "swim 3", "pull 15", "pull 30", "tired"]
## The water band each species is shown on (FishingPalette.SEA index).
const BANDS: Array[int] = [0, 0, 0, 1, 1, 1, 2, 2, 2, 3]


class Painter:
	extends Node2D
	var rows: Array[Dictionary] = []

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(SHEET)), FishingPalette.SEA[3])
		draw_rect(Rect2(0, 0, SHEET.x, TOP), FishingPalette.SKY)
		var font := FishingHudDraw.font()
		for i in LABELS.size():
			var x := LABEL_W + COL_W * i + 30
			draw_string(font, Vector2(x, 10), LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, LINE)
		for row in rows:
			var r: Rect2 = row["rect"]
			draw_rect(r, FishingPalette.SEA[int(row["band"])])
			var col := FishingPalette.ABYSS if int(row["band"]) >= 2 else LINE
			draw_string(
				font,
				r.position + Vector2(3, 10),
				str(row["name"]),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				9,
				col
			)
			for line: Array in row["lines"]:
				for p in FishingRig.raster(line[0], line[1]):
					draw_rect(Rect2(Vector2(p), Vector2.ONE), col)


func _ready() -> void:
	var pv := PixelViewport.new()
	pv.pixel_base = SHEET
	pv.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(pv)
	var root := Node2D.new()
	var painter := Painter.new()
	root.add_child(painter)
	var y := TOP
	for i in FishingArtGrids.FISH.size():
		var id: String = FishingArtGrids.FISH[i]
		var size := FishingSprites.size_of(id)
		var a := FishingSprites.anchor(id)
		var h := 0
		for k in FishingArtGrids.FISH_POSES.size():
			h = maxi(h, FishingSprites.bounds(id, k).size.y)
		var row_h := h + 6
		var row := {
			"rect": Rect2(0, y, SHEET.x, row_h),
			"band": BANDS[i],
			"name": FishingHudModel.species_name(null, i),
			"lines": [],
		}
		for k in FishingArtGrids.FISH_POSES.size():
			var box := FishingSprites.bounds(id, k)
			var mouth := Vector2i(LABEL_W + COL_W * k + 2 + maxi(0, (COL_W - size.x) / 2), y + 3)
			mouth.y += a.y - box.position.y
			var s := Sprite2D.new()
			s.centered = false
			s.texture = FishingSprites.frame(id, k)
			s.position = Vector2(mouth - a)
			var m := FishingPaletteMap.apply(s)
			FishingPaletteMap.set_shift(m, FishingPaletteMap.fish_shift(BANDS[i]))
			root.add_child(s)
			var run := 4 if k == FishingSprites.FISH_PULL15 else 2
			if k == FishingSprites.FISH_PULL15 or k == FishingSprites.FISH_PULL30:
				var up := mini(mouth.y - y - 2, 12)
				(row["lines"] as Array).append(
					[mouth - Vector2i(1, 0), mouth - Vector2i(up * run, up)]
				)
			elif k == FishingSprites.FISH_TIRED:
				(row["lines"] as Array).append([mouth + Vector2i(0, -1), Vector2i(mouth.x, y + 1)])
		painter.rows.append(row)
		y += row_h
	pv.set_game_view(root)

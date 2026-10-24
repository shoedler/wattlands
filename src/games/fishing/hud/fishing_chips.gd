class_name FishingChips
extends FishingHudControl
## The light stopped menu as small chips in the world, next to what they act on: "Cast: <fish>"
## above each fish hint's silhouette, "Drive on" ahead of the bow and "Turn around" behind the
## stern (FishingHudModel.chips), on abyss-teal panels. The highlighted chip is lit with a foam
## frame and a caret.
## Positions come from the view's model (FishingView, through the game's "fishing_view" meta),
## in art px mapped onto this Control, which covers the view down to the meters.

const ART := Rect2i(0, 0, 640, 300)
## Chip offsets (art px): above a hint, and ahead of / behind the boat's pivot.
const HINT_LIFT := 12.0
const SIDE_DX := 64.0
const SIDE_Y := 24.0

## The chips of the last refresh with their art positions ("at"; tests read them).
var chips: Array[Dictionary] = []
var _t: float = 0.0


static func make(p_game: FishingGame) -> FishingChips:
	var c := FishingChips.new()
	c.game = p_game
	c.name = "FishingChips"
	c.design_h = float(ART.size.y * 3)
	return c


func ap() -> float:
	return size.x / float(ART.size.x) if size.x > 0.0 else 3.0


func refresh() -> void:
	_t += get_process_delta_time()
	chips.clear()
	var r := FishingHudModel.own_rider(game)
	var list := FishingHudModel.chips(game, r)
	if list.is_empty() or not game.has_meta(FishingView.META):
		return
	var view: Variant = game.get_meta(FishingView.META)
	if not view is FishingView:
		return
	var m: Dictionary = (view as FishingView).model
	var boat: Variant = (m.get("boats", {}) as Dictionary).get(r.slot)
	if not boat is Vector2:
		return
	var hints: Array = m.get("hints", [])
	var dir := float(r.heading)
	for e in list:
		var at := Vector2.ZERO
		var hint := int(e["hint"])
		if hint >= 0:
			for h: Dictionary in hints:
				if int(h["index"]) == hint:
					at = (h["pos"] as Vector2) - Vector2(0, HINT_LIFT)
		elif int(e["entry"]) == FishingConst.M_DRIVE_ON:
			at = (boat as Vector2) + Vector2(SIDE_DX * dir, -SIDE_Y)
		else:
			at = (boat as Vector2) + Vector2(-SIDE_DX * dir, -SIDE_Y)
		var c := e.duplicate()
		c["at"] = at
		chips.append(c)


func _draw() -> void:
	var s := ap()
	var fpx := px(WlTheme.SMALL_PX)
	var placed: Array[Rect2] = []
	for c in chips:
		var text := str(c["text"])
		var w := FishingHudDraw.text_w(text, fpx, true) + 20.0
		var h := float(fpx) + 14.0
		var center := (c["at"] as Vector2) * s
		center.x = clampf(center.x, w * 0.5 + 4.0, size.x - w * 0.5 - 4.0)
		var r := Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h))
		for k in 4:
			var hit := false
			for o in placed:
				if o.grow(4.0).intersects(r):
					hit = true
			if not hit:
				break
			r.position.y -= h + 6.0
		center = r.get_center()
		placed.append(r)
		var lit := bool(c["selected"])
		FishingHudDraw.panel(self, r)
		if lit:
			draw_rect(r.grow(2.0), FishingPalette.HUD_TEXT, false, 3.0)
			var bob := roundf(sin(_t * 6.0) * 2.0)
			var y0 := r.end.y + 4.0 + bob
			var tri := PackedVector2Array(
				[Vector2(center.x - 8, y0), Vector2(center.x + 8, y0), Vector2(center.x, y0 + 8)]
			)
			draw_colored_polygon(tri, FishingPalette.HUD_TEXT)
		var col := FishingPalette.HUD_TEXT if lit else FishingPalette.HUD_DIM
		FishingHudDraw.text(self, Vector2(r.position.x + 10.0, r.end.y - 9.0), text, fpx, col, lit)

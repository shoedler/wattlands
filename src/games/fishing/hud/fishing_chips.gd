class_name FishingChips
extends FishingHudControl
## The light stopped menu as small chips in the world, next to what they act on: "Cast: <fish>"
## above each fish hint's silhouette, "Drive on" ahead of the bow and "Turn around" behind the
## stern (FishingHudModel.chips), on abyss-teal panels, kept clear of the boat and of each other
## (a chip that would overlap moves above or below what it hits), never above TOP_ROW (under
## the minimap) and on the art pixel grid. The highlighted chip is lit with a foam frame and a
## caret.
## Positions come from the view's model (FishingView, through the game's "fishing_view" meta),
## in art px mapped onto this Control, which covers the view down to the meters.

const ART := Rect2i(0, 0, 640, 300)
## Chip offsets (art px): above a hint, and ahead of / behind the boat's pivot.
const HINT_LIFT := 20.0
## A hint fish's box round its centre (art px): chips keep clear of it too.
const FISH_BOX := Rect2(-18, -9, 36, 18)
const SIDE_DX := 64.0
const SIDE_Y := 24.0
## The boat's box round its pivot (art px): chips keep clear of it.
const BOAT_BOX := Rect2(-46, -36, 92, 44)
## No chip rises above this row (art px): the minimap's strip ends just above it.
const TOP_ROW := 30.0
## The lit chip's caret under it (pixels).
const CARET: Array[String] = ["#####", ".###.", "..#.."]

## The chips of the last refresh with their art positions ("at"; tests read them).
var chips: Array[Dictionary] = []
## The local boat's box and the hint fish's boxes (art px).
var boat_box: Rect2 = Rect2()
var fish_boxes: Array[Rect2] = []
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
	boat_box = Rect2()
	fish_boxes.clear()
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
	boat_box = Rect2((boat as Vector2) + BOAT_BOX.position, BOAT_BOX.size)
	var hints: Array = m.get("hints", [])
	for h: Dictionary in hints:
		fish_boxes.append(Rect2((h["pos"] as Vector2) + FISH_BOX.position, FISH_BOX.size))
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
	var u := float(FishingHudDraw.unit(k()))
	var pad := 3.0 * u
	var line_h := float(FishingHudDraw.LINE_ROWS) * u
	var placed: Array[Rect2] = []
	if boat_box.size != Vector2.ZERO:
		placed.append(Rect2(boat_box.position * s, boat_box.size * s))
	for f in fish_boxes:
		placed.append(Rect2(f.position * s, f.size * s))
	for c in chips:
		var text := str(c["text"])
		var w := FishingHudDraw.text_w(text, k()) + 2.0 * pad
		var h := line_h + 2.0 * pad
		var center := (c["at"] as Vector2) * s
		center.x = clampf(center.x, w * 0.5 + u, size.x - w * 0.5 - u)
		center.y = maxf(center.y, TOP_ROW * s + h * 0.5)
		var r := _free_spot(Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h)), placed, TOP_ROW * s)
		r.position = (r.position / u).round() * u
		placed.append(r)
		var lit := bool(c["selected"])
		FishingHudDraw.panel(self, r)
		if lit:
			FishingHudDraw.frame(self, r.grow(u), u, FishingPalette.HUD_TEXT)
			var bob := roundf(sin(_t * 6.0)) * u
			var tip := Vector2(roundf(r.get_center().x / u) * u - 2.0 * u, r.end.y + 2.0 * u + bob)
			FishingHudDraw.pixels(self, CARET, tip, u, FishingPalette.HUD_TEXT)
		var col := FishingPalette.HUD_TEXT if lit else FishingPalette.HUD_DIM
		FishingHudDraw.text_line(self, r.position.x + pad, r.position.y + pad, text, k(), col)


## The first of `r`, then `r` moved up and down by a chip's height (nearest first), that
## touches nothing in `placed` and stays below `top`; `r` itself when all are taken.
static func _free_spot(r: Rect2, placed: Array[Rect2], top: float = 0.0) -> Rect2:
	var step := r.size.y + 8.0
	for k in 9:
		var cand := r
		cand.position.y += step * float((k + 1) / 2) * (-1.0 if k % 2 == 1 else 1.0)
		if cand.position.y < top:
			continue
		var free := true
		for o in placed:
			if o.grow(4.0).intersects(cand):
				free = false
				break
		if free:
			return cand
	return r

class_name FishingBoatPanel
extends FishingHudControl
## Base of the panels that stand just under the local boat, on the side away from what is on the
## line (the fight panel: the fish; the jig panel: the lure): FishingPanelRows' width, `panel_rect`
## (art px; Rect2i() when hidden, tests read it) and place_panel(). The rect is the whole view;
## the panel follows the boat (FishingView's model).

## The panel's top under the surface row, and how far it reaches past the boat's pivot toward
## what is on the line.
const BELOW_SURFACE := 12
const OVER_PIVOT := 30

var panel_rect: Rect2i = Rect2i()
var _anchor: Vector2 = Vector2(-1, -1)
var _toward_left: bool = true


## Follows the boat of `r` and puts the panel on the side away from the view model's `thing`
## ("mouth": the fish; "lure": the wobbler) of the same slot.
func track_boat(r: FishingRiderState, thing: String) -> void:
	_anchor = Vector2(-1, -1)
	var v := view()
	if r != null and v != null:
		var boat: Variant = (v.model.get("boats", {}) as Dictionary).get(r.slot)
		if boat is Vector2:
			_anchor = boat
			var at: Variant = (v.model.get(thing, {}) as Dictionary).get(r.slot)
			_toward_left = not (at is Vector2) or (at as Vector2).x < _anchor.x


## The panel's rect (art px) for a panel `h` rows tall at the boat.
func place_panel(h: int) -> Rect2i:
	var aw := art_rect.size.x
	var w := FishingPanelRows.W
	var x := (aw - w) / 2
	if _anchor.x >= 0.0:
		x = int(_anchor.x) - OVER_PIVOT if _toward_left else int(_anchor.x) + OVER_PIVOT - w
	x = clampi(x, 4, maxi(aw - w - 4, 4))
	return Rect2i(x, FishingScenery.SURF_Y + BELOW_SURFACE, w, h)

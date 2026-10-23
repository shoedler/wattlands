class_name FishingRig
extends RefCounted
## The boat's rig in boat-local art pixels (origin = the boat sprite's top-left, bow right) and
## the code-drawn parts' geometry (brief 3.3 "code draws"): legs as two 2 px segments solved from
## hip to pedal, the rod bending with tension, the line sagging with slack and straight under
## strain. Pure functions, so tests check the shapes. Mount points are measured on the generated
## boat.png (GPT Image 2.5 via fal, assets/fishing/README.md), whose parts sit at: outboard
## x 0-8 y 12-31; open aft deck x 9-28 behind the gunwale (row 18); canopy posts x 29-30 and
## 41-42; console x 36-46 y 11-18; canopy roof x 26-48 y 2-4 (key red x 27-46 y 3-4); trim stripe
## key red on row 20 from x 9 to 55, rising to row 16 at the bow (x 73-75), with a coral row
## under it. tests/games/fishing/view/test_fishing_rig_art.gd checks these numbers against the
## PNG, so a re-rolled boat fails there first.

## The hull sits this far below the surface strip's top: its bottom rows sit in the water band
## and the angler's cap stays inside even a 4-lane lane's 3 px border.
const DRAFT := 9
const BOAT_W := 80
const BOAT_H := 32
## The gunwale row: the bike's feet stand on it.
const DECK_Y := 18
## rig_bike's top-left (24 x 16, opaque x 3-21 y 0-15, its feet on the deck) on the aft deck,
## and the crank hub at the bike's bottom bracket (bike x 10, y 11).
const BIKE_POS := Vector2(6, 3)
const CRANK_HUB := Vector2(16, 14)
const CRANK_R := 3.0
## rig_angler's top-left (14 x 12, opaque x 2-10 y 0-11: cap rows 0-1, shirt 4-9, hands at x 8-10
## y 7-8) seated on the saddle (bike x 4-7, y 3), the hip and the hands on the rod.
const ANGLER_POS := Vector2(6, -4)
const HIP := Vector2(11, 6)
const HANDS := Vector2(15, 4)
const THIGH := 6.0
const SHIN := 7.0
## The reel on the bike's front, where its flywheel sits (bike x 13-20 y 8-13), turned by the
## chain from the crank; the line runs from it up to the rod's first guide (ROD_GUIDE).
const REEL_HUB := Vector2(24, 12)
const ROD_GUIDE := 1
const REEL_R := 2.0
const CRANK_SPROCKET_R := 3.0
## The rod: butt in the angler's hands, tip at rest at lane x 88 (boat at x 8), over the canopy.
const ROD_BASE := HANDS
const ROD_TIP := Vector2(80, -4)
## Tip deflection at full tension (art px, toward the line).
const ROD_BEND_PX := 9.0
## Canopy roof (pattern cosmetics: the key-red rows of the roof) and the pennant's mast top on
## the roof's aft end (the flag streams aft, toward -x).
const CANOPY_RECT := Rect2i(27, 3, 20, 2)
const PENNANT_AT := Vector2(28, -3)
## Trim pixels (the trim cosmetic): the trim colours below this row; above it is the roof.
const TRIM_MIN_Y := 10
## The wake's attachment at the stern, in boat-local px.
const STERN := Vector2(0, 27)


## Two-segment leg from `hip` to `foot` (lengths l1, l2), the knee bent toward +x (forward).
## Returns [hip, knee, foot]; an out-of-reach foot is pulled in along the hip-foot line.
static func leg(
	hip: Vector2, foot: Vector2, l1: float = THIGH, l2: float = SHIN
) -> PackedVector2Array:
	var v := foot - hip
	var d := v.length()
	var lo := absf(l1 - l2) + 0.01
	var hi := l1 + l2 - 0.01
	var dir := v / d if d > 0.001 else Vector2.DOWN
	d = clampf(d, lo, hi)
	var end := hip + dir * d
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := Vector2(-dir.y, dir.x)
	if perp.x < 0.0:
		perp = -perp
	var knee := hip + dir * a + perp * h
	return PackedVector2Array([hip, knee, end])


## The pedal positions for crank angle `angle` (radians): [near, far].
static func pedals(hub: Vector2, r: float, angle: float) -> PackedVector2Array:
	var p := Vector2(cos(angle), sin(angle)) * r
	return PackedVector2Array([hub + p, hub - p])


## The rod as a polyline from `base` to its tip, bent toward `pull_dir` (a unit vector toward
## the line) by tension 0..1. `segments` + 1 points.
static func rod(
	base: Vector2, tip: Vector2, tension: float, pull_dir: Vector2, segments: int = 6
) -> PackedVector2Array:
	var bend := pull_dir.normalized() * ROD_BEND_PX * clampf(tension, 0.0, 1.0)
	var bent_tip := tip + bend
	var ctrl := base.lerp(tip, 0.55)
	var out := PackedVector2Array()
	for i in segments + 1:
		var t := float(i) / float(segments)
		out.append(_quad(base, ctrl, bent_tip, t))
	return out


## Sag in art px of a line `length` long: deep with slack, none under full strain.
static func line_sag(length: float, slack: float, strain: float) -> float:
	var k := clampf(0.3 + slack - 1.3 * strain, 0.0, 1.3)
	return length * 0.12 * k


## The line from `tip` to `end` as a polyline sagging by line_sag(): `segments` + 1 points.
static func line(
	tip: Vector2, end: Vector2, slack: float, strain: float, segments: int = 10
) -> PackedVector2Array:
	var sag := line_sag(tip.distance_to(end), slack, strain)
	var ctrl := tip.lerp(end, 0.5) + Vector2(0, sag * 2.0)
	var out := PackedVector2Array()
	for i in segments + 1:
		out.append(_quad(tip, ctrl, end, float(i) / float(segments)))
	return out


## The boat's trim pixels in `img` (boat.png): every pixel at y >= TRIM_MIN_Y in one of the trim
## colours (the key red and the coral, pink and peach that shade it). [positions, colours].
static func trim_pixels(img: Image) -> Array:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	if img == null or img.is_empty():
		return [pts, cols]
	var trim := FishingPalette.trim_colours()
	for y in range(TRIM_MIN_Y, img.get_height()):
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			for t in trim:
				if same_colour(c, t):
					pts.append(Vector2(x, y))
					cols.append(t)
					break
	return [pts, cols]


static func same_colour(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


## The rod tip in lane coordinates for a boat whose sprite top-left is `boat_pos`.
static func tip_in_lane(boat_pos: Vector2, tension: float, pull_dir: Vector2) -> Vector2:
	var pts := rod(ROD_BASE, ROD_TIP, tension, pull_dir)
	return boat_pos + pts[pts.size() - 1]


## The boat sprite's top-left in lane coordinates (lane origin at the lane's top).
static func boat_pos(sky_h: int) -> Vector2:
	return Vector2(FishingConst.BOAT_X0, sky_h + DRAFT - BOAT_H)


## Every point snapped to whole art pixels (crisp 1 px lines).
static func snapped(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(p.floor() + Vector2(0.5, 0.5))
	return out


static func _quad(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u + b * 2.0 * u * t + c * t * t

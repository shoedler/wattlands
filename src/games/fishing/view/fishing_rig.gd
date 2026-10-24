class_name FishingRig
extends RefCounted
## The boat's geometry in boat-local art pixels (origin = the boat_hull sprite's top-left, bow
## right, sea surface on WATERLINE) and the code-drawn parts' shapes: legs solved hip to pedal,
## arms to the tiller or the winch brake, the clutch lever, the rod (stowed or raised, bending
## with tension) and the line's sag. Pure functions, so tests check the shapes. The sprites in
## FishingArtGrids are drawn to these points.

const HULL_SIZE := Vector2i(96, 40)
## The sea surface (boat-local y): everything below it is seen through the water.
const WATERLINE := 30
## Hull extent along the waterline (stern .. bow) and the bow's stem head.
const STERN_X := 24
const BOW_X := 93
const BOW_TOP := Vector2(93, 17)
## Part sprites' top-left corners.
const FLYWHEEL_AT := Vector2(25, 7)
const FLYWHEEL_HUB := Vector2(29, 11)
const GEARS_AT := Vector2(26, 17)
const WINCH_AT := Vector2(21, 14)
const WINCH_HUB := Vector2(23, 16)
const PROP_AT := Vector2(7, 29)
const PROP_HUB := Vector2(8, 32)
const RIDER_AT := Vector2(37, 1)
## Pedalling: hip on the saddle, bottom bracket, crank radius, leg segment lengths.
const HIP := Vector2(40, 12)
const BB := Vector2(46, 19)
const CRANK_R := 3.0
const THIGH := 5.0
const SHIN := 7.5
## The chain runs from the chainring (at BB) to the gearbox's input sprocket.
const SPROCKET := Vector2(31, 18)
const SPROCKET_R := 1.0
const CHAINRING_R := 2.0
## Arms: from the shoulder to the tiller grip (driving) or the winch brake knob (fishing).
const SHOULDER := Vector2(40, 7)
const TILLER_GRIP := Vector2(37, 18)
const BRAKE_KNOB := Vector2(35, 11)
## The clutch lever on the gearbox: tilted toward the bow drives the prop, aft the winch.
const CLUTCH_PIVOT := Vector2(31, 16)
const CLUTCH_LEN := 4.0
## The rod in its stern mount: stowed nearly flat over the stern, raised to fish.
const ROD_BASE := Vector2(23, 12)
const ROD_STOW_TIP := Vector2(3, 9)
const ROD_FISH_TIP := Vector2(9, -7)
## Tip deflection at full tension (art px, toward the line).
const ROD_BEND_PX := 7.0
## The pennant mast at the bow.
const MAST_FOOT := Vector2(87, 18)
const MAST_TOP := Vector2(87, 11)
## Where the wake starts (behind the prop) and where the bow throws spray.
const WAKE_AT := Vector2(6, 30)
const SPRAY_AT := Vector2(91, 29)


## Two-segment leg from `hip` to `foot` (lengths l1, l2), the knee bent toward +x (forward).
## Returns [hip, knee, foot]; an out-of-reach foot is pulled in along the hip-foot line.
static func leg(
	hip: Vector2, foot: Vector2, l1: float = THIGH, l2: float = SHIN
) -> PackedVector2Array:
	var v := foot - hip
	var d := v.length()
	var dir := v / d if d > 0.001 else Vector2.DOWN
	d = clampf(d, absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var end := hip + dir * d
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := Vector2(-dir.y, dir.x)
	if perp.x < 0.0:
		perp = -perp
	return PackedVector2Array([hip, hip + dir * a + perp * h, end])


## The pedal positions for crank angle `angle` (radians): [near, far].
static func pedals(angle: float) -> PackedVector2Array:
	var p := Vector2(cos(angle), sin(angle)) * CRANK_R
	return PackedVector2Array([BB + p, BB - p])


## The arm from the shoulder to `hand` as [shoulder, elbow, hand] (elbow bent down).
static func arm(hand: Vector2) -> PackedVector2Array:
	var mid := SHOULDER.lerp(hand, 0.5) + Vector2(0, 1)
	return PackedVector2Array([SHOULDER, mid, hand])


## The clutch lever's tip: `fishing` 0 (toward the bow, driving) .. 1 (aft, winch engaged).
static func clutch_tip(fishing: float) -> Vector2:
	var a := lerpf(-0.95, -2.2, clampf(fishing, 0.0, 1.0))
	return CLUTCH_PIVOT + Vector2(cos(a), sin(a)) * CLUTCH_LEN


## The rod as a polyline from ROD_BASE: raised by `raise` 0 (stowed) .. 1 (fishing angle), its
## tip bent toward `pull_dir` (a unit vector toward the line) by `tension` 0..1. 7 points.
static func rod(raise: float, tension: float, pull_dir: Vector2) -> PackedVector2Array:
	var u := clampf(raise, 0.0, 1.0)
	var a0 := (ROD_STOW_TIP - ROD_BASE).angle()
	var a1 := (ROD_FISH_TIP - ROD_BASE).angle()
	var length := lerpf(ROD_BASE.distance_to(ROD_STOW_TIP), ROD_BASE.distance_to(ROD_FISH_TIP), u)
	var tip := ROD_BASE + Vector2.from_angle(lerp_angle(a0, a1, u)) * length
	var bent := tip + pull_dir.normalized() * ROD_BEND_PX * clampf(tension, 0.0, 1.0) * u
	var ctrl := ROD_BASE.lerp(tip, 0.55)
	var out := PackedVector2Array()
	for i in 7:
		out.append(quad(ROD_BASE, ctrl, bent, float(i) / 6.0))
	return out


## Sag in art px of a line `length` long: deep with slack, none under full strain.
static func line_sag(length: float, slack: float, strain: float) -> float:
	var k := clampf(0.3 + slack - 1.3 * strain, 0.0, 1.3)
	return length * 0.1 * k


## The line from `a` to `b` sagging by line_sag(): `segments` + 1 points.
static func line(
	a: Vector2, b: Vector2, slack: float, strain: float, segments: int = 8
) -> PackedVector2Array:
	var sag := line_sag(a.distance_to(b), slack, strain)
	var ctrl := a.lerp(b, 0.5) + Vector2(0, sag * 2.0)
	var out := PackedVector2Array()
	for i in segments + 1:
		out.append(quad(a, ctrl, b, float(i) / float(segments)))
	return out


## Every point snapped to whole art pixels (crisp 1 px lines).
static func snapped(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(p.floor() + Vector2(0.5, 0.5))
	return out


static func quad(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u + b * 2.0 * u * t + c * t * t

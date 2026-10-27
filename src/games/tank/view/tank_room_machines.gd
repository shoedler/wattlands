class_name TankRoomMachines
extends RefCounted
## The station machines in the tank's cutaway rooms (docs/games/tank.md 3.2, 3.4): small pixel
## overlays on the reference-cut room art, driven like TankMech's engine windows. `phase` is the
## crank revolutions of the room's rider (the integral of rpm / 60), every part turning at
## TankMech's integer ratio of it; `power` is watts over the rider's target (1 = in band).
##   diesel: six rockers nodding in the firing order on the block top and its flywheel (2:1);
##   steam:  the high-mounted engine (cylinder, crosshead, flywheel) and the shell hoist (1 shell a
##           revolution), the firebox lit by power;
##   dynamo: one big spoked armature turning 3:1 in its copper ring, sparks at its brushes by watts,
##           two capacitor jars charging once a revolution;
##   arc:    a tall V of copper horns (the Jacob's ladder: two climbs a revolution, the white-hot arc
##           reaching higher with the watts) and a small magneto wheel.
## Over band a machine shakes by a pixel; under band its lights die down. draw() paints the metal
## (normal blend), draw_light() the glow (the additive layer). Rooms are rects in variant px,
## `origin` is the variant's top-left on the canvas.

const DK := Color(0.16, 0.13, 0.1)
const MID := Color(0.27, 0.22, 0.16)
const HI := Color(0.4, 0.33, 0.23)
const GLINT := Color(0.66, 0.54, 0.36)
const BRASS := Color(0.82, 0.62, 0.3)
const COPPER := Color(0.74, 0.4, 0.19)
const STEEL := Color(0.62, 0.6, 0.55)
const RED := Color(0.62, 0.15, 0.09)
const SHADES: Array[Color] = [DK, HI, GLINT, Color(0.615, 0.465, 0.225)]
## The dynamo's armature (its centre in the room, its rim's radius) and the jars' left edge.
const DYNAMO_AT := Vector2(30, 15)
const DYNAMO_R := 9.0
const JAR_X := 41.0
const JARS := 2
## The arc's horns: their foot's x in the room and how far each tip leans out.
const ARC_FOOT := 15.0
const ARC_SPREAD := 11.0
## Crank angle (degrees, 720 a cycle) at which each of the six cylinders fires.
const DIESEL_FIRING: Array[float] = [0.0, 480.0, 240.0, 600.0, 120.0, 360.0]


## The per-machine shake (over band): a 1 px jolt on some frames.
static func shake(power: float, t: float, seed_v: float) -> Vector2:
	if smoothstep(1.18, 1.42, power) <= 0.4:
		return Vector2.ZERO
	if TankDraw.hash01(floorf(t * 14.0) + seed_v) <= 0.45:
		return Vector2.ZERO
	return (
		Vector2(1, 0) if TankDraw.hash01(floorf(t * 14.0) + seed_v + 3.0) > 0.5 else Vector2(0, -1)
	)


static func draw(
	ci: CanvasItem,
	origin: Vector2,
	rooms: Dictionary,
	phase: Dictionary,
	power: Dictionary,
	t: float
) -> void:
	var o := origin.floor()
	if rooms.has("diesel"):
		_diesel(
			ci,
			o,
			rooms["diesel"],
			float(phase.get("diesel", 0.0)),
			float(power.get("diesel", 0.0)),
			t
		)
	if rooms.has("steam"):
		_steam(
			ci, o, rooms["steam"], float(phase.get("steam", 0.0)), float(power.get("steam", 0.0)), t
		)
	if rooms.has("dynamo"):
		_dynamo(
			ci,
			o,
			rooms["dynamo"],
			float(phase.get("dynamo", 0.0)),
			float(power.get("dynamo", 0.0)),
			t
		)
	if rooms.has("arc"):
		_arc(ci, o, rooms["arc"], float(phase.get("arc", 0.0)), float(power.get("arc", 0.0)), t)


static func _diesel(ci: CanvasItem, o: Vector2, rd: Rect2, ph: float, pw: float, t: float) -> void:
	var e := ph * float(TankMech.RATIO["diesel"])
	var at := o + rd.position.floor() + shake(pw, t, 1.0)
	for i in 6:
		var x := at.x + 32.0 + i * 9.0
		var y := at.y + 1.0
		var cyc := fposmod(e * 360.0 + DIESEL_FIRING[i], 720.0)
		var tilt := 0.0
		if cyc > 540.0 and cyc < 700.0:
			tilt = 1.0
		elif cyc > 20.0 and cyc < 180.0:
			tilt = -1.0
		TankDraw.px(ci, Vector2(x, y + 1.0), DK)
		TankDraw.px(ci, Vector2(x - 2.0, y - tilt), STEEL)
		TankDraw.px(ci, Vector2(x - 1.0, y), STEEL)
		TankDraw.px(ci, Vector2(x, y), HI)
		TankDraw.px(ci, Vector2(x + 1.0, y), STEEL)
		TankDraw.px(ci, Vector2(x + 2.0, y + tilt), STEEL)
	var fw := at + Vector2(21, 18)
	TankDraw.wheel(ci, fw, 7.0, 6, e * TAU, MID, SHADES)
	TankDraw.px(ci, fw + Vector2(cos(e * TAU - PI * 0.5), sin(e * TAU - PI * 0.5)) * 6.0, BRASS)


static func _steam(ci: CanvasItem, o: Vector2, rs: Rect2, ph: float, pw: float, t: float) -> void:
	var th := ph * float(TankMech.RATIO["steam"]) * TAU
	var base := o + rs.position.floor() + shake(pw, t, 2.0)
	var fwc := base + Vector2(56, 7)
	var pin := fwc + Vector2(cos(th), sin(th)) * 2.5
	var xh := pin.x - sqrt(81.0 - pow(pin.y - fwc.y, 2.0))
	ci.draw_rect(Rect2(base + Vector2(33, 4), Vector2(7, 6)), DK)
	ci.draw_rect(Rect2(base + Vector2(33, 4), Vector2(7, 1)), HI)
	ci.draw_rect(Rect2(base + Vector2(40, 6), Vector2(1, 2)), BRASS)
	TankDraw.line_px(ci, base + Vector2(41, 7), Vector2(xh, fwc.y), STEEL)
	ci.draw_rect(Rect2(Vector2(floorf(xh) - 1.0, fwc.y - 1.0), Vector2(3, 3)), BRASS)
	TankDraw.wheel(ci, fwc, 5.0, 4, th, MID, SHADES)
	TankDraw.line_px(ci, Vector2(xh, fwc.y), pin, HI)
	TankDraw.px(ci, pin, BRASS)
	# The hoist: chain links and brass shells rising, one shell spacing a revolution.
	var hx := base.x + 25.0
	var y0 := base.y + 2.0
	var y1 := base.y + rs.size.y - 1.0
	var lift := fposmod(ph, 1.0) * 11.0
	var y := y0
	while y < y1:
		var u := fposmod(y - y0 + lift, 3.0)
		TankDraw.px(ci, Vector2(hx, y), STEEL if u < 1.5 else DK)
		y += 1.0
	for k in 4:
		var sy := y1 - 3.0 - fposmod(k * 11.0 + lift, 44.0)
		if sy < y0 + 5.0:
			continue
		ci.draw_rect(Rect2(Vector2(hx + 1.0, floorf(sy) - 4.0), Vector2(2, 5)), BRASS)
		TankDraw.px(ci, Vector2(hx + 1.0, floorf(sy) - 5.0), STEEL)
		TankDraw.px(ci, Vector2(hx + 1.0, floorf(sy) - 1.0), COPPER)
	# The firebox under the boiler, by the room's far wall.
	var fb := Rect2(base + Vector2(rs.size.x - 7.0, rs.size.y - 11.0), Vector2(6, 9))
	ci.draw_rect(fb, Color(0.12, 0.1, 0.08))
	var fire := firebox_heat(pw)
	var k2 := (0.75 + 0.25 * sin(t * 13.0) * sin(t * 7.3)) * fire
	ci.draw_rect(
		Rect2(fb.position + Vector2(1, 3), Vector2(4, 5)),
		Color(0.4 + 0.6 * fire, 0.45 * k2 + 0.1, 0.1 * fire)
	)
	ci.draw_rect(Rect2(fb.position + Vector2(1, 5), Vector2(4, 2)), Color(1.0, 0.8, 0.4 * k2))


static func firebox_heat(pw: float) -> float:
	return 0.15 + 0.85 * smoothstep(0.0, 1.3, pw)


static func _dynamo(ci: CanvasItem, o: Vector2, ry: Rect2, ph: float, pw: float, t: float) -> void:
	# One big readable silhouette: the armature, a spoked wheel DYNAMO_R px across its rim, turning 3:1
	# on the rider's cadence inside its copper field ring, a brush either side; the jars beside it.
	var arm := ph * float(TankMech.RATIO["dynamo"]) * TAU
	var base := o + ry.position.floor() + shake(pw, t, 3.0)
	var dc := base + DYNAMO_AT
	ci.draw_circle(dc + Vector2(0.5, 1.5), DYNAMO_R + 2.0, Color(0.05, 0.05, 0.04))
	ci.draw_circle(dc + Vector2(0.5, 0.5), DYNAMO_R + 1.5, Color(0.36, 0.17, 0.08))
	var shades: Array[Color] = [Color(0.12, 0.1, 0.07), COPPER, Color(0.95, 0.7, 0.42), BRASS]
	TankDraw.wheel(ci, dc, DYNAMO_R, 6, arm, Color(0.5, 0.26, 0.12), shades)
	for s in [-1.0, 1.0]:
		var bp := dc + Vector2(s * (DYNAMO_R + 2.0), 0)
		ci.draw_rect(Rect2((bp - Vector2(1, 2)).floor(), Vector2(2, 4)), Color(0.1, 0.09, 0.08))
		TankDraw.px(ci, bp - Vector2(0, 2), STEEL)
	ci.draw_rect(Rect2(dc + Vector2(-3, DYNAMO_R + 2.0), Vector2(7, 3)), DK)
	for i2 in JARS:
		var jx := base.x + JAR_X + i2 * 3.0
		var jy := base.y + 21.0
		ci.draw_rect(Rect2(Vector2(jx, jy), Vector2(2, 8)), Color(0.07, 0.08, 0.09))
		ci.draw_rect(Rect2(Vector2(jx, jy), Vector2(1, 8)), Color(0.42, 0.48, 0.5))
		TankDraw.px(ci, Vector2(jx + 1.0, jy - 1.0), BRASS)


static func _arc(ci: CanvasItem, o: Vector2, ra: Rect2, ph: float, pw: float, t: float) -> void:
	# One big readable silhouette: a tall V of copper horns (the Jacob's ladder) on an insulator, the
	# arc climbing it (draw_light); a small magneto wheel turning at its foot.
	var base := o + ra.position.floor() + shake(pw, t, 4.0)
	var fy := ra.size.y
	ci.draw_rect(
		Rect2(base + Vector2(ARC_FOOT - 4.0, fy - 4.0), Vector2(10, 3)), Color(0.6, 0.58, 0.52)
	)
	ci.draw_rect(Rect2(base + Vector2(ARC_FOOT - 4.0, fy - 2.0), Vector2(10, 1)), DK)
	for s in [-1.0, 1.0]:
		var foot := base + Vector2(ARC_FOOT + (0.0 if s < 0.0 else 1.0), fy - 5.0)
		var tip := base + Vector2(ARC_FOOT + 0.5 + s * ARC_SPREAD, 3.0)
		TankDraw.line_px(ci, foot, tip, COPPER)
		TankDraw.line_px(ci, foot + Vector2(s, 0), tip + Vector2(s, 0), Color(0.42, 0.2, 0.09))
		TankDraw.px(ci, tip, Color(0.95, 0.7, 0.42))
	var mc := base + Vector2(5.0, fy - 7.0)
	TankDraw.wheel(ci, mc, 4.0, 4, ph * TAU, MID, SHADES)
	for k4 in 4:
		var a3 := ph * TAU + (k4 + 0.5) * TAU / 4.0
		TankDraw.px(ci, mc + Vector2(cos(a3), sin(a3)) * 4.0, RED)


## The machines' light: firing flashes and hot heads (diesel), the firebox (steam), sparks and the
## charging jars (dynamo), the climbing arc and the coil pulses (arc).
static func draw_light(
	ci: CanvasItem,
	origin: Vector2,
	rooms: Dictionary,
	phase: Dictionary,
	power: Dictionary,
	t: float
) -> void:
	var o := origin.floor()
	if rooms.has("diesel"):
		var rd: Rect2 = rooms["diesel"]
		var pw := float(power.get("diesel", 0.0))
		var heat := smoothstep(0.2, 1.45, pw)
		var e := float(phase.get("diesel", 0.0)) * float(TankMech.RATIO["diesel"])
		for i in 6:
			var x := o.x + floorf(rd.position.x) + 32.5 + i * 9.0
			var y := o.y + floorf(rd.position.y) + 4.0
			var cyc := fposmod(e * 360.0 + DIESEL_FIRING[i], 720.0)
			if cyc < 90.0:
				var k := (1.0 - cyc / 90.0) * (0.25 + 0.6 * heat)
				TankDraw.glow_at(ci, Vector2(x, y), 6.0, Color(1.0, 0.5, 0.15, k))
			TankDraw.glow_at(
				ci, Vector2(x, y - 2.0), 4.0, Color(1.0, 0.3, 0.08, 0.35 * heat * heat)
			)
	if rooms.has("steam"):
		var rs: Rect2 = rooms["steam"]
		var fb := o + rs.position.floor() + Vector2(rs.size.x - 4.0, rs.size.y - 6.0)
		var k1 := (
			(0.8 + 0.2 * sin(t * 11.0))
			* (0.2 + 0.8 * smoothstep(0.0, 1.3, float(power.get("steam", 0.0))))
		)
		TankDraw.glow_at(ci, fb, 12.0 + 8.0 * k1, Color(1.0, 0.45, 0.12, 0.65 * k1))
	if rooms.has("dynamo"):
		_dynamo_light(
			ci,
			o,
			rooms["dynamo"],
			float(phase.get("dynamo", 0.0)),
			float(power.get("dynamo", 0.0)),
			t
		)
	if rooms.has("arc"):
		_arc_light(
			ci, o, rooms["arc"], float(phase.get("arc", 0.0)), float(power.get("arc", 0.0)), t
		)


static func _dynamo_light(
	ci: CanvasItem, o: Vector2, ry: Rect2, ph: float, pw: float, t: float
) -> void:
	var dc := o + ry.position.floor() + DYNAMO_AT + Vector2(0.5, 0.5)
	# Sparks at the brushes, more with the watts.
	for k2 in int(roundf(pw * 4.0)):
		var seed_v := floorf(t * 24.0) + k2 * 13.0
		var s := -1.0 if k2 % 2 == 0 else 1.0
		if TankDraw.hash01(seed_v) > 0.3:
			var dy := floorf(TankDraw.hash01(seed_v + 1.0) * 3.0) - 1.0
			var sp := dc + Vector2(s * (DYNAMO_R + 2.0), dy)
			ci.draw_rect(Rect2(sp.floor(), Vector2.ONE), Color(0.85, 0.92, 1.0, 1.0))
	if pw > 0.1:
		TankDraw.glow_at(
			ci, dc, DYNAMO_R + 4.0 * pw, Color(0.45, 0.55, 1.0, 0.2 + 0.2 * minf(pw, 1.4))
		)
	var cyc2 := fposmod(ph, 1.0)
	var fill := jar_fill(pw, cyc2)
	for i2 in JARS:
		var lvl := clampf(fill * float(JARS) - float(i2), 0.0, 1.0)
		if lvl <= 0.0:
			continue
		var jx := o.x + floorf(ry.position.x) + JAR_X + i2 * 3.0
		var jy := o.y + floorf(ry.position.y) + 29.0
		var hgt := roundf(lvl * 7.0)
		ci.draw_rect(Rect2(Vector2(jx, jy - hgt), Vector2(1, hgt)), Color(0.5, 0.68, 1.0, 0.85))
		TankDraw.glow_at(ci, Vector2(jx + 1.0, jy - 3.0), 5.0, Color(0.4, 0.55, 1.0, 0.3 * lvl))
		# Over band the jars overflow: a spark jumps from the top.
		if pw > 1.18 and lvl >= 1.0 and TankDraw.hash01(floorf(t * 20.0) + i2) > 0.6:
			ci.draw_rect(Rect2(Vector2(jx, jy - 9.0), Vector2.ONE), Color(0.9, 0.95, 1.0))


## How full the capacitor jars are: they charge over 80 % of a crank revolution and discharge.
static func jar_fill(pw: float, cyc: float) -> float:
	var k := cyc / 0.8 if cyc < 0.8 else 1.0 - (cyc - 0.8) / 0.2
	return clampf(pw / 1.15, 0.0, 1.0) * k


static func _arc_light(
	ci: CanvasItem, o: Vector2, ra: Rect2, ph: float, pw: float, t: float
) -> void:
	var base := o + ra.position.floor()
	var fy := ra.size.y
	var strength := smoothstep(0.12, 0.7, pw)
	var reach := 0.15 + 0.85 * smoothstep(0.3, 0.9, pw)
	var climbs := float(TankMech.PARTS["arc"]["ladder_arc_climbs"])
	var climb := fposmod(ph * climbs, 1.0)
	if strength > 0.0 and climb <= reach:
		var ya := lerpf(fy - 6.0, 4.0, climb)
		var f := (fy - 5.0 - ya) / (fy - 8.0)
		var xa := ARC_FOOT - ARC_SPREAD * f + 1.0
		var xb := ARC_FOOT + 1.0 + ARC_SPREAD * f - 1.0
		var seed2 := floorf(t * 30.0)
		var x2 := xa
		while x2 <= xb:
			var j := roundf((TankDraw.hash01(seed2 + x2) - 0.5) * 2.0)
			var bow := sin((x2 - xa) / maxf(xb - xa, 1.0) * PI) * (1.0 + 2.0 * climb)
			var ap := base + Vector2(x2, ya - bow + j)
			ci.draw_rect(Rect2(ap.floor(), Vector2(1, 2)), Color(0.7, 0.8, 1.0, 0.9))
			ci.draw_rect(Rect2(ap.floor(), Vector2.ONE), Color(1.0, 1.0, 1.0, 1.0))
			x2 += 1.0
		var mid := base + Vector2((xa + xb) * 0.5, ya - 1.0)
		TankDraw.glow_at(ci, mid, 12.0 + 8.0 * strength, Color(0.5, 0.6, 1.0, 0.5 * strength))
		TankDraw.glow_at(ci, mid, 4.0, Color(0.9, 0.95, 1.0, 0.8 * strength))
	var a_me := fposmod(ph * TAU + 0.5 * TAU / 4.0 + PI * 0.5, TAU / 4.0)
	var pulse := maxf(0.0, 1.0 - minf(a_me, TAU / 4.0 - a_me) / 0.4)
	if pulse > 0.0 and pw > 0.1:
		var mc := base + Vector2(5.0, fy - 7.0)
		TankDraw.glow_at(ci, mc, 4.0, Color(0.6, 0.7, 1.0, 0.6 * pulse))


## Where the arc climbs this frame (variant px inside the room) or Vector2(-1, -1) when it is out:
## tests and the crackle sound read it.
static func arc_at(ra: Rect2, ph: float, pw: float) -> Vector2:
	var strength := smoothstep(0.12, 0.7, pw)
	var reach := 0.15 + 0.85 * smoothstep(0.3, 0.9, pw)
	var climb := fposmod(ph * float(TankMech.PARTS["arc"]["ladder_arc_climbs"]), 1.0)
	if strength <= 0.0 or climb > reach:
		return Vector2(-1, -1)
	return Vector2(ARC_FOOT + 0.5, lerpf(ra.size.y - 6.0, 4.0, climb))

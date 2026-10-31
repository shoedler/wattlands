class_name TankMechRepair
extends TankMechKit
## The Repairs seat's machine, painted through TankMech.paint_ex. TankMech also forwards its hammer to outsiders.

# A helve hammer, the rivet hammer of the Repairs seat, and the card's hero. The flywheel chains to a small cam
# on its shaft, one turn per crank revolution. The cam's lobe lifts a tappet in its guide, the tappet lifts the
# helve about its pillar (a counterweight rocks on the tail), and at the lobe's drop the forged head falls: one
# stroke, and a rivet set, per crank revolution, its sparks on the strike. The patch plate steps one rivet along
# the anvil per stroke, fed down a chute from the rivet pot. To the right the screw press works its platen on
# the stack. The lamp is a pinker copper than the diesel's. Everything moving is a pure function of the crank
# revolutions.

const R_FW := Vector2(14, 45)
const R_FR := 10.0
const R_HUB := 3.5
const R_CAM := Vector2(46, 40)
const R_CAM_R := 3.0
const R_PIVOT := Vector2(30, 19)
const R_HEAD_X := 76.0
## The helve's end: its height with the head down on the plate, and how far the head lifts.
const R_REST_Y := 32.0
const R_HEAD_LIFT := 15.0
## The tappet's and so the cam's lift (px) at the top of the stroke.
const R_LIFT := R_HEAD_LIFT * (46.0 - 30.0) / (76.0 - 30.0)
const R_ANVIL := Rect2i(64, 47, 24, 10)
const R_PLATE_Y := 45
const R_RIVET_PITCH := 5.0
const R_PRESS_X := 100
const R_LAMP := 60
const R_POT := Rect2i(50, 50, 10, 7)
const R_DIAL := Vector2i(15, 13)
## The room's own wall: the card's plain wall under a pinker wash, so its lamp reads copper, not orange.
const R_WALL_WASH := Color(0.92, 0.9, 1.3)
## The share of a revolution the hammer takes to fall.
const R_FALL := 0.12
## Sparks last this share of a revolution after the strike.
const R_SPARK := 0.2


## The hammer's lift (0 down on the plate .. 1 at the top), a pure function of the crank revolutions: the
## cam raises it through the revolution, it falls at the end and strikes on each whole revolution.
static func hammer_lift(revs: float) -> float:
	var f := fposmod(revs, 1.0)
	var up := 1.0 - R_FALL
	if f < up:
		return smoothstep(0.0, up, f)
	var k := (f - up) / R_FALL
	return 1.0 - k * k


## How long since the strike, in revolutions (0..1): the sparks' clock.
static func since_strike(revs: float) -> float:
	return fposmod(revs, 1.0)


## The press's platen (0 open .. 1 closed), once a revolution, shut as the hammer strikes.
static func press_closed(revs: float) -> float:
	return 0.5 + 0.5 * cos(fposmod(revs, 1.0) * TAU)


static func _repair_static(cv: Cv) -> void:
	_room_static(cv, R_LAMP)
	# the room's pinker wall (the machine, drawn after this, keeps its own iron)
	var data := cv.al
	for j in range(0, data.size(), 4):
		data[j] = mini(int(data[j] * R_WALL_WASH.r), 255)
		data[j + 1] = mini(int(data[j + 1] * R_WALL_WASH.g), 255)
		data[j + 2] = mini(int(data[j + 2] * R_WALL_WASH.b), 255)
	cv.al = data
	# the flywheel on its pedestal
	cv.rect(int(R_FW.x) - 6, 53, 13, 4, IRON[2])
	cv.hl(int(R_FW.x) - 6, int(R_FW.x) + 6, 53, IRON[4])
	cv.vl(int(R_FW.x) + 6, 53, 56, IRON[0])
	_wheel_static(cv, R_FW, R_FR, 3, STEEL)
	# the helve's pillar and its bearing, riveted
	cv.rect(27, 21, 7, 36, IRON[2])
	cv.vl(27, 21, 56, IRON[4])
	cv.vl(28, 21, 56, IRON[3])
	cv.vl(33, 21, 56, IRON[0])
	for y in range(25, 54, 6):
		cv.rivet(30, y)
	cv.rect(24, 53, 13, 4, IRON[3])
	cv.hl(24, 36, 53, IRON[4])
	cv.disc_f(R_PIVOT, 4.0, IRON[2])
	cv.ring_shaded(R_PIVOT.x, R_PIVOT.y, 2.6, 4.0, BRASS)
	# the cam's bearing post with its base, and the tappet's guide on a bracket off the post
	cv.rect(int(R_CAM.x) - 2, int(R_CAM.y), 5, 57 - int(R_CAM.y), IRON[1])
	cv.vl(int(R_CAM.x) - 2, int(R_CAM.y), 56, IRON[3])
	cv.vl(int(R_CAM.x) + 2, int(R_CAM.y), 56, IRON[0])
	cv.rect(int(R_CAM.x) - 7, 53, 15, 4, IRON[2])
	cv.hl(int(R_CAM.x) - 7, int(R_CAM.x) + 7, 53, IRON[4])
	cv.rivet(int(R_CAM.x) - 5, 54)
	cv.rivet(int(R_CAM.x) + 5, 54)
	cv.line_f(R_CAM + Vector2(3, -2), R_CAM + Vector2(6, -9), IRON[2])
	cv.line_f(R_CAM + Vector2(6, -9), R_CAM + Vector2(2, -12), IRON[2])
	cv.rect(int(R_CAM.x) - 2, int(R_CAM.y) - 13, 5, 2, BRASS[1])
	cv.hl(int(R_CAM.x) - 2, int(R_CAM.x) + 2, int(R_CAM.y) - 13, BRASS[2])
	# the anvil: a block on its stump, a horn on the far side
	cv.rect(R_ANVIL.position.x, R_ANVIL.position.y, R_ANVIL.size.x, 4, STEEL[1])
	cv.hl(R_ANVIL.position.x, R_ANVIL.end.x - 1, R_ANVIL.position.y, STEEL[4])
	cv.hl(R_ANVIL.position.x, R_ANVIL.end.x - 1, R_ANVIL.position.y + 1, STEEL[3])
	cv.vl(R_ANVIL.end.x - 1, R_ANVIL.position.y, R_ANVIL.position.y + 3, STEEL[0])
	cv.hl(R_ANVIL.end.x, R_ANVIL.end.x + 3, R_ANVIL.position.y, STEEL[3])
	cv.hl(R_ANVIL.end.x, R_ANVIL.end.x + 1, R_ANVIL.position.y + 1, STEEL[1])
	cv.rect(R_ANVIL.position.x + 5, 51, R_ANVIL.size.x - 10, 6, IRON[1])
	cv.vl(R_ANVIL.position.x + 5, 51, 56, IRON[3])
	cv.vl(R_ANVIL.end.x - 6, 51, 56, IRON[0])
	cv.rect(R_ANVIL.position.x + 2, 55, R_ANVIL.size.x - 4, 2, IRON[2])
	cv.rivet(R_ANVIL.position.x + 7, 52)
	cv.rivet(R_ANVIL.end.x - 8, 52)
	# the pot of rivets and the chute from it up to the plate
	cv.rect(R_POT.position.x, R_POT.position.y, R_POT.size.x, R_POT.size.y, IRON[1])
	cv.hl(R_POT.position.x - 1, R_POT.end.x, R_POT.position.y, IRON[4])
	cv.vl(R_POT.position.x, R_POT.position.y, R_POT.end.y - 1, IRON[3])
	cv.vl(R_POT.end.x - 1, R_POT.position.y, R_POT.end.y - 1, IRON[0])
	cv.line_f(Vector2(R_POT.position.x + 2, 49), Vector2(63, 44), IRON[3])
	cv.line_f(Vector2(R_POT.position.x + 2, 50), Vector2(63, 45), IRON[0])
	# the press: screw frame from the ceiling to the deck, a stack of plates at its foot
	cv.rect(R_PRESS_X - 8, 6, 2, 51, IRON[2])
	cv.vl(R_PRESS_X - 8, 6, 56, IRON[4])
	cv.rect(R_PRESS_X + 7, 6, 2, 51, IRON[1])
	cv.rect(R_PRESS_X - 8, 6, 17, 4, IRON[2])
	cv.hl(R_PRESS_X - 8, R_PRESS_X + 8, 6, IRON[4])
	for k in 5:
		var py := 55 - k * 2
		cv.hl(R_PRESS_X - 5, R_PRESS_X + 5, py, COPPER[2 if k % 2 == 0 else 1])
		cv.hl(R_PRESS_X - 5, R_PRESS_X + 5, py + 1, IRON[0])
		cv.p(R_PRESS_X - 5, py, COPPER[4])
	# the rate dial
	_gauge_face(cv, R_DIAL.x, R_DIAL.y, 5, 0.8)


static func _repair_lights(cv: Cv, pw: float) -> void:
	var heat := 0.3 + 0.7 * smoothstep(0.0, 1.3, pw)
	# the flywheel's own caged lamp, so the crank end reads
	cv.light(R_FW.x + 6.0, 36.0, 24.0, _key * (0.35 * (0.85 + 0.15 * minf(pw, 1.0))))
	cv.light(
		R_POT.position.x + 5, R_POT.position.y - 1, 10.0, Color(1.0, 0.5, 0.42) * (0.1 + 0.2 * heat)
	)
	# the work light over the anvil: the head is what the room is lit for
	cv.light(R_HEAD_X, 26.0, 24.0, Color(0.95, 0.8, 0.8) * 0.3)


static func _repair(cv: Cv, ph: float, pw: float, t: float, slot: Color, rate: float) -> void:
	var heat := _heat(pw)
	var over := _over(pw)
	var th := ph * TAU
	var lift := hammer_lift(ph)
	_lamp(cv, R_LAMP, pw, t, slot)
	# the rivets in the pot glow with the power; one rides the chute each stroke
	for x in range(R_POT.position.x + 2, R_POT.end.x - 1):
		var hot := 0.3 + 0.5 * heat * (0.65 + 0.35 * _h(float(x) + floorf(t * 8.0)))
		cv.p(x, R_POT.position.y + 1, Color(0.3, 0.14, 0.12))
		cv.e(x, R_POT.position.y + 1, Color(1.0, 0.45, 0.28), hot)
	var fr := fposmod(ph, 1.0)
	var ride := Vector2(R_POT.position.x + 2, 48).lerp(Vector2(63, 43), smoothstep(0.1, 0.85, fr))
	cv.rect(roundi(ride.x), roundi(ride.y), 2, 1, Color(0.7, 0.42, 0.3))
	cv.e(roundi(ride.x), roundi(ride.y), Color(1.0, 0.45, 0.28), 0.5)
	# the flywheel, its chain to the cam's sprocket (1:1)
	_spokes(cv, R_FW, R_FR - 2.6, 5, th, STEEL, clampf((rate - 1.7) / 1.3, 0.0, 1.0))
	# the hub: a drawn boss, its highlight, a dark bore; the crank pin a small stud
	cv.disc_f(R_FW, R_HUB, IRON[0])
	cv.disc_f(R_FW + Vector2(-0.4, -0.4), R_HUB - 0.9, BRASS[2])
	cv.disc_f(R_FW + Vector2(-1.3, -1.3), 0.9, BRASS[4])
	cv.disc_f(R_FW, 1.1, IRON[0])
	var pin := R_FW + _dir(th) * (R_FR - 5.0)
	cv.disc_f(pin, 1.5, IRON[0])
	cv.p(roundi(pin.x) - 1, roundi(pin.y) - 1, BRASS[3])
	_chain(cv, R_FW, R_HUB + 0.4, R_CAM, R_HUB + 0.4, ph, 11, 3.0)
	cv.teeth(R_CAM, R_HUB + 0.6, 8, th, BRASS[2])
	# the small cam: a snail with a shaded rim on its shaft; its radius is the hammer's lift round the turn
	var cri := ceili(R_CAM_R + R_LIFT) + 1
	for y in range(int(R_CAM.y) - cri, int(R_CAM.y) + cri + 1):
		for x2 in range(int(R_CAM.x) - cri, int(R_CAM.x) + cri + 1):
			var v := Vector2(x2, y) - R_CAM
			var rho := v.length()
			# the point of the cam on top (angle -90 degrees) has the lift of the moment
			var along := fposmod((v.angle() + PI * 0.5) / TAU - ph, 1.0)
			var rim := R_CAM_R + R_LIFT * hammer_lift(_cam_at(along, ph))
			if rho > rim + 0.4:
				continue
			var lit := (-0.6 * v.x - 0.8 * v.y) / maxf(rho, 0.01)
			var c: Color = STEEL[clampi(1 + roundi(lit * 1.2), 0, 3)]
			if rho > rim - 0.9:
				# a 1 px rim that takes the light, dark on its far side
				c = STEEL[4] if lit > -0.1 else STEEL[0]
			cv.p(x2, y, c)
	cv.disc_f(R_CAM, 1.8, IRON[0])
	cv.disc_f(R_CAM + Vector2(-0.4, -0.4), 1.0, BRASS[3])
	# the tappet riding on the cam, the helve on the tappet, the head on the helve's end
	var end_y := R_REST_Y - R_HEAD_LIFT * lift
	var slope := (end_y - R_PIVOT.y) / (R_HEAD_X - R_PIVOT.x)
	var at_rod := R_PIVOT.y + slope * (R_CAM.x - R_PIVOT.x)
	var rod_low := R_CAM.y - R_CAM_R - R_LIFT * lift
	cv.rect(int(R_CAM.x), roundi(at_rod), 2, maxi(roundi(rod_low - at_rod), 1), STEEL[1])
	cv.vl(int(R_CAM.x), roundi(at_rod), roundi(rod_low), STEEL[3])
	var end := Vector2(R_HEAD_X, end_y)
	# the tail behind the pillar, its counterweight rocking the other way
	var tail := R_PIVOT - Vector2(11.0, 11.0 * slope)
	cv.line_f(R_PIVOT + Vector2(0, 1), tail + Vector2(0, 1), IRON[0])
	cv.line_f(R_PIVOT, tail, LEATHER[2])
	cv.rect(roundi(tail.x) - 3, roundi(tail.y) - 2, 6, 6, IRON[0])
	cv.rect(roundi(tail.x) - 2, roundi(tail.y) - 1, 4, 4, IRON[2])
	cv.hl(roundi(tail.x) - 2, roundi(tail.x) + 1, roundi(tail.y) - 1, IRON[4])
	# the helve: a thick ash beam with iron straps
	for k in 4:
		cv.line_f(
			R_PIVOT + Vector2(0, k - 1),
			end + Vector2(0, k - 2),
			[LEATHER[4], LEATHER[3], LEATHER[2], IRON[0]][k]
		)
	for k2 in 3:
		var q := R_PIVOT.lerp(end, 0.3 + k2 * 0.22)
		cv.vl(roundi(q.x), roundi(q.y) - 2, roundi(q.y) + 1, IRON[3])
	cv.disc_f(R_PIVOT, 1.6, BRASS[4])
	_repair_head(cv, end)
	# the patch plate on the anvil, stepping one rivet along per stroke; the newest rivet is hot
	var step := smoothstep(0.1, 0.5, fposmod(ph, 1.0)) * R_RIVET_PITCH
	cv.rect(56, R_PLATE_Y, 38, 2, COPPER[1])
	cv.hl(56, 93, R_PLATE_Y, COPPER[3])
	var rx := 0.0
	while rx < 40.0:
		var px := int(R_HEAD_X - rx - step + R_RIVET_PITCH)
		if px >= 56 and px < 94:
			cv.p(px, R_PLATE_Y - 1, STEEL[3])
			cv.p(px, R_PLATE_Y, STEEL[4])
		rx += R_RIVET_PITCH
	var since := since_strike(ph)
	var fresh := 1.0 - since / 0.75
	if fresh > 0.0 and pw > 0.05:
		cv.e(int(R_HEAD_X - step + R_RIVET_PITCH), R_PLATE_Y - 1, Color(1.0, 0.5, 0.25), fresh)
	# the strike: sparks fly out from under the head; a shower over power
	if since < R_SPARK and pw > 0.05:
		var k3 := 1.0 - since / R_SPARK
		var n := int(roundf(6.0 + 8.0 * heat + 10.0 * over))
		var st := floorf(ph)
		for i in n:
			var a := -PI * (0.05 + 0.9 * _h(st + float(i) * 1.7))
			var sp := 12.0 + 18.0 * _h(st + float(i) * 3.1)
			var u := since / R_SPARK
			var sq := (
				Vector2(R_HEAD_X, R_PLATE_Y - 1.0) + _dir(a) * sp * u + Vector2(0.0, 9.0 * u * u)
			)
			cv.e(roundi(sq.x), roundi(sq.y), Color(1.0, 0.72, 0.42), k3 * (0.8 + 0.6 * heat))
		cv.glow(
			R_HEAD_X, R_PLATE_Y - 1.0, 13.0, Color(1.0, 0.55, 0.36), 0.5 * k3 * (0.4 + 0.6 * heat)
		)
	# the press: the screw turns, the crosshead comes down on the stack
	var closed := press_closed(ph)
	var ph_y := 20 + roundi(closed * 22.0)
	cv.vl(R_PRESS_X, 2, ph_y, STEEL[2])
	for y2 in range(3, ph_y, 2):
		cv.p(R_PRESS_X, y2 + (1 if fposmod(ph * 2.0, 1.0) > 0.5 else 0), STEEL[4])
	cv.rect(R_PRESS_X - 6, ph_y, 13, 3, IRON[2])
	cv.hl(R_PRESS_X - 6, R_PRESS_X + 6, ph_y, IRON[4])
	cv.hl(R_PRESS_X - 6, R_PRESS_X + 6, ph_y + 2, IRON[0])
	cv.teeth(Vector2(R_PRESS_X, 3), 4.0, 6, th, BRASS[3])
	# the dial, the tag
	_gauge_needle(cv, R_DIAL.x, R_DIAL.y, 5, clampf(rate / 2.0, 0.0, 1.05), over)
	_tag(cv, 4, 4, slot, pw)
	if over > 0.05:
		_vent(cv, Vector2(48, 44), Vector2(0.2, -1.0), over, t, 0.0, Color(0.6, 0.55, 0.52))


## The forged head, the card's hero: a poll with its eye for the helve, a broad banded cheek, a narrow striking
## face, every edge outlined and lit from above.
static func _repair_head(cv: Cv, end: Vector2) -> void:
	var x := int(end.x)
	var y := roundi(end.y)
	# outline
	cv.rect(x - 6, y - 4, 13, 4, IRON[0])
	cv.rect(x - 9, y - 1, 19, 9, IRON[0])
	cv.rect(x - 5, y + 8, 11, 4, IRON[0])
	# the poll, the eye the helve enters
	cv.rect(x - 5, y - 3, 11, 3, STEEL[3])
	cv.hl(x - 5, x + 5, y - 3, STEEL[4])
	cv.rect(x - 2, y - 2, 4, 2, IRON[0])
	# the cheek
	cv.rect(x - 8, y, 17, 7, STEEL[2])
	cv.hl(x - 8, x + 8, y, STEEL[4])
	cv.hl(x - 8, x + 8, y + 1, STEEL[3])
	cv.vl(x - 8, y + 1, y + 6, STEEL[3])
	cv.vl(x + 8, y + 1, y + 6, STEEL[1])
	cv.hl(x - 8, x + 8, y + 6, STEEL[1])
	cv.hl(x - 7, x + 7, y + 4, STEEL[1])
	cv.rivet(x - 6, y + 2)
	cv.rivet(x, y + 2)
	cv.rivet(x + 5, y + 2)
	# the striking face
	cv.rect(x - 4, y + 7, 9, 4, STEEL[2])
	cv.vl(x - 4, y + 7, y + 10, STEEL[3])
	cv.vl(x + 4, y + 7, y + 10, STEEL[1])
	cv.hl(x - 4, x + 4, y + 10, STEEL[4])


## The cam's lift at `along` of the way round from its top: the lift the hammer had `along` of a revolution
## ago, so the point on top always carries the lift of now.
static func _cam_at(along: float, ph: float) -> float:
	return ph - along

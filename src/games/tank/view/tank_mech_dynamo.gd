class_name TankMechDynamo
extends TankMechKit
## The Gun seat's machine (turret traverse and gun charge), painted through TankMech.paint_ex.

# Hero: the dynamo seen end-on, filling the left half: olive field frame with its pole shoes and
# copper field coils, the copper-wound armature turning 3:1, the commutator and two brushes that
# spark with power. The rider's crank pulley hangs from the ceiling bracket (top left) and belts
# the armature from behind. Right: the voltmeter, the traverse motor on the turret ring (edge-on
# along the ceiling, teeth sliding), and four tall capacitor jars that fill with charge once per
# crank revolution and dump it up the bus bar; over power they overflow, arcing jar to jar.

const Y_DC := Vector2(44, 32)
const Y_FR := 22.5
const Y_PUL := Vector2(10, 12)
const Y_PR := 7.0
const Y_LAMP := 70
const Y_RACK_Y := 2
const Y_JX := 72
const Y_JY := 28
const Y_VM := Vector2i(102, 15)


static func _dynamo_static(cv: Cv) -> void:
	_room_static(cv, Y_LAMP)
	# turret ring edge-on along the ceiling, the traverse motor hanging under it
	cv.rect(64, Y_RACK_Y, 48, 3, IRON[2])
	cv.hl(64, 111, Y_RACK_Y, IRON[4])
	cv.hl(64, 111, Y_RACK_Y + 2, IRON[1])
	cv.rect(76, 9, 12, 8, OLIVE[2])
	cv.hl(76, 87, 9, OLIVE[4])
	cv.vl(76, 9, 16, OLIVE[3])
	cv.vl(87, 9, 16, OLIVE[0])
	for y in range(11, 17, 2):
		cv.hl(77, 86, y, OLIVE[1])
	cv.rect(80, 8, 4, 1, STEEL[2])
	# bus bar: frame top -> ceiling -> motor; a tap down to the jars
	cv.rect(43, 5, 2, 5, COPPER[2])
	cv.vl(43, 5, 9, COPPER[3])
	cv.rect(43, 5, 33, 2, COPPER[2])
	cv.hl(43, 75, 5, COPPER[3])
	cv.hl(43, 75, 6, COPPER[1])
	for x in range(50, 74, 8):
		cv.rect(x, 4, 2, 4, Color(0.8, 0.77, 0.68))
	cv.vl(69, 7, 24, COPPER[1])
	cv.hl(69, 108, 24, COPPER[1])
	cv.hl(69, 108, 23, COPPER[3])
	# the jars on their shelf
	cv.rect(68, 50, 44, 2, LEATHER[2])
	cv.hl(68, 111, 50, LEATHER[4])
	cv.rect(70, 52, 2, 5, LEATHER[1])
	cv.rect(108, 52, 2, 5, LEATHER[1])
	for i in 4:
		_jar_static(cv, Y_JX + i * 9, Y_JY)
		cv.vl(Y_JX + 3 + i * 9, 24, Y_JY - 3, COPPER[2])
	# voltmeter
	_gauge_face(cv, Y_VM.x, Y_VM.y, 6, 0.8)
	cv.vl(Y_VM.x, Y_VM.y + 7, 23, COPPER[1])
	# the crank pulley on its ceiling bracket
	cv.line_f(Vector2(4, 3), Y_PUL, IRON[3])
	cv.line_f(Vector2(16, 3), Y_PUL, IRON[3])
	cv.hl(3, 17, 3, IRON[4])
	_wheel_static(cv, Y_PUL, Y_PR, 2, STEEL)
	# cast feet and the field frame
	cv.rect(25, 52, 39, 5, IRON[2])
	cv.hl(25, 63, 52, IRON[4])
	cv.rivet(28, 54)
	cv.rivet(59, 54)
	cv.disc_f(Y_DC, Y_FR, OLIVE[1])
	cv.ring_shaded(Y_DC.x, Y_DC.y, Y_FR - 3.2, Y_FR, OLIVE)
	cv.disc_f(Y_DC, Y_FR - 3.4, Color(0.06, 0.055, 0.045))
	for y2 in range(int(Y_DC.y - Y_FR), int(Y_DC.y + Y_FR) + 1):
		for x2 in range(int(Y_DC.x - Y_FR), int(Y_DC.x + Y_FR) + 1):
			var v := Vector2(x2, y2) - Y_DC
			var d := v.length()
			if d < 15.2 or d > Y_FR - 3.2 or absf(v.x) > d * 0.62:
				continue
			var lit := (-0.6 * v.x - 0.8 * v.y) / d
			if d > 17.2:
				cv.p(x2, y2, IRON[clampi(2 + roundi(lit), 1, 4)])
			else:
				var stripe := int(fposmod(v.angle() * 40.0 / TAU, 2.0))
				cv.p(x2, y2, COPPER[clampi(2 + stripe + roundi(lit * 0.8), 1, 4)])
	for k in 10:
		var bp := Y_DC + _dir(k * TAU / 10.0 + 0.3) * (Y_FR - 1.6)
		cv.rivet(roundi(bp.x), roundi(bp.y))
	# brush rocker arms
	for s: float in [-1.0, 1.0]:
		cv.line_f(
			Vector2(Y_DC.x + s * 7.0, Y_DC.y - 2.0),
			Vector2(Y_DC.x + s * 13.0, Y_DC.y - 13.0),
			BRASS[2]
		)


static func _jar_static(cv: Cv, x: int, y: int) -> void:
	cv.rect(x, y + 2, 7, 19, Color(0.08, 0.085, 0.09))
	cv.vl(x, y + 2, y + 20, GLASS)
	cv.vl(x + 6, y + 2, y + 20, GLASS.darkened(0.4))
	cv.hl(x + 1, x + 5, y + 20, GLASS.darkened(0.3))
	cv.hl(x, x + 6, y + 2, GLASS.darkened(0.2))
	cv.rect(x + 1, y + 12, 5, 8, STEEL[2])
	cv.vl(x + 1, y + 12, y + 19, STEEL[3])
	cv.rect(x + 2, y + 1, 3, 1, LEATHER[1])
	cv.vl(x + 3, y - 2, y + 10, BRASS[2])
	cv.p(x + 3, y - 2, BRASS[4])
	cv.p(x + 1, y + 4, Color(0.85, 0.9, 0.9))
	cv.p(x + 1, y + 5, Color(0.6, 0.66, 0.68))


static func _dynamo(cv: Cv, ph: float, pw: float, t: float, slot: Color, rate: float) -> void:
	var heat := _heat(pw)
	var over := _over(pw)
	var under := _under(pw)
	var th := ph * TAU
	var arm := ph * float(RATIO["dynamo"]) * TAU
	_lamp(cv, Y_LAMP, pw, t, slot)
	# ring teeth slide (3 per crank revolution); the motor's pinion runs the other way
	var rshift := fposmod(ph * 3.0, 1.0) * 3.0
	for x in range(64, W):
		if fposmod(float(x) - rshift, 3.0) < 1.0:
			cv.p(x, Y_RACK_Y + 3, STEEL[3])
	var pshift := fposmod(ph * 9.0, 1.0) * 2.0
	for x2 in range(79, 85):
		if fposmod(float(x2) + pshift, 2.0) < 1.0:
			cv.p(x2, 6, STEEL[4])
			cv.p(x2, 7, STEEL[2])
	# belt from the crank pulley (behind the frame), the pulley and its pedal crank
	_belt(cv, Y_PUL, Y_PR + 0.6, Y_DC, 4.0, ph, 15, 4.6, Y_DC, Y_FR + 0.4)
	_spokes(cv, Y_PUL, Y_PR - 2.0, 4, th, STEEL, clampf((rate - 1.7) / 1.3, 0.0, 1.0))
	var pedal := Y_PUL + _dir(th + PI * 0.5) * 5.0
	cv.thick(Y_PUL, pedal, STEEL[4], STEEL[1])
	cv.rect(roundi(pedal.x) - 2, roundi(pedal.y), 5, 2, IRON[3])
	cv.hl(roundi(pedal.x) - 2, roundi(pedal.x) + 2, roundi(pedal.y), IRON[4])
	cv.disc_f(Y_PUL, 1.2, BRASS[3])
	# armature: 9 copper-wound slots between laminated iron teeth
	var cx := int(Y_DC.x)
	var cy := int(Y_DC.y)
	for y in range(cy - 15, cy + 16):
		for x3 in range(cx - 15, cx + 16):
			var v := Vector2(x3, y) - Y_DC
			var dist := v.length()
			if dist > 14.6 or dist < 4.6:
				continue
			var su := fposmod((v.angle() - arm) * 9.0 / TAU, 1.0)
			var lit := (-0.6 * v.x - 0.8 * v.y) / dist
			if dist > 13.6:
				cv.p(x3, y, IRON[clampi(1 + roundi(lit), 0, 3)] if su >= 0.5 else COPPER[1])
			elif su < 0.52:
				var wind := 1 if int(dist) % 2 == 0 else 0
				cv.p(x3, y, COPPER[clampi(2 + wind + roundi(lit), 1, 4)])
			elif su < 0.58 or su > 0.96:
				cv.p(x3, y, IRON[0])
			else:
				cv.p(x3, y, IRON[clampi(2 + roundi(lit * 1.2), 0, 4)])
	# commutator
	for y2 in range(cy - 4, cy + 5):
		for x4 in range(cx - 4, cx + 5):
			var v2 := Vector2(x4, y2) - Y_DC
			var d2 := v2.length()
			if d2 > 4.4:
				continue
			if d2 < 1.3:
				cv.p(x4, y2, STEEL[3])
				continue
			var su2 := fposmod((v2.angle() - arm) * 9.0 / TAU, 1.0)
			cv.p(x4, y2, LEATHER[0] if su2 < 0.22 else BRASS[2 if v2.y > 0 else 4])
	cv.p(cx, cy, STEEL[4])
	# brushes and their sparks (more with power; a shower over)
	for s2: float in [-1.0, 1.0]:
		var bx := cx + int(s2 * 5.0)
		cv.rect(bx - (1 if s2 < 0 else 0), cy - 1, 2, 3, Color(0.16, 0.16, 0.17))
		cv.rect(cx + int(s2 * 7.0) - (1 if s2 < 0 else 0), cy - 2, 2, 5, BRASS[2])
		cv.p(cx + int(s2 * 7.0), cy - 2, BRASS[4])
		var n := int(roundf(pw * 3.5 + over * 6.0))
		for k2 in n:
			var seed := floorf(t * 24.0) + k2 * 17.0 + s2 * 5.0 + floorf(ph * 36.0)
			if _h(seed) > 0.25 + 0.4 * under:
				var spread := 2.5 + 4.0 * over
				var sp := Vector2(
					bx + s2 * (_h(seed + 1.0) * spread - 1.0),
					Y_DC.y - 2.0 + _h(seed + 2.0) * (4.0 + 3.0 * over)
				)
				cv.e(roundi(sp.x), roundi(sp.y), ARC_CORE, 0.7 + 0.7 * heat)
		if pw > 0.15:
			cv.glow(bx, cy, 3.5 + 2.5 * heat + 3.0 * over, ARC_GLOW, 0.15 + 0.3 * heat + 0.2 * over)
	# capacitor jars: the charge builds over the crank revolution, then dumps up the bus bar
	var cyc := fposmod(ph, 1.0)
	var max_fill := clampf(pw / 1.15, 0.0, 1.0)
	var charge := 0.0
	var dump := 0.0
	if cyc < 0.8:
		charge = cyc / 0.8 * max_fill
	else:
		dump = 1.0 - (cyc - 0.8) / 0.2
		charge = max_fill * dump
	if over > 0.0:
		charge = maxf(charge, max_fill * over)
	for i in 4:
		_jar_fill(cv, Y_JX + i * 9, Y_JY, clampf(charge * 4.0 - float(i), 0.0, 1.0), t + i)
	if dump > 0.0 and max_fill > 0.4:
		for x5 in range(44, 76):
			cv.e(x5, 5, ARC_CORE, dump * max_fill * 0.55)
		cv.e_line(Vector2(69, 23), Vector2(69, 7), ARC_CORE, dump * max_fill * 0.5)
		cv.glow(82, 8, 7.0, ARC_GLOW, dump * max_fill * 0.4)
	# over: the jars overflow, arcing terminal to terminal, sparks dripping off the shelf
	if over > 0.05:
		var seed2 := floorf(t * 20.0)
		for i2 in 3:
			if _h(seed2 + i2 * 7.0) < 0.35 + 0.5 * over:
				var a := Vector2(Y_JX + 3 + i2 * 9, Y_JY - 2)
				var prev := a
				for k3 in range(1, 10):
					var q := (
						a
						+ Vector2(k3, -2.5 * sin(k3 / 9.0 * PI) + (_h(seed2 + k3 + i2) - 0.5) * 2.0)
					)
					cv.e_line(prev, q, ARC_CORE, 1.0)
					prev = q
				cv.glow(a.x + 4.5, a.y - 2.0, 6.0, ARC_GLOW, 0.4 * over)
		for k4 in 5:
			var fall := fposmod(t * 1.6 + k4 * 0.21, 1.0)
			var fx := float(Y_JX) + 2.0 + _h(float(k4) * 3.7 + floorf(t * 1.6 + k4 * 0.21)) * 34.0
			cv.e(roundi(fx), roundi(52.0 + fall * 5.0), Color(0.75, 0.85, 1.0), over * (1.0 - fall))
		# hot varnish fumes from the frame's vents
		_vent(cv, Vector2(27, 18), Vector2(-0.6, -1.0), over, t, 0.0, Color(0.62, 0.62, 0.62))
		_vent(cv, Vector2(61, 18), Vector2(0.6, -1.0), over, t, 0.5, Color(0.62, 0.62, 0.62))
	# voltmeter, tag
	var volt := clampf(pw / 1.4, 0.0, 1.05) * (0.97 + 0.03 * _h(floorf(t * 20.0)))
	_gauge_needle(cv, Y_VM.x, Y_VM.y, 6, volt, over)
	_tag(cv, 90, 18, slot, pw)


static func _jar_fill(cv: Cv, x: int, y: int, fill: float, seed: float) -> void:
	if fill <= 0.0:
		return
	var lvl := roundi(fill * 17.0)
	for yy in range(y + 20 - lvl, y + 20):
		for xx in range(x + 1, x + 6):
			var k := (
				(0.55 + 0.45 * fill) * (0.55 + 0.2 * _h(float(xx + yy * 3) + floorf(seed * 10.0)))
			)
			cv.e(xx, yy, Color(0.5, 0.68, 1.0), k)
	for xx2 in range(x + 2, x + 5):
		cv.e(xx2, y + 20 - lvl, ARC_CORE, 0.8 * fill)
	cv.glow(x + 3, y + 13, 7.0 + 4.0 * fill, Color(0.4, 0.55, 1.0), 0.2 * fill)

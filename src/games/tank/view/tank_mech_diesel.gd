class_name TankMechDiesel
extends TankMechKit
## The Drive seat's machine, painted through TankMech.paint_ex.

# Three inline cylinders cut open: pistons, con-rods and crank throws in the open crankcase; the
# flywheel on the crankshaft's rear end, a chain from the front sprocket down to the gearbox (its
# output shaft goes to the tracks); each firing lights its bore and pops the stack's flapper cap
# with a puff; heads and manifold glow with power; the tacho reads rpm.

const D_FW := Vector2(17, 44)
const D_FR := 13.0
const D_CY := 45.0
const D_R := 6.0
const D_L := 13.0
const D_CX: Array[int] = [45, 61, 77]
const D_THROW: Array[float] = [0.0, 120.0, 240.0]
const D_CYCLE: Array[float] = [0.0, 480.0, 240.0]
const D_SPA := Vector2(92, 45)
const D_SPB := Vector2(103, 50)
const D_LAMP := 68


static func _diesel_static(cv: Cv) -> void:
	_room_static(cv, D_LAMP)
	# gearbox
	cv.rect(95, 38, 17, 19, IRON[2])
	cv.hl(95, 111, 38, IRON[4])
	cv.hl(95, 111, 39, IRON[3])
	cv.vl(95, 38, 56, IRON[3])
	for x in range(97, 111, 4):
		cv.rivet(x, 41)
	cv.rect(106, 31, 2, 7, STEEL[2])
	cv.vl(106, 31, 37, STEEL[3])
	cv.rect(105, 29, 4, 2, BRASS[2])
	cv.hl(105, 108, 29, BRASS[4])
	# output shaft to the tracks
	cv.rect(109, 49, 3, 3, STEEL[2])
	cv.hl(109, 111, 49, STEEL[4])
	# stack (a stub through the ceiling, with a flapper cap) and the manifold
	cv.rect(97, 5, 5, 8, IRON[2])
	cv.vl(98, 5, 12, IRON[4])
	cv.vl(101, 5, 12, IRON[0])
	cv.hl(96, 102, 12, IRON[3])
	cv.rect(40, 8, 61, 4, IRON[2])
	cv.hl(40, 100, 8, IRON[4])
	cv.hl(40, 100, 9, IRON[3])
	cv.hl(40, 100, 11, IRON[0])
	cv.vl(40, 8, 11, IRON[1])
	for x in range(46, 98, 9):
		cv.rect(x, 7, 2, 6, IRON[1])
		cv.p(x, 7, IRON[3])
	for cx: int in D_CX:
		cv.rect(cx + 2, 12, 3, 4, IRON[2])
		cv.vl(cx + 2, 12, 15, IRON[4])
	# block
	cv.rect(37, 23, 49, 18, IRON[2])
	cv.hl(37, 85, 23, IRON[4])
	cv.vl(37, 23, 40, IRON[3])
	cv.vl(85, 23, 40, IRON[1])
	for i in 3:
		var cx3 := D_CX[i]
		cv.rect(cx3 - 7, 16, 14, 7, IRON[2])
		for y in range(17, 23, 2):
			cv.hl(cx3 - 7, cx3 + 6, y, IRON[1])
		cv.hl(cx3 - 7, cx3 + 6, 16, IRON[4])
		cv.vl(cx3 - 7, 16, 22, IRON[3])
		cv.rivet(cx3 - 6, 21)
		cv.rivet(cx3 + 4, 21)
		cv.p(cx3, 15, STEEL[1])
		# the bore, cut open: a lit cylinder wall
		cv.rect(cx3 - 5, 23, 10, 18, Color(0.15, 0.125, 0.10))
		cv.vl(cx3 - 5, 23, 40, Color(0.07, 0.06, 0.05))
		cv.vl(cx3 - 3, 23, 40, Color(0.27, 0.23, 0.19))
		cv.vl(cx3 + 3, 23, 40, Color(0.10, 0.085, 0.07))
		cv.vl(cx3 + 4, 23, 40, Color(0.05, 0.04, 0.035))
	for x: int in [53, 69]:
		cv.vl(x, 24, 40, IRON[3])
		cv.vl(x + 1, 24, 40, IRON[1])
	# crankcase, open at the front; sump with the oil
	cv.rect(35, 41, 53, 12, Color(0.12, 0.10, 0.08))
	cv.vl(35, 41, 52, IRON[4])
	cv.vl(36, 41, 52, IRON[2])
	cv.vl(86, 41, 52, IRON[2])
	cv.vl(87, 41, 52, IRON[0])
	cv.hl(35, 87, 41, IRON[1])
	cv.hl(38, 84, 52, Color(0.10, 0.09, 0.05))
	cv.hl(40, 82, 51, Color(0.05, 0.045, 0.03))
	cv.rect(35, 53, 53, 4, IRON[2])
	cv.hl(35, 87, 53, IRON[4])
	for x2 in range(38, 86, 5):
		cv.rivet(x2, 55)
	for bx: int in [37, 53, 69, 85]:
		cv.rect(bx - 1, int(D_CY) - 2, 3, 5, BRASS[1])
		cv.p(bx - 1, int(D_CY) - 2, BRASS[3])
	# crankshaft: flywheel hub to the front sprocket
	cv.rect(18, int(D_CY) - 1, 76, 3, STEEL[2])
	cv.hl(18, 93, int(D_CY) - 1, STEEL[4])
	cv.hl(18, 93, int(D_CY) + 1, STEEL[1])
	# flywheel, gearbox sprocket, crank sprocket bodies
	_wheel_static(cv, D_FW, D_FR, 3, STEEL)
	cv.rect(int(D_FW.x) - 3, 56, 7, 1, IRON[3])
	cv.disc_f(D_SPB, 5.6, STEEL[1])
	cv.ring_shaded(D_SPB.x, D_SPB.y, 4.4, 6.0, STEEL)
	cv.disc_f(D_SPB, 1.4, BRASS[3])
	cv.disc_f(D_SPA, 3.0, STEEL[2])
	cv.ring_shaded(D_SPA.x, D_SPA.y, 2.0, 3.2, STEEL)
	cv.p(int(D_SPA.x), int(D_SPA.y), BRASS[4])
	# tacho on the wall, its drive cable down to the flywheel hub
	cv.vl(17, 22, 30, Color(0.07, 0.06, 0.05))
	cv.vl(18, 23, 30, Color(0.2, 0.17, 0.13))
	_gauge_face(cv, 17, 13, 7, 0.86)
	_gauge_face(cv, 32, 12, 4, 0.75)


static func _diesel_lights(cv: Cv, pw: float) -> void:
	var mglow := clampf(_heat(pw) * 1.35 - 0.45, 0.0, 1.0)
	cv.light(66, 12, 26.0, Color(1.0, 0.35, 0.1) * (0.5 * mglow))


static func _diesel(cv: Cv, ph: float, pw: float, t: float, slot: Color, rate: float) -> void:
	var heat := _heat(pw)
	var over := _over(pw)
	var under := _under(pw)
	var e := ph * float(RATIO["diesel"])
	var th := e * TAU
	_lamp(cv, D_LAMP, pw, t, slot)
	# manifold and heads glow with heat (hot near the exhaust ports)
	var mglow := clampf(heat * 1.35 - 0.45, 0.0, 1.0)
	if mglow > 0.0:
		for x in range(41, 100):
			var hot := 0.35 + 0.15 * sin(float(x) * 0.5)
			for cx2: int in D_CX:
				hot += 0.9 * maxf(0.0, 1.0 - absf(float(x - cx2 - 3)) / 7.0)
			cv.e(x, 9, Color(0.85, 0.2, 0.04), mglow * 0.4 * hot)
			cv.e(x, 10, Color(0.65, 0.12, 0.03), mglow * 0.35 * hot)
	for i in 3:
		var cx3 := D_CX[i]
		var hg := heat * heat * (0.3 + 0.7 * over)
		if hg > 0.02:
			for x in range(cx3 - 6, cx3 + 6):
				for y in range(18, 23, 2):
					cv.e(x, y, Color(0.95, 0.24, 0.05), hg * (0.55 + 0.45 * _h(float(x * 3 + y))))
		# rocker on its post, tilting with the valve events
		var cyc := fposmod(e * 360.0 + D_CYCLE[i], 720.0)
		var tilt := 0
		if cyc > 540.0 and cyc < 700.0:
			tilt = 1
		elif cyc > 20.0 and cyc < 180.0:
			tilt = -1
		cv.p(cx3 - 3, 14 + tilt, STEEL[3])
		cv.p(cx3 - 2, 14 + (1 if tilt > 0 else 0), STEEL[3])
		cv.p(cx3 - 1, 14, STEEL[3])
		cv.p(cx3, 14, STEEL[4])
		cv.p(cx3 + 1, 14, STEEL[3])
		cv.p(cx3 + 2, 14 + (1 if tilt < 0 else 0), STEEL[3])
		cv.p(cx3 + 3, 14 - tilt, STEEL[3])
	# crank throws, con-rods, pistons; the bore lights up after each firing
	for i in 3:
		var cx4 := float(D_CX[i])
		var a := th + deg_to_rad(D_THROW[i])
		var pin := Vector2(cx4 + D_R * sin(a), D_CY - D_R * cos(a))
		var py := D_CY - (D_R * cos(a) + sqrt(D_L * D_L - D_R * D_R * sin(a) * sin(a)))
		var cw := Vector2(cx4, D_CY) - (pin - Vector2(cx4, D_CY)) * 0.6
		cv.disc_f(cw, 2.4, IRON[1])
		cv.thick(Vector2(cx4, D_CY), pin, IRON[3], IRON[1])
		cv.thick(Vector2(cx4, py), pin, STEEL[4], STEEL[2])
		cv.disc_f(pin, 1.6, STEEL[3])
		cv.p(roundi(pin.x), roundi(pin.y), BRASS[4])
		var top := roundi(py) - 3
		var cyc2 := fposmod(e * 360.0 + D_CYCLE[i], 720.0)
		if cyc2 < 90.0:
			var k := (1.0 - cyc2 / 90.0) * (0.3 + 0.9 * heat)
			for y in range(23, top):
				for x in range(int(cx4) - 4, int(cx4) + 4):
					var c := Color(1.0, 0.85, 0.5).lerp(Color(1.0, 0.38, 0.08), float(y - 23) / 9.0)
					cv.e(x, y, c, k * (0.75 + 0.25 * _h(float(x + y * 7) + floorf(t * 30.0))))
			cv.glow(cx4, 24.0, 9.0, Color(1.0, 0.5, 0.15), 0.3 * k)
		var px0 := int(cx4) - 5
		cv.rect(px0, top, 10, 6, STEEL[3])
		cv.hl(px0, px0 + 9, top, STEEL[4])
		cv.hl(px0, px0 + 9, top + 1, STEEL[1])
		cv.hl(px0, px0 + 9, top + 3, STEEL[1])
		cv.hl(px0, px0 + 9, top + 5, STEEL[2])
		cv.vl(px0, top, top + 5, STEEL[2])
		cv.vl(px0 + 9, top, top + 5, STEEL[1])
		cv.rect(int(cx4) - 1, roundi(py) - 1, 2, 2, BRASS[3])
	# flywheel spokes (smeared at speed) and its timing mark
	var blur := clampf((rate * float(RATIO["diesel"]) - 2.2) / 1.8, 0.0, 1.0)
	_spokes(cv, D_FW, D_FR - 2.6, 8, th, STEEL, blur)
	var tm := D_FW + _dir(th - PI * 0.5) * (D_FR - 1.4)
	cv.rect(roundi(tm.x), roundi(tm.y), 1, 1, BRASS[4])
	# drive chain: crank sprocket (x2) -> gearbox sprocket (x1)
	cv.teeth(D_SPA, 3.6, 8, th, STEEL[3])
	cv.teeth(D_SPB, 6.4, 15, ph * TAU, STEEL[3])
	for k2 in 4:
		var hp := D_SPB + _dir(ph * TAU + k2 * TAU / 4.0) * 3.0
		cv.p(roundi(hp.x), roundi(hp.y), IRON[0])
	_chain(cv, D_SPA, 3.9, D_SPB, 6.9, ph, 15, 3.0)
	# tacho by rpm, tag
	_gauge_needle(cv, 17, 13, 7, clampf(rate * 60.0 / 140.0, 0.0, 1.0), over)
	_gauge_needle(cv, 32, 12, 4, clampf(pw / 1.4, 0.0, 1.05), over)
	_tag(cv, 22, 23, slot, pw)
	# exhaust pulse: the flapper lifts and a puff leaves the stack (three per crank revolution)
	var since := fposmod(e * 360.0 - 200.0, 240.0)
	if since < 80.0:
		cv.p(96, 4, IRON[3])
		cv.p(97, 3, IRON[3])
		cv.p(98, 2, IRON[4])
		cv.p(99, 1, IRON[3])
		if heat > 0.45:
			cv.e(99, 4, Color(1.0, 0.45, 0.1), (heat - 0.45) * 1.2 * (1.0 - since / 80.0))
	else:
		cv.hl(96, 102, 4, IRON[3])
		cv.p(96, 4, IRON[4])
	var smoke := Color(0.5, 0.48, 0.45).lerp(Color(0.18, 0.16, 0.14), maxf(under * 0.5, over * 0.8))
	var dens := 0.35 + 0.1 * under + 0.35 * over + 0.15 * heat
	for k3 in 3:
		var age := (since + 240.0 * k3) / 720.0
		var c2 := Vector2(
			99.0 - age * 22.0 + sin(t * 2.0 + k3) * 0.8, 3.0 - age * 2.0 + under * age * 3.0
		)
		_puff(cv, c2, 1.6 + age * (4.5 + 3.0 * under), smoke, dens * (1.0 - age))
	_vent(cv, Vector2(38, 15), Vector2(-0.4, -1.0), over, t, 0.0, STEAM_WHITE)
	_vent(cv, Vector2(86, 40), Vector2(0.5, -1.0), over, t, 0.5, Color(0.55, 0.53, 0.5))
	if over > 0.1:
		for k4 in 3:
			var s := fposmod(t * 1.7 + k4 * 0.37, 1.0)
			var sp := Vector2(99.0 - s * 12.0 + k4 * 2.0, 3.0 - s * 3.0)
			cv.e(roundi(sp.x), roundi(sp.y), Color(1.0, 0.55, 0.15), over * (1.0 - s))

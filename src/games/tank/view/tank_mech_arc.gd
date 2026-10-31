class_name TankMechArc
extends TankMechKit
## The Lights seat's machine, painted through TankMech.paint_ex.

# Hero: a tall Jacob's ladder filling the middle, its arc climbing twice per crank revolution
# (weak and low under band, doubled and spraying sparks over). Bottom left, the alternator side-on
# (finned housing, rotor poles sliding past its window) driven by the rider's small flywheel; its
# current goes to the induction coil (the interrupter chatters), then to the horns and to the
# carbon arc searchlight (top right, brightness = power, beam out to the right). Bottom right, the
# bow-gun belt feed advances out of the ammo box. Cold key: blue-white light, olive and copper.

const A_FW := Vector2(27, 48)
const A_FR := 6.0
const A_LAMP := 24
const A_LX := 84
const A_LY := 7
const A_HL0 := Vector2(58, 50)
const A_HL1 := Vector2(45, 4)
const A_HR0 := Vector2(62, 50)
const A_HR1 := Vector2(75, 4)
const A_AM := Vector2i(78, 38)


static func _arc_static(cv: Cv) -> void:
	_room_static(cv, A_LAMP)
	var wire := Color(0.08, 0.07, 0.06)
	# wires: alternator -> induction coil -> horns and the lamp
	cv.vl(12, 22, 40, wire)
	cv.hl(12, 37, 22, wire)
	cv.vl(37, 22, 25, wire)
	cv.vl(41, 14, 25, wire)
	cv.hl(41, 83, 14, wire)
	cv.hl(42, 82, 13, Color(0.28, 0.2, 0.12))
	cv.hl(39, 55, 54, wire)
	cv.hl(39, 65, 55, wire)
	# alternator: finned housing, the window onto its rotor, slip-ring end, feet
	cv.rect(3, 41, 18, 15, OLIVE[2])
	cv.hl(3, 20, 41, OLIVE[4])
	cv.hl(3, 20, 55, OLIVE[0])
	for x in range(4, 20, 2):
		cv.vl(x, 42, 54, OLIVE[1])
	cv.rect(6, 44, 11, 9, BRASS[1])
	cv.rect(7, 45, 9, 7, VOID)
	cv.rect(1, 45, 2, 7, COPPER[2])
	cv.vl(1, 45, 51, COPPER[4])
	cv.rect(21, 47, 6, 2, STEEL[2])
	cv.hl(21, 26, 47, STEEL[4])
	_wheel_static(cv, A_FW, A_FR, 2, STEEL)
	# induction coil on its wooden base
	cv.rect(31, 51, 13, 5, LEATHER[2])
	cv.hl(31, 43, 51, LEATHER[4])
	cv.rect(33, 27, 9, 24, COPPER[2])
	for y in range(28, 50):
		cv.hl(33, 41, y, COPPER[3] if y % 2 == 0 else COPPER[1])
		cv.p(33, y, COPPER[1])
		cv.p(34, y, COPPER[4] if y % 2 == 0 else COPPER[2])
		cv.p(41, y, COPPER[0])
	cv.rect(32, 25, 11, 3, BRASS[2])
	cv.hl(32, 42, 25, BRASS[4])
	cv.rect(32, 49, 11, 2, BRASS[1])
	cv.p(35, 24, BRASS[3])
	cv.p(39, 24, BRASS[3])
	# Jacob's ladder: two tall copper horns on a porcelain insulator
	cv.rect(54, 50, 13, 5, Color(0.66, 0.64, 0.58))
	cv.hl(54, 66, 50, Color(0.86, 0.84, 0.77))
	cv.hl(54, 66, 52, Color(0.44, 0.42, 0.38))
	cv.rect(57, 55, 7, 2, IRON[2])
	cv.line_f(A_HL0 + Vector2(-1, 0), A_HL1 + Vector2(-1, 0), COPPER[1])
	cv.line_f(A_HL0, A_HL1, COPPER[4])
	cv.line_f(A_HR0, A_HR1, COPPER[4])
	cv.line_f(A_HR0 + Vector2(1, 0), A_HR1 + Vector2(1, 0), COPPER[1])
	cv.rect(int(A_HL1.x) - 1, int(A_HL1.y) - 1, 3, 2, COPPER[3])
	cv.rect(int(A_HR1.x) - 1, int(A_HR1.y) - 1, 3, 2, COPPER[3])
	# ammeter
	_gauge_face(cv, A_AM.x, A_AM.y, 5, 0.82)
	cv.vl(A_AM.x, A_AM.y + 6, 55, wire)
	# carbon arc searchlight: ribbed drum, chimney, feed knob, lens ring, peek window
	var lx := A_LX
	var ly := A_LY
	cv.rect(lx, ly, 20, 17, IRON[2])
	for y2 in range(ly, ly + 17):
		var u := float(y2 - ly) / 16.0
		var lit := sin(u * PI) * 0.8 + (0.4 - u) * 0.9
		cv.hl(lx, lx + 19, y2, IRON[clampi(1 + roundi(lit * 2.0), 0, 4)])
	for x2 in range(lx + 2, lx + 19, 3):
		cv.vl(x2, ly + 1, ly + 15, IRON[1])
	cv.rect(lx + 7, ly - 4, 5, 4, IRON[2])
	cv.vl(lx + 7, ly - 4, ly - 1, IRON[4])
	cv.rect(lx + 6, ly - 5, 7, 1, IRON[3])
	cv.rect(lx - 2, ly + 7, 2, 3, BRASS[2])
	cv.rect(lx + 20, ly - 1, 3, 19, BRASS[2])
	cv.vl(lx + 20, ly - 1, ly + 17, BRASS[4])
	cv.vl(lx + 22, ly - 1, ly + 17, BRASS[1])
	cv.rect(lx + 3, ly + 17, 2, 4, IRON[2])
	cv.rect(lx + 15, ly + 17, 2, 4, IRON[2])
	var wx := lx + 4
	var wy := ly + 5
	cv.rect(wx - 1, wy - 1, 13, 9, BRASS[1])
	cv.hl(wx - 1, wx + 11, wy - 1, BRASS[3])
	cv.rect(wx, wy, 11, 7, VOID)
	cv.rect(wx, wy + 3, 4, 1, Color(0.2, 0.2, 0.21))
	cv.rect(wx + 6, wy + 3, 5, 1, Color(0.2, 0.2, 0.21))
	# ammo box and the feed sprocket's bracket
	cv.rect(86, 44, 16, 13, OLIVE[2])
	cv.hl(86, 101, 44, OLIVE[4])
	cv.vl(86, 44, 56, OLIVE[3])
	cv.vl(101, 44, 56, OLIVE[0])
	cv.rect(88, 48, 12, 1, OLIVE[1])
	cv.rect(92, 42, 4, 2, IRON[3])
	for x3 in range(88, 101, 4):
		cv.rivet(x3, 53)
	cv.disc_f(Vector2(105, 41), 2.8, STEEL[2])
	cv.ring_shaded(105.0, 41.0, 1.8, 3.0, STEEL)
	cv.rect(104, 44, 3, 13, IRON[2])


static func _arc(cv: Cv, ph: float, pw: float, t: float, slot: Color, rate: float) -> void:
	var heat := _heat(pw)
	var over := _over(pw)
	var under := _under(pw)
	var th := ph * TAU
	_lamp(cv, A_LAMP, pw, t, slot)
	# alternator: rotor poles slide past the window (9 px per crank revolution), the flywheel
	var shift := ph * 9.0
	for y in range(45, 52):
		var u := fposmod(float(y) - shift, 4.0)
		var c := COPPER[3] if u < 1.0 else (COPPER[1] if u < 2.0 else IRON[1])
		for x in range(7, 16):
			cv.p(x, y, c)
	cv.vl(7, 45, 51, Color(0.05, 0.05, 0.05))
	var blur := clampf((rate - 1.7) / 1.3, 0.0, 1.0)
	_spokes(cv, A_FW, A_FR - 1.6, 3, th, STEEL, blur)
	cv.disc_f(A_FW, 1.4, BRASS[3])
	if pw > 0.1 and _h(floorf(t * 30.0)) < 0.3 + 0.6 * heat:
		cv.e(2, 46 + int(_h(floorf(t * 30.0) + 1.0) * 5.0), ARC_CORE, 0.6 + 0.6 * heat)
	# induction coil's interrupter chatters
	var chatter := 1 if (pw > 0.1 and _h(floorf(t * 40.0)) < 0.5 + 0.4 * heat) else 0
	cv.rect(39, 46 - chatter, 2, 3, STEEL[4])
	if chatter == 1 and pw > 0.3:
		cv.e(39, 49, ARC_CORE, 0.7 * heat)
		cv.glow(39, 49, 2.5, ARC_GLOW, 0.3 * heat)
	# Jacob's ladder: the arc climbs twice per crank revolution (doubled when over)
	var strength := smoothstep(0.12, 0.7, pw)
	var reach := 0.25 + 0.75 * smoothstep(0.3, 0.9, pw)
	var arcs := 2 if over > 0.3 else 1
	for ai in arcs:
		var climb := fposmod(ph * 2.0 + float(ai) * 0.5, 1.0)
		if strength <= 0.0 or climb > reach + 0.02:
			continue
		var hk := minf(climb, reach)
		var y_arc := lerpf(47.0, 7.0, hk)
		var f := (A_HL0.y - y_arc) / (A_HL0.y - A_HL1.y)
		var xa := lerpf(A_HL0.x, A_HL1.x, f) + 1.0
		var xb := lerpf(A_HR0.x, A_HR1.x, f) - 1.0
		var seed := floorf(t * 30.0) + floorf(ph * 48.0) * 7.0 + ai * 31.0
		var prev := Vector2(xa, y_arc)
		var bow := 0.5 + 4.0 * hk
		var steps := maxi(int(xb - xa), 2)
		for i in range(1, steps + 1):
			var fr := float(i) / steps
			var jit := (_h(seed + i * 3.1) - 0.5) * (1.0 + 2.5 * hk)
			var q := Vector2(lerpf(xa, xb, fr), y_arc - sin(fr * PI) * bow + jit)
			cv.e_line(prev, q, ARC_CORE, 0.9 + 0.6 * heat)
			if over > 0.3:
				cv.e_line(prev + Vector2(0, 1), q + Vector2(0, 1), ARC_GLOW, 0.6 * over)
			prev = q
		var mid := Vector2((xa + xb) * 0.5, y_arc - bow)
		cv.glow(
			mid.x, mid.y, 7.0 + 8.0 * strength + 6.0 * over, ARC_GLOW, 0.35 * strength + 0.25 * over
		)
		if over > 0.3 and hk > 0.7:
			for k in 6:
				var sp := Vector2(
					xa + _h(seed + k) * (xb - xa), y_arc - bow - _h(seed + k + 9.0) * 5.0
				)
				cv.e(roundi(sp.x), roundi(sp.y), ARC_CORE, over)
	if strength > 0.0:
		cv.glow(60, 48, 3.0, ARC_GLOW, 0.25 * strength)
	if under > 0.5 and _h(floorf(t * 7.0)) < 0.4:
		cv.e(60, 48, ARC_CORE, 0.7)
	# carbon arc searchlight: the arc between the carbon tips; the lens and the beam to the right
	var lamp := clampf(pw / 1.2, 0.0, 1.3) * (0.92 + 0.08 * _h(floorf(t * 25.0)))
	var wx := A_LX + 4
	var wy := A_LY + 5
	if pw > 0.05:
		var tips := Color(1.0, 0.95, 0.85)
		cv.e(wx + 4, wy + 3, tips, 0.5 + 0.8 * lamp)
		cv.e(wx + 5, wy + 3, ARC_CORE, 0.7 + 1.0 * lamp)
		cv.e(wx + 5, wy + 2, ARC_GLOW, 0.5 * lamp)
		cv.e(wx + 6, wy + 3, tips, 0.5 + 0.6 * lamp)
		cv.glow(wx + 5, wy + 3, 4.0 + 3.0 * lamp, Color(0.85, 0.9, 1.0), 0.35 * lamp)
		for y3 in range(A_LY, A_LY + 17):
			var k3 := 1.0 - absf(float(y3 - A_LY - 8)) / 9.0
			cv.e(A_LX + 21, y3, Color(0.92, 0.95, 1.0), lamp * 0.8 * k3)
		for x2 in range(A_LX + 23, W):
			var dx := float(x2 - A_LX - 23)
			var half := 8.0 + dx * 0.5
			for y4 in range(roundi(A_LY + 8 - half), roundi(A_LY + 8 + half) + 1):
				var dy := absf(float(y4) - (A_LY + 8.0)) / half
				cv.e(x2, y4, Color(0.75, 0.82, 1.0), lamp * 0.3 * (1.0 - dy) * (1.0 - dx / 12.0))
	# belt feed: sprocket teeth and the cartridges advancing (4 per crank revolution)
	cv.teeth(Vector2(105, 41), 3.6, 4, th, STEEL[4])
	cv.p(105, 41, BRASS[3])
	var bshift := fposmod(ph * 12.0, 3.0)
	for i2 in 9:
		var s := float(i2) * 3.0 + bshift
		var bp := Vector2.ZERO
		if s < 7.0:
			bp = Vector2(99.0 + s * 0.5, 45.0 - s * 0.6)
		else:
			bp = Vector2(102.5 + (s - 7.0), 37.5)
		if bp.x > 111.0:
			continue
		var bi := Vector2i(roundi(bp.x), roundi(bp.y))
		cv.rect(bi.x, bi.y - 3, 1, 4, BRASS[3])
		cv.p(bi.x, bi.y - 4, COPPER[3])
		cv.p(bi.x, bi.y + 1, STEEL[2])
	# ammeter, tag
	_gauge_needle(cv, A_AM.x, A_AM.y, 5, clampf(pw / 1.4, 0.0, 1.05), over)
	_tag(cv, 4, 4, slot, pw)
	# over: the alternator runs hot, vapour off its fins
	if over > 0.05:
		_vent(cv, Vector2(8, 40), Vector2(-0.3, -1.0), over, t, 0.0, Color(0.85, 0.86, 0.88))
		_vent(cv, Vector2(16, 40), Vector2(0.3, -1.0), over, t, 0.4, Color(0.85, 0.86, 0.88))


static func _arc_lights(cv: Cv, pw: float) -> void:
	var lamp := clampf(pw / 1.2, 0.0, 1.3)
	cv.light(A_LX + 10, A_LY + 8, 34.0, Color(0.55, 0.65, 1.0) * (0.7 * lamp))
	cv.light(60, 28, 30.0, Color(0.45, 0.55, 1.0) * (0.5 * smoothstep(0.12, 0.7, pw)))

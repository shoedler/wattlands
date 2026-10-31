class_name TankMechSteam
extends TankMechKit
## The Loader seat's machine, painted through TankMech.paint_ex.

# Cool key: grey-green iron, brass and white steam. A vertical boiler over its firebox (fire =
# power) with the pressure gauge, sight glass and a lever safety valve (it lifts and blows when
# over); the steam pipe and throttle to the cylinder (cut open: the piston), piston rod, crosshead
# in its guides, con-rod to the flywheel; a chain from the flywheel shaft drives the wide shell
# hoist on the right, which lifts big brass shells up to the turret, one per crank revolution.

const GIRON: Array[Color] = [
	Color(0.08, 0.10, 0.095),
	Color(0.17, 0.20, 0.185),
	Color(0.28, 0.32, 0.29),
	Color(0.41, 0.46, 0.41),
	Color(0.58, 0.64, 0.57)
]
const S_FW := Vector2(66, 34)
const S_FR := 10.0
const S_CR := 4.0
const S_L := 16.0
const S_ROD := 15.0
const S_HS := Vector2(97, 50)
const S_HR := 7.0
const S_BX := 2
const S_BW := 20
const S_LAMP := 48
const S_FX := 7
const S_FY := 47
const S_SHELL := 22.0


static func _steam_static(cv: Cv) -> void:
	_room_static(cv, S_LAMP)
	var bx := S_BX
	var bw := S_BW
	# hoist shaft: dark well between two rails, cross braces
	cv.rect(84, 3, 26, 54, Color(0.06, 0.07, 0.065))
	cv.vl(83, 3, 56, GIRON[3])
	cv.vl(82, 3, 56, GIRON[0])
	cv.vl(110, 3, 56, GIRON[3])
	cv.vl(111, 3, 56, GIRON[1])
	cv.rect(82, 2, 30, 1, GIRON[4])
	for y in range(8, 54, 12):
		cv.rivet(82, y)
		cv.rivet(110, y)
	# the shaft lamp (cage and bulb)
	cv.rect(95, 3, 5, 1, BRASS[2])
	cv.p(95, 4, STEEL[2])
	cv.p(99, 4, STEEL[2])
	cv.hl(96, 98, 5, Color(1.0, 0.95, 0.8))
	# boiler barrel, shaded round, brass bands
	for x in range(bx, bx + bw):
		var u := float(x - bx) / float(bw - 1)
		var lit := sin(u * PI) * 0.8 + (0.5 - u) * 0.7
		cv.vl(x, 11, 41, GIRON[clampi(1 + roundi(lit * 2.0), 0, 4)])
	for x2 in range(bx + 2, bx + bw - 2):
		cv.p(x2, 9, GIRON[2])
		cv.p(x2, 10, GIRON[3] if x2 < bx + 11 else GIRON[2])
	cv.hl(bx + 4, bx + bw - 5, 8, GIRON[3])
	for yb: int in [11, 26, 40]:
		cv.hl(bx, bx + bw - 1, yb, BRASS[2])
		for x3 in range(bx + 1, bx + bw - 1, 3):
			cv.p(x3, yb, BRASS[4])
	# sight glass frame and the gauge (with its siphon loop)
	cv.rect(bx + 15, 28, 3, 11, BRASS[2])
	cv.vl(bx + 15, 28, 38, BRASS[4])
	cv.vl(bx + 16, 29, 37, Color(0.1, 0.12, 0.12))
	_gauge_face(cv, bx + 8, 19, 5, 0.82)
	cv.p(bx + 8, 25, BRASS[2])
	cv.p(bx + 9, 26, BRASS[2])
	# firebox, its small fire door window, the door swung open
	cv.rect(bx - 1, 42, bw + 2, 14, GIRON[2])
	cv.hl(bx - 1, bx + bw, 42, GIRON[4])
	for x4 in range(bx + 1, bx + bw, 4):
		cv.rivet(x4, 44)
	cv.rect(S_FX - 1, S_FY - 1, 12, 7, GIRON[3])
	cv.rect(S_FX, S_FY, 10, 5, VOID)
	cv.rect(S_FX - 4, S_FY - 1, 3, 7, GIRON[2])
	cv.vl(S_FX - 4, S_FY - 1, S_FY + 5, GIRON[4])
	cv.rect(bx, 55, bw, 2, GIRON[0])
	# safety valve body on the dome; steam pipe with the throttle wheel to the steam chest
	cv.rect(bx + 6, 5, 3, 3, BRASS[2])
	cv.p(bx + 6, 5, BRASS[4])
	cv.p(bx + 3, 5, STEEL[1])
	cv.rect(bx + bw - 1, 6, 15, 3, BRASS[1])
	cv.hl(bx + bw - 1, bx + bw + 13, 6, BRASS[3])
	cv.rect(bx + bw + 11, 6, 3, 19, BRASS[1])
	cv.vl(bx + bw + 11, 6, 24, BRASS[3])
	cv.ring_shaded(28.0, 7.0, 1.5, 3.0, BRASS)
	cv.p(28, 7, BRASS[1])
	# cylinder (cut open) with its steam chest, gland, guides
	var cy := int(S_FW.y)
	cv.rect(26, cy - 6, 18, 13, GIRON[2])
	cv.hl(26, 43, cy - 6, GIRON[4])
	cv.hl(26, 43, cy + 6, GIRON[0])
	cv.rect(30, cy - 10, 11, 4, GIRON[2])
	cv.hl(30, 40, cy - 10, GIRON[4])
	cv.rect(26, cy - 6, 2, 13, GIRON[3])
	cv.rect(42, cy - 6, 2, 13, GIRON[1])
	cv.rect(28, cy - 3, 14, 7, VOID)
	cv.hl(28, 41, cy - 3, Color(0.15, 0.17, 0.16))
	for x5 in range(27, 43, 4):
		cv.rivet(x5, cy - 5)
		cv.rivet(x5, cy + 5)
	cv.rect(44, cy - 2, 2, 4, BRASS[2])
	cv.p(44, cy - 2, BRASS[4])
	cv.hl(46, 55, cy - 4, STEEL[4])
	cv.hl(46, 55, cy - 3, STEEL[1])
	cv.hl(46, 55, cy + 3, STEEL[3])
	cv.hl(46, 55, cy + 4, STEEL[1])
	cv.rect(29, cy + 7, 2, 16, GIRON[2])
	cv.rect(39, cy + 7, 2, 16, GIRON[2])
	# drain cocks under the cylinder
	cv.p(28, cy + 7, BRASS[3])
	cv.p(41, cy + 7, BRASS[3])
	# flywheel pedestal and wheel; the hoist's bottom sprocket body
	cv.rect(63, 43, 7, 14, GIRON[2])
	cv.vl(63, 43, 56, GIRON[4])
	cv.vl(69, 43, 56, GIRON[0])
	cv.rect(60, 54, 13, 3, GIRON[2])
	cv.hl(60, 72, 54, GIRON[4])
	_wheel_static(cv, S_FW, S_FR, 2, STEEL)
	cv.disc_f(S_HS, S_HR - 1.0, GIRON[1])
	cv.ring_shaded(S_HS.x, S_HS.y, S_HR - 2.0, S_HR, STEEL)
	cv.disc_f(S_HS, 3.0, GIRON[3])
	_tag(cv, 24, 12, Color(0.3, 0.3, 0.3), 0.0)


static func _steam(cv: Cv, ph: float, pw: float, t: float, slot: Color, rate: float) -> void:
	var heat := _heat(pw)
	var over := _over(pw)
	var th := ph * TAU
	var bx := S_BX
	_lamp(cv, S_LAMP, pw, t, slot)
	# hoist: the up-run carries the shells, the down-run returns empty hooks
	var lift := fposmod(ph, 1.0) * S_SHELL
	for y in range(3, int(S_HS.y)):
		var u := fposmod(float(y) + lift, 4.0)
		cv.p(90, y, STEEL[4] if u < 1.5 else (STEEL[2] if u < 3.0 else IRON[0]))
		cv.p(91, y, STEEL[2] if u < 1.5 else IRON[0])
		var u2 := fposmod(float(y) - lift, 4.0)
		cv.p(104, y, STEEL[3] if u2 < 1.5 else (STEEL[1] if u2 < 3.0 else IRON[0]))
		var hk := fposmod(float(y) - lift, S_SHELL)
		if hk < 1.0:
			cv.p(103, y, STEEL[3])
			cv.p(102, y + 1, STEEL[2])
	cv.teeth(S_HS, S_HR + 0.6, 15, th, STEEL[4])
	for k in 4:
		var sy := S_HS.y - 8.0 - fposmod(float(k) * S_SHELL + lift, 4.0 * S_SHELL)
		var base := roundi(sy)
		if base < 0 or base > 52:
			continue
		# cradle
		cv.hl(90, 99, base + 1, STEEL[4])
		cv.p(99, base, STEEL[3])
		# brass case
		cv.rect(92, base - 8, 6, 9, BRASS[3])
		cv.vl(92, base - 8, base, BRASS[4])
		cv.vl(93, base - 8, base, BRASS[4])
		cv.vl(97, base - 8, base, BRASS[1])
		cv.hl(92, 97, base, BRASS[2])
		cv.hl(91, 98, base - 1, BRASS[2])
		# copper driving band, grey-green projectile with its pointed nose
		cv.hl(92, 97, base - 9, COPPER[3])
		cv.rect(92, base - 14, 6, 5, GIRON[3])
		cv.vl(92, base - 14, base - 10, GIRON[4])
		cv.vl(97, base - 14, base - 10, GIRON[1])
		cv.hl(93, 96, base - 15, GIRON[3])
		cv.hl(94, 95, base - 16, GIRON[4])
	# chain from the flywheel shaft's sprocket to the hoist sprocket's small wheel
	_chain(cv, S_FW, 3.4, S_HS, 3.4, ph, 4, 3.0)
	cv.disc_f(S_HS, 2.6, STEEL[2])
	cv.teeth(S_HS, 3.3, 7, th, STEEL[4])
	cv.p(int(S_HS.x), int(S_HS.y), BRASS[4])
	# flywheel spokes, the shaft sprocket over the hub
	var blur := clampf((rate - 1.7) / 1.3, 0.0, 1.0)
	_spokes(cv, S_FW, S_FR - 2.0, 4, th, STEEL, blur)
	cv.disc_f(S_FW, 2.6, STEEL[2])
	cv.teeth(S_FW, 3.3, 7, th, STEEL[4])
	cv.p(int(S_FW.x), int(S_FW.y), BRASS[4])
	# water level (bobs with the strokes; lower when worked hard)
	var wl := 32 + roundi(sin(th * 2.0) * 0.7 + (1.0 - minf(pw, 1.3)) * 2.5)
	for y3 in range(wl, 38):
		cv.p(bx + 16, y3, Color(0.42, 0.58, 0.64))
	cv.p(bx + 16, wl, Color(0.75, 0.88, 0.9))
	_gauge_needle(cv, bx + 8, 19, 5, clampf(pw / 1.4, 0.0, 1.05), over)
	_tag(cv, 24, 12, slot, pw)
	# the fire (brightness = power) behind the grate bars, a small window in a cool room
	var fire := 0.3 + 0.7 * smoothstep(0.0, 1.3, pw)
	for y4 in range(S_FY, S_FY + 5):
		for x in range(S_FX, S_FX + 10):
			var n := _h(float(x * 13 + y4 * 7) + floorf(t * 12.0) * 3.1)
			var depth := float(y4 - S_FY) / 4.0
			var f := clampf(fire * (0.45 + 0.8 * depth) + (n - 0.5) * 0.55, 0.0, 1.4)
			if f < 0.16:
				continue
			var c := Color(0.5, 0.08, 0.02).lerp(Color(1.0, 0.45, 0.08), clampf(f, 0.0, 1.0))
			if f > 1.0:
				c = c.lerp(Color(1.0, 0.92, 0.65), (f - 1.0) * 2.0)
			cv.p(x, y4, c * 0.5)
			cv.e(x, y4, c, 0.3 + 0.65 * f)
	for x2 in range(S_FX + 2, S_FX + 10, 3):
		cv.vl(x2, S_FY, S_FY + 4, Color(0.07, 0.06, 0.05))
	cv.glow(S_FX + 5, S_FY + 3, 7.0 + 5.0 * fire, Color(1.0, 0.4, 0.1), 0.22 * fire)
	# safety valve lever: lifts when over (the weight rises), and the valve roars
	var tip := 2 if over > 0.3 else 0
	cv.line_f(Vector2(bx + 3, 4), Vector2(bx + 17, 4 - tip), STEEL[4])
	cv.rect(bx + 16, 3 - tip, 3, 3, GIRON[3])
	cv.p(bx + 16, 3 - tip, GIRON[4])
	# piston, rod, crosshead, con-rod
	var pin := S_FW + _dir(th) * S_CR
	var xh := pin.x - sqrt(S_L * S_L - pow(pin.y - S_FW.y, 2.0))
	var xp := xh - S_ROD
	var cy := int(S_FW.y)
	var pxi := roundi(xp)
	var xhi := roundi(xh)
	cv.rect(pxi - 1, cy - 3, 3, 7, BRASS[2])
	cv.vl(pxi - 1, cy - 3, cy + 3, BRASS[4])
	cv.vl(pxi + 1, cy - 3, cy + 3, BRASS[1])
	cv.rect(pxi + 2, cy - 1, xhi - pxi - 2, 2, STEEL[3])
	cv.hl(pxi + 2, xhi, cy - 1, STEEL[4])
	cv.rect(44, cy - 2, 2, 4, BRASS[2])
	cv.p(44, cy - 2, BRASS[4])
	cv.rect(xhi - 2, cy - 2, 4, 5, BRASS[2])
	cv.hl(xhi - 2, xhi + 1, cy - 2, BRASS[4])
	cv.vl(xhi + 1, cy - 2, cy + 2, BRASS[1])
	cv.p(xhi, cy, STEEL[4])
	cv.thick(Vector2(xh, S_FW.y), pin, STEEL[4], STEEL[1])
	cv.disc_f(pin, 1.5, BRASS[2])
	cv.p(roundi(pin.x), roundi(pin.y), BRASS[4])
	# live steam: a thin wisp at the gland in band, the drain cocks spitting and the safety
	# valve blowing when over
	var stroke := fposmod(ph * 2.0, 1.0)
	if heat > 0.3:
		var wa := fposmod(t * 1.3, 1.0)
		_puff(
			cv,
			Vector2(45.0 + wa * 3.0, cy - 3.0 - wa * 5.0),
			0.8 + wa * 1.6,
			STEAM_WHITE,
			0.45 * heat * (1.0 - wa)
		)
	if over > 0.05:
		for k2 in 6:
			var age := fposmod(t * 2.4 + k2 / 6.0, 1.0)
			var c2 := Vector2(bx + 8.0 + age * 12.0 + sin(t * 3.0 + k2) * 1.2, 3.0 - age * 2.0)
			_puff(cv, c2, 1.6 + age * 5.0, STEAM_WHITE, over * 0.85 * (1.0 - age * 0.8))
		var sa := fposmod(stroke * 2.0, 1.0)
		for side: float in [28.0, 41.0]:
			var on := 1.0 if (side < 30.0) == (stroke < 0.5) else 0.45
			var dc := Vector2(side, cy + 8.0)
			_puff(
				cv,
				dc + Vector2((side - 34.5) * 0.25 * sa, sa * 6.0),
				1.5 + sa * 4.0,
				STEAM_WHITE,
				over * 0.9 * on * (1.0 - sa * 0.8)
			)


static func _steam_lights(cv: Cv, pw: float) -> void:
	var fire := 0.3 + 0.7 * smoothstep(0.0, 1.3, pw)
	cv.light(S_FX + 5, S_FY + 3, 10.0 + 12.0 * fire, Color(1.0, 0.5, 0.2) * (0.2 + 0.5 * fire))
	# the hoist's own caged lamp at the top of the shaft
	cv.light(97, 5, 34.0, _key * (0.75 * (0.85 + 0.15 * minf(pw, 1.0))))

class_name TankMechFeed
extends TankMechKit
## The Secondaries seat's machine, painted through TankMech.paint_ex.

# The crank-driven twin belt feed of the two bow guns. The rider's flywheel (left) drives a chain up
# to the brass feed drum; the drum turns the feed shaft between the two gun lines, whose sprockets
# pull both linked belts up out of their ammo boxes and into the two receivers at the wall (upper
# and lower bow gun), whose bolts cycle in turn. Each crank revolution feeds exactly
# TankFeedState.ROUNDS_PER_REV rounds (one per belt, the belts half a revolution apart, so the guns
# alternate): each belt advances one cartridge pitch, each bolt strokes once, a flash at the
# receiver and a spent casing drops down the chute. A round counter steps per round, a dial reads
# the rate. Warm brass key, olive boxes.

const F_FW := Vector2(15, 45)
const F_FR := 11.0
const F_CS := 3.5
const F_DRUM := Vector2(56, 15)
const F_DR := 7.5
const F_LAMP := 36
## The belts: up from each box's mouth to its gun line, then right into its receiver.
const F_BELT_X: Array[int] = [70, 87]
const F_BELT_Y0 := 43
const F_GUN_Y: Array[int] = [8, 22]
const F_SHAFT_Y := 15
const F_RECV_X := 97
const F_PITCH := 4.0
const F_DIAL := Vector2i(40, 47)


static func _feed_static(cv: Cv) -> void:
	_room_static(cv, F_LAMP)
	# the flywheel on its pedestal
	cv.rect(10, 53, 11, 4, IRON[2])
	cv.hl(10, 20, 53, IRON[4])
	cv.vl(20, 53, 56, IRON[0])
	_wheel_static(cv, F_FW, F_FR, 3, STEEL)
	# the feed drum's bracket from the ceiling beam, the drum's web and its brass rim
	cv.rect(int(F_DRUM.x) - 1, 3, 3, 6, IRON[2])
	cv.vl(int(F_DRUM.x) - 1, 3, 8, IRON[4])
	cv.disc_f(F_DRUM, F_DR, IRON[1])
	cv.ring_shaded(F_DRUM.x, F_DRUM.y, F_DR - 2.0, F_DR, BRASS)
	cv.disc_f(F_DRUM, 2.2, STEEL[2])
	# the feed shaft between the gun lines, out to the receivers
	cv.rect(int(F_DRUM.x), F_SHAFT_Y - 1, F_RECV_X - int(F_DRUM.x), 3, STEEL[1])
	cv.hl(int(F_DRUM.x), F_RECV_X - 1, F_SHAFT_Y - 1, STEEL[3])
	cv.hl(int(F_DRUM.x), F_RECV_X - 1, F_SHAFT_Y + 1, STEEL[0])
	# the guide channels the belts run in
	for k in 2:
		var bx := F_BELT_X[k]
		var gy := F_GUN_Y[k]
		cv.vl(bx - 4, gy + 3, 43, IRON[0])
		cv.vl(bx + 5, gy + 3, 43, IRON[2])
		cv.hl(bx + 5, F_RECV_X - 1, gy + 3, IRON[2])
		cv.hl(bx - 4, F_RECV_X - 1, gy - 3, IRON[0])
	# the ammo boxes (olive, a stencilled band, a brass latch)
	for bx2: int in [62, 79]:
		cv.rect(bx2, 44, 16, 13, OLIVE[2])
		cv.hl(bx2, bx2 + 15, 44, OLIVE[4])
		cv.vl(bx2, 44, 56, OLIVE[3])
		cv.vl(bx2 + 15, 44, 56, OLIVE[0])
		cv.hl(bx2 + 1, bx2 + 14, 50, OLIVE[1])
		cv.rect(bx2 + 6, 47, 4, 2, BRASS[2])
		cv.p(bx2 + 7, 47, BRASS[4])
		cv.rivet(bx2 + 2, 53)
		cv.rivet(bx2 + 12, 53)
	# the two receivers through the wall (the guns are outside): blocks with their bolts' slots
	for gy2 in F_GUN_Y:
		cv.rect(F_RECV_X, gy2 - 3, W - F_RECV_X, 7, IRON[2])
		cv.hl(F_RECV_X, W - 1, gy2 - 3, IRON[4])
		cv.hl(F_RECV_X, W - 1, gy2 + 3, IRON[0])
		cv.vl(F_RECV_X, gy2 - 3, gy2 + 3, IRON[3])
		cv.rect(F_RECV_X + 3, gy2 - 1, 8, 2, VOID)
		cv.rivet(W - 3, gy2 + 1)
	# the spent-casing chute down to a bin on the deck
	cv.rect(100, 26, 4, 17, IRON[1])
	cv.vl(100, 26, 42, IRON[3])
	cv.rect(97, 43, 13, 14, IRON[2])
	cv.hl(97, 109, 43, IRON[4])
	cv.vl(109, 43, 56, IRON[0])
	# the round counter (three drums behind a window) and the rate dial
	cv.rect(12, 5, 17, 9, IRON[0])
	cv.hl(12, 28, 5, IRON[2])
	cv.rect(13, 7, 15, 5, PAPER.darkened(0.25))
	_gauge_face(cv, F_DIAL.x, F_DIAL.y, 5, 0.8)
	cv.vl(F_DIAL.x, F_DIAL.y + 6, 56, Color(0.08, 0.07, 0.06))


static func _feed(cv: Cv, ph: float, pw: float, t: float, slot: Color, rate: float) -> void:
	var heat := _heat(pw)
	var over := _over(pw)
	var th := ph * TAU
	_lamp(cv, F_LAMP, pw, t, slot)
	# the flywheel and its crank pin, the chain up to the feed drum (one drum revolution a crank
	# revolution), the drum's spokes and teeth
	var blur := clampf((rate - 1.7) / 1.3, 0.0, 1.0)
	_spokes(cv, F_FW, F_FR - 2.6, 5, th, STEEL, blur)
	cv.disc_f(F_FW, F_CS, BRASS[1])
	var pin := F_FW + _dir(th) * (F_FR - 5.0)
	cv.rect(roundi(pin.x) - 1, roundi(pin.y) - 1, 3, 3, BRASS[3])
	cv.p(roundi(pin.x) - 1, roundi(pin.y) - 1, BRASS[4])
	_chain(cv, F_FW, F_CS + 0.5, F_DRUM, 3.0, ph, 7, 3.0)
	_spokes(cv, F_DRUM, F_DR - 2.2, 4, th, BRASS, blur)
	cv.teeth(F_DRUM, F_DR + 0.4, 10, th, BRASS[4])
	cv.disc_f(F_DRUM, 1.6, BRASS[3])
	# the shaft's sprockets at the belts' corners turn with it
	for k in 2:
		cv.teeth(Vector2(F_BELT_X[k], F_SHAFT_Y), 2.4, 4, th + k * PI, STEEL[4])
	# the two belts: each advances one pitch a revolution, the lower half a revolution behind the
	# upper (the guns alternate); cartridges lie across the belt, brass cases and copper noses
	for k2 in 2:
		var bx := F_BELT_X[k2]
		var gy := F_GUN_Y[k2]
		var up := float(F_BELT_Y0 - gy)
		var run := float(F_RECV_X + 3 - bx)
		var s := fposmod((ph - 0.5 * float(k2)) * F_PITCH, F_PITCH)
		while s < up + run:
			if s < up:
				var y := roundi(F_BELT_Y0 - s)
				cv.p(bx - 3, y, STEEL[1])
				cv.hl(bx - 2, bx + 2, y, BRASS[3])
				cv.hl(bx - 2, bx + 2, y + 1, BRASS[1])
				cv.p(bx - 2, y, BRASS[4])
				cv.rect(bx + 3, y, 1, 2, COPPER[3])
			else:
				var x := roundi(bx + (s - up))
				cv.p(x, gy - 2, STEEL[1])
				cv.vl(x, gy - 1, gy + 1, BRASS[3])
				cv.vl(x + 1, gy - 1, gy + 1, BRASS[1])
				cv.p(x, gy - 1, BRASS[4])
				cv.rect(x, gy + 2, 2, 1, COPPER[3])
			s += F_PITCH
		# the bolt: home (and the shot) at the start of its stroke, back while the next round feeds
		var u := fposmod(ph - 0.5 * float(k2), 1.0)
		var back := roundi(5.0 * sin(u * PI))
		cv.rect(F_RECV_X + 3 + back, gy - 1, 4, 2, BRASS[3])
		cv.p(F_RECV_X + 3 + back, gy - 1, BRASS[4])
		cv.rect(F_RECV_X + 5 + back, gy - 3, 1, 2, BRASS[2])
		if pw > 0.1 and u < 0.12:
			var k3 := (1.0 - u / 0.12) * (0.6 + 0.6 * heat)
			cv.e(W - 1, gy - 1, Color(1.0, 0.85, 0.5), k3)
			cv.e(W - 1, gy, Color(1.0, 0.7, 0.35), k3)
			cv.e(W - 2, gy, Color(1.0, 0.8, 0.45), 0.6 * k3)
			cv.glow(W - 1, gy, 5.0, Color(1.0, 0.7, 0.35), 0.4 * k3)
		# the spent casing drops down the chute
		if pw > 0.05:
			cv.rect(101, roundi(27.0 + u * 14.0), 2, 2, BRASS[3])
	# the counter's drums step one round at a time
	var rounds := floori(ph * float(TankFeedState.ROUNDS_PER_REV))
	for i in 3:
		var dg := posmod(floori(float(rounds) / pow(10.0, 2 - i)), 10)
		var dx := 14 + i * 5
		cv.rect(dx, 7, 4, 5, PAPER if i == 2 else PAPER.darkened(0.1))
		cv.rect(dx + 1, 8 + dg % 3, 2, 1, NEEDLE)
		if dg >= 5:
			cv.p(dx + 1, 10, NEEDLE)
	# the rate dial, the tag
	_gauge_needle(cv, F_DIAL.x, F_DIAL.y, 5, clampf(rate / 2.0, 0.0, 1.05), over)
	_tag(cv, 4, 4, slot, pw)
	# over: the receivers smoke
	if over > 0.05:
		_vent(cv, Vector2(95, 6), Vector2(-0.4, -1.0), over, t, 0.0, Color(0.7, 0.7, 0.72))
		_vent(cv, Vector2(95, 20), Vector2(-0.4, -1.0), over, t, 0.5, Color(0.7, 0.7, 0.72))


static func _feed_lights(cv: Cv, pw: float) -> void:
	# the breech flashes' glow on the tray, and the counter's little lamp
	cv.light(F_RECV_X, 15, 26.0, Color(1.0, 0.7, 0.4) * (0.3 * smoothstep(0.1, 1.0, pw)))
	cv.light(20, 9, 14.0, _key * 0.35)
	# the caged lamp over the ammo boxes
	cv.light(78, 4, 34.0, _key * (0.7 * (0.85 + 0.15 * minf(pw, 1.0))))

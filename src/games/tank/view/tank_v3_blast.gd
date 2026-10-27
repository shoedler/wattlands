class_name TankV3Blast
extends RefCounted
## MOCK (tank v3 r5 frames): the main gun's blast, ported from the tank builder's r6
## (tank3-tank: assets/tank/v3/tools_src/tank_r6.gd blast() and puff()), hard pixels into an Image:
##  0.00-0.07  a big cross/star flash (about 50 px across) with blade jets out of the slotted brake
##  0.05-0.22  a lumpy fire ball rolling forward, flame fragments thrown off
##  0.08-1.9   a billowing smoke cloud and a smoke ring
##  0.02-1.4   blast dust off the road under the muzzle, a dust shockwave both ways, pebbles; sparks
## The view shows one moment of it (TANK_V3_FIRE_T, seconds after the shot) for a still frame.

const F_WHITE := Color("#fff8e0")
const F_YEL := Color("#ffd848")
const F_ORA := Color("#ff8a20")
const F_RED := Color("#c83a14")
const F_DRED := Color("#5a1808")
const SMOKE: Array = [Color("#2a2622"), Color("#3e3832"), Color("#5a5248"), Color("#7a7062")]
const DUST: Array = [Color("#2e2618"), Color("#463a28"), Color("#6a5a40")]


## The blast `ft` s after the shot into `img`: `m` the muzzle, `a` the bore angle, `gy` the road's y
## under the muzzle (all in img px).
static func blast(img: Image, m: Vector2, a: float, ft: float, gy: float) -> void:
	if ft < 0.0 or ft > 2.0:
		return
	var d := Vector2(cos(a), sin(a))
	var n := Vector2(-d.y, d.x)
	if ft > 0.08:
		var age := ft - 0.08
		for j in 16:
			var sp := 18.0 + 46.0 * h2(j, 1, 41)
			var up := 10.0 + 26.0 * h2(j, 2, 41)
			var slow := 1.0 / (1.0 + age * 1.2)
			var side := (h2(j, 3, 41) - 0.5) * 26.0 * minf(age * 2.0, 1.0)
			var c := m + d * (6.0 + j * 4.5 + sp * age * slow) + n * side + Vector2(0, -up * age)
			var r := 4.0 + 13.0 * minf(age * 1.1, 1.0) + h2(j, 4, 41) * 4.0
			puff(img, c, r, SMOKE, clampf((age - 0.9) / 1.0, 0.0, 1.0), j * 13)
	if ft > 0.02 and ft < 1.6:
		var age2 := ft - 0.02
		var dust4: Array = [DUST[0], DUST[0], DUST[1], DUST[2]]
		for j in 9:
			var c2 := Vector2(
				m.x - 30.0 + j * 9.0 + 14.0 * age2, gy - 3.0 - 22.0 * age2 * (0.4 + h2(j, 5, 43))
			)
			var fd := clampf((age2 - 0.6) / 0.8, 0.0, 1.0)
			puff(img, c2, 3.0 + 7.0 * minf(age2 * 1.8, 1.0), dust4, fd, j * 7 + 100)
		if age2 < 0.9:
			for sd: float in [-1.0, 1.0]:
				for j in 4:
					var xr: float = m.x + sd * (14.0 + 150.0 * age2 - j * 7.0)
					var rr := 2.0 + 1.5 * h2(j, 6, 44)
					var fd2 := clampf(age2 / 0.9, 0.0, 1.0)
					puff(img, Vector2(xr, gy - 2.0), rr, dust4, fd2, j * 5 + 200 + int(sd))
		if age2 < 0.8:
			for j in 12:
				var vx := (h2(j, 7, 45) - 0.3) * 120.0
				var vy := -70.0 - 80.0 * h2(j, 8, 45)
				var pp := (
					Vector2(m.x - 10.0 + j * 3.0, gy - 1.0)
					+ Vector2(vx, vy) * age2
					+ Vector2(0, 260.0 * age2 * age2)
				)
				if pp.y <= gy:
					put(img, floori(pp.x), floori(pp.y), DUST[0] if j % 2 else Color("#1a140e"))
					put(img, floori(pp.x) + 1, floori(pp.y), DUST[1])
	if ft < 0.5:
		for j in 26:
			var sa := a + (h2(j, 6, 47) - 0.5) * 2.0
			var spd := 120.0 + 180.0 * h2(j, 7, 47)
			var dir := Vector2(cos(sa), sin(sa))
			var p0 := m + dir * spd * ft + Vector2(0, 80.0 * ft * ft)
			line(img, p0 - dir * 4.0, p0, F_YEL if j % 3 else F_ORA)
	if ft >= 0.05 and ft < 0.24:
		var u := ft - 0.05
		var fb := m + d * (12.0 + 90.0 * u)
		var fr := 19.0 - 30.0 * u
		var fa0 := clampf((u - 0.12) / 0.07, 0.0, 1.0) * 0.6
		puff(img, fb, fr + 3.0, [F_DRED, F_RED, F_ORA, F_YEL], fa0, 77)
		puff(img, fb - d * 2.0 + n * 3.0, fr * 0.62, [F_ORA, F_YEL, F_WHITE, F_WHITE], 0.0, 78)
		puff(img, fb + d * (fr * 0.7) - n * 5.0, fr * 0.45, [F_RED, F_ORA, F_YEL, F_YEL], 0.0, 79)
		for j in 7:
			var fa := a + (h2(j, 11, 49) - 0.5) * 2.4
			var fp := m + Vector2(cos(fa), sin(fa)) * (20.0 + 160.0 * u) + Vector2(0, 50.0 * u * u)
			puff(img, fp, 2.5 + 1.5 * h2(j, 12, 49), [F_DRED, F_RED, F_ORA, F_YEL], 0.0, 80 + j)
	if ft < 0.075:
		var big := 1.0 if ft < 0.04 else 0.75
		var bk := m - d * 4.0
		for y in range(floori(m.y) - 34, ceili(m.y) + 35):
			for x in range(floori(m.x) - 16, ceili(m.x) + 58):
				var v := Vector2(x + 0.5, y + 0.5) - m
				var rho := v.length()
				var phi := atan2(v.dot(n), v.dot(d))
				var rad := (
					(
						8.0
						+ 40.0 * pow(maxf(cos(phi), 0.0), 7.0)
						+ 20.0 * pow(maxf(cos(4.0 * phi), 0.0), 12.0)
						+ 10.0 * pow(maxf(cos(8.0 * phi + 0.4), 0.0), 16.0)
					)
					* big
				)
				var vb := Vector2(x + 0.5, y + 0.5) - bk
				var jet := (
					absf(vb.dot(d)) < 2.5 - absf(vb.dot(n)) * 0.06 and absf(vb.dot(n)) < 24.0 * big
				)
				if rho > rad + 1.5 and not jet:
					continue
				var col := F_ORA
				if jet:
					col = F_YEL if absf(vb.dot(n)) < 14.0 * big else F_ORA
				elif rho > rad:
					col = F_RED
				elif rho < rad * 0.45:
					col = F_WHITE
				elif rho < rad * 0.72:
					col = F_YEL
				put(img, x, y, col)


static func puff(img: Image, c: Vector2, r: float, ramp: Array, fade: float, sd: int) -> void:
	for y in range(floori(c.y - r) - 1, ceili(c.y + r) + 2):
		for x in range(floori(c.x - r) - 1, ceili(c.x + r) + 2):
			var d := Vector2(x + 0.5, y + 0.5) - c
			var lump := r * (0.85 + 0.25 * h2(floori(atan2(d.y, d.x) * 3.0) + 9, sd, 7))
			var rho := d.length()
			if rho > lump:
				continue
			if fade > 0.0 and h2(x, y, sd + 3) < fade:
				continue
			var lit := (-d.x - d.y) / maxf(rho, 0.001)
			var col: Color = ramp[1]
			if rho > lump - 1.0:
				col = ramp[0]
			elif lit > 0.5 and rho > lump * 0.45:
				col = ramp[3]
			elif lit > -0.1:
				col = ramp[2]
			put(img, x, y, col)


static func put(i: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < i.get_width() and y < i.get_height():
		i.set_pixel(x, y, c)


static func line(i: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var n := maxi(ceili(maxf(absf(b.x - a.x), absf(b.y - a.y))), 1)
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		put(i, floori(p.x), floori(p.y), c)


static func h2(x: int, y: int, s: int = 0) -> float:
	var n := (x * 374761393 + y * 668265263 + s * 1442695041) & 0xFFFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65536.0

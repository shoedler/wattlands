extends RefCounted
## Running gear for the tank generators: the track as a belt round its wheels (road wheels, sprocket,
## idler, return rollers), links that travel with the hull's travel, wheels drawn per pixel at
## their rotation angle.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")

const TRK0 := Color("#0f0c09")
const TRK1 := Color("#1c1610")
const TRK2 := Color("#30271d")
const TRK3 := Color("#4e4131")
const TRK4 := Color("#6e5c44")
const OUT := Color("#0b0806")
const LINK_PITCH := 7.0

## r5: dark steel and mud track shoes (set from the gear dictionary's "dark").
static var DARK := false


## Belt samples round `circles` ([{c, r}] in clockwise screen order): {pts: [[p, n, s]], len}.
## n is the outward normal; s the arc length. A circle the belt would wrap concavely (a wheel
## pushed up by the ground) gets no arc: the belt runs straight under it.
static func belt(circles: Array, ds := 0.4) -> Dictionary:
	var n := circles.size()
	var nrm: Array[Vector2] = []
	for i in n:
		var a: Dictionary = circles[i]
		var b: Dictionary = circles[(i + 1) % n]
		var d: Vector2 = b["c"] - a["c"]
		var dl := maxf(d.length(), 0.001)
		var cv := clampf((float(a["r"]) - float(b["r"])) / dl, -1.0, 1.0)
		nrm.append((d / dl).rotated(-acos(cv)))
	var pts: Array = []
	var s := 0.0
	for i in n:
		var c: Dictionary = circles[i]
		var cc: Vector2 = c["c"]
		var r := float(c["r"])
		var n0 := nrm[(i - 1 + n) % n]
		var n1 := nrm[i]
		var a0 := n0.angle()
		var da := fposmod(n1.angle() - a0, TAU)
		if da > PI * 1.6:
			da = 0.0
		var steps := maxi(ceili(da * r / ds), 1)
		for k in steps:
			var a := a0 + da * float(k) / float(steps)
			var nv := Vector2(cos(a), sin(a))
			pts.append([cc + nv * r, nv, s])
			s += da * r / float(steps)
		var p0: Vector2 = cc + n1 * r
		var nx: Dictionary = circles[(i + 1) % n]
		var p1: Vector2 = nx["c"] + n1 * float(nx["r"])
		var seg := p0.distance_to(p1)
		var m := maxi(ceili(seg / ds), 1)
		for k in m:
			pts.append([p0.lerp(p1, float(k) / float(m)), n1, s])
			s += seg / float(m)
	return {"pts": pts, "len": s}


## The track: shoes of LINK_PITCH (stretched so a whole number fits the loop), `thick` px, moving
## by `travel` (positive: the top run moves forward, clockwise). Each shoe has an inner guide horn,
## a pin boss at its joint, a plate with a gap to the next shoe, and an outer grouser bar.
static func draw_track(img: Image, b: Dictionary, travel: float, thick := 5.0, enemy := false) -> void:
	var total: float = b["len"]
	var pitch := total / roundf(total / LINK_PITCH)
	var c1 := TRK1
	var c2 := TRK2
	var c3 := TRK3
	var c4 := TRK4
	if enemy:
		c1 = Color("#1d211d")
		c2 = Color("#323833")
		c3 = Color("#4f574f")
		c4 = Color("#6f786d")
	elif DARK:
		c1 = Color("#0d0a08")
		c2 = Color("#15110d")
		c3 = Color("#1e1913")
		c4 = Color("#3a3024")
	var horn0 := pitch * 0.4
	var horn1 := pitch * 0.4 + 2.0
	var gr0 := pitch * 0.3
	var gr1 := pitch * 0.3 + 2.6
	for pass_i in 2:
		for e: Array in b["pts"]:
			var p: Vector2 = e[0]
			var nv: Vector2 = e[1]
			var u := fposmod(float(e[2]) - travel, pitch)
			var lit := nv.y < -0.35
			var horn := u >= horn0 and u < horn1
			var grouser := u >= gr0 and u < gr1
			var dd := -2.0
			while dd <= thick + 2.0:
				var q := p + nv * dd
				var x := floori(q.x)
				var y := floori(q.y)
				var col := Color(0, 0, 0, 0)
				var outl := false
				if dd < -1.0:
					outl = horn
				elif dd < 0.0:
					if horn:
						col = c3 if lit else c2
					else:
						outl = true
				elif dd < 1.0:
					col = c4 if u < 1.3 else (c2 if u > 1.8 else TRK0)
				elif dd < thick - 1.0:
					col = TRK0 if u < 0.8 else (c2 if lit else c1)
					if dd < 2.0 and u >= 0.8 and u < 1.8:
						col = c3
				elif dd < thick:
					col = TRK0 if u < 0.8 else (c3 if lit else c2)
				elif dd < thick + 1.0:
					if grouser:
						col = c4 if lit else c3
					else:
						outl = true
				else:
					outl = grouser
				if pass_i == 0 and outl:
					Px.put(img, x, y, OUT)
				elif pass_i == 1 and col.a > 0.0:
					Px.put(img, x, y, col)
				dd += 0.5


## A wheel at `c` (target px), radius `r`, turned `ang` radians. kind: road, sprocket, idler, roller.
static func draw_wheel(img: Image, c: Vector2, r: float, ang: float, kind: String, enemy := false) -> void:
	var ext := r + (3.5 if kind == "sprocket" else 1.0)
	var rim := Color("#33261a") if not enemy else Color("#39403a")
	var rim_hi := Color("#5e4a32") if not enemy else Color("#5d665c")
	var disc := Color("#21180f") if not enemy else Color("#222823")
	var disc_d := Color("#1c140d") if not enemy else Color("#161a17")
	var hub := Color("#6a5236") if not enemy else Color("#7d8578")
	var hub_hi := Color("#9a7a4a") if not enemy else Color("#b0b8aa")
	for y in range(floori(c.y - ext), ceili(c.y + ext) + 1):
		for x in range(floori(c.x - ext), ceili(c.x + ext) + 1):
			var d := Vector2(x + 0.5, y + 0.5) - c
			var rho := d.length()
			if rho > ext:
				continue
			var phi := atan2(d.y, d.x) - ang
			var litf := (-d.y * 0.8 - d.x * 0.3) / maxf(rho, 0.001)
			var col := Color(0, 0, 0, 0)
			match kind:
				"road":
					if rho > r + 0.7:
						continue
					if r > 9.0:
						if rho > r:
							col = OUT
						elif rho > r * 0.8:
							col = Color("#1a1612") if litf > 0.5 else Color("#0c0a08")
						elif rho > r * 0.68:
							col = rim_hi if litf > 0.2 else rim
						elif rho > r * 0.36:
							col = disc if litf > -0.2 else disc_d
							for kk in 6:
								var ha := phi - TAU * kk / 6.0
								if (Vector2(cos(ha), sin(ha)) * r * 0.52).distance_to(Vector2(rho, 0)) < r * 0.11:
									col = OUT
						elif rho > r * 0.2:
							col = disc_d
							if fposmod(phi * 6.0 / TAU, 1.0) < 0.2:
								col = Color("#7a6244") if not enemy else hub
						else:
							col = Color("#6a5236") if litf > 0.3 else Color("#3e2e1e")
						if col.a > 0.0:
							Px.put(img, x, y, col)
						continue
					if rho > r:
						col = OUT
					elif rho > r - 1.3:
						col = TRK1 if litf > 0.45 else TRK0
					elif rho > r - 2.3:
						col = rim_hi if litf > 0.25 else rim
					elif rho > 2.6:
						col = disc_d if cos(5.0 * phi) > 0.55 else disc
						if litf > 0.6 and rho > r - 3.0:
							col = rim
					elif rho > 1.6:
						col = disc_d
						var bk := fposmod(phi * 6.0 / TAU, 1.0)
						if rho > 2.2 and rho < 3.4 and bk < 0.22:
							col = Color("#5e4a32") if not enemy else hub
					else:
						col = Color("#6a5236") if litf > 0.3 else Color("#3e2e1e")
						if enemy:
							col = hub
				"roller":
					if rho > r + 0.6:
						continue
					col = OUT if rho > r else (rim_hi if litf > 0.3 else rim)
					if rho < r - 1.0:
						col = disc
					if rho < 1.0:
						col = hub
					if rho >= 1.0 and rho < r - 1.0 and fposmod(phi * 3.0 / TAU, 1.0) < 0.2:
						col = hub
				"sprocket", "idler":
					var teeth := 11 if kind == "sprocket" else 0
					if rho > r:
						if teeth == 0:
							if rho < r + 0.7:
								col = OUT
							else:
								continue
						else:
							var tv := cos(teeth * phi)
							var tw := 0.1 + (rho - r) * 0.18
							if tv < tw:
								if rho < r + 0.8:
									col = OUT
								else:
									continue
							elif rho > r + 2.4 or tv < tw + 0.15:
								col = OUT
							else:
								col = rim_hi if litf > 0.1 else rim
					elif rho > r - 2.6:
						col = rim_hi if litf > 0.35 else rim
						if rho < r - 1.7:
							col = disc
						var bolt := fposmod(phi * 10.0 / TAU, 1.0)
						if rho > r - 1.7 and rho < r - 0.7 and bolt < 0.2:
							col = Color("#7a6244") if not enemy else hub_hi
					elif rho < 3.2:
						col = hub if rho > 1.3 else hub_hi
						if rho > 2.4:
							col = OUT
						elif rho > 1.3 and fposmod(phi * 5.0 / TAU, 1.0) < 0.25:
							col = hub_hi
					else:
						var ns := 6 if kind == "sprocket" else 5
						var sp := fposmod(phi, TAU / ns)
						var side := sp < TAU / ns * 0.5
						sp = minf(sp, TAU / ns - sp)
						var w := sp * rho
						if w < 1.2:
							col = rim_hi if (litf > 0.0 or side) else rim
						elif w < 2.0:
							col = OUT
						else:
							continue
			if col.a > 0.0:
				Px.put(img, x, y, col)

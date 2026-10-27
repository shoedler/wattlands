extends RefCounted
## Running gear for the v3 tank mock: the track as a belt round its wheels (road wheels, sprocket,
## idler, return rollers), links that travel with the hull's travel, wheels drawn per pixel at
## their rotation angle, and suspension that follows a ground profile.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")

const TRK0 := Color("#0f0c09")
const TRK1 := Color("#2a2219")
const TRK2 := Color("#44382b")
const TRK3 := Color("#6c5a44")
const TRK4 := Color("#8f7958")
const OUT := Color("#0b0806")
const LINK_PITCH := 7.0


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
	var rim := Color("#4a3826") if not enemy else Color("#39403a")
	var rim_hi := Color("#7a5e3e") if not enemy else Color("#5d665c")
	var disc := Color("#2e2218") if not enemy else Color("#222823")
	var disc_d := Color("#1c140d") if not enemy else Color("#161a17")
	var hub := Color("#b08a4a") if not enemy else Color("#7d8578")
	var hub_hi := Color("#e6c27a") if not enemy else Color("#b0b8aa")
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
						var bk := fposmod(phi * 4.0 / TAU + 0.125, 1.0)
						if rho < 2.6 and bk < 0.2:
							col = Color("#c8a468") if not enemy else hub_hi
					else:
						col = hub_hi if litf > 0.3 else hub
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
							col = Color("#c8a468") if not enemy else hub_hi
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


## Suspension: the road wheels' centres in target coords for the hull transform `xf` (local ->
## target) over `ground` (Callable: target x -> target ground y), each kept within its travel.
static func wheel_centres(gear: Dictionary, xf: Transform2D, ground: Callable) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var t := float(gear["T"])
	for w: Dictionary in gear["wheels"]:
		var mount: Vector2 = xf * Vector2(float(w["x"]), float(w["y"]))
		var r := float(w["r"])
		var want := float(ground.call(mount.x)) - r - t
		var s := clampf(want - mount.y, -float(gear["up"]), float(gear["droop"]))
		out.append(mount + Vector2(0, s))
	return out


## Draws the running gear (behind the hull: road wheels, arms, the track; in front: sprocket,
## idler) into `img`. `wc` = the road wheels' centres (target coords), `xf` local -> target.
static func draw_back(
	img: Image, gear: Dictionary, xf: Transform2D, wc: Array[Vector2], travel: float, enemy := false
) -> void:
	var circles := _circles(gear, xf, wc)
	var b := belt(circles)
	var ang := travel
	var t := float(gear["T"])
	# suspension: a trailing arm from each hub to its pivot on the hull, a coil spring above the hub
	var dark := Color("#1a130d") if not enemy else Color("#151915")
	var mid := Color("#3a2c1e") if not enemy else Color("#2c332c")
	var lit := Color("#6a5236") if not enemy else Color("#4f574f")
	for i in wc.size():
		var w: Dictionary = gear["wheels"][i]
		var r := float(w["r"])
		var piv: Vector2 = xf * Vector2(float(w["x"]) - r + 0.5, float(w["y"]) - r * 0.6)
		var stop: Vector2 = xf * Vector2(float(w["x"]) + 2.5, float(w["y"]) - r - 7.0)
		var n := maxi(ceili(wc[i].distance_to(stop)), 1)
		for k in n + 1:
			var q := wc[i].lerp(stop, float(k) / n) + Vector2(1, 0)
			Px.put(img, floori(q.x), floori(q.y), lit if k % 2 == 0 else dark)
			Px.put(img, floori(q.x) + 1, floori(q.y), mid if k % 2 == 0 else dark)
		Px.linef(img, wc[i] + Vector2(0, 1), piv + Vector2(0, 1), dark)
		Px.linef(img, wc[i], piv, mid)
		Px.put(img, floori(piv.x), floori(piv.y), lit)
	if not bool(gear.get("track_front", false)):
		draw_track(img, b, travel, t, enemy)
	for i in wc.size():
		var w2: Dictionary = gear["wheels"][i]
		draw_wheel(img, wc[i], float(w2["r"]), ang / float(w2["r"]), "road", enemy)
	for rl: Dictionary in gear["rollers"]:
		draw_wheel(img, xf * (rl["c"] as Vector2), float(rl["r"]), ang / float(rl["r"]), "roller", enemy)


static func draw_front(
	img: Image, gear: Dictionary, xf: Transform2D, wc: Array[Vector2], travel: float, enemy := false
) -> void:
	if bool(gear.get("track_front", false)):
		draw_track(img, belt(_circles(gear, xf, wc)), travel, float(gear["T"]), enemy)
	var rot := xf.get_rotation()
	var sp: Dictionary = gear["sprocket"]
	var idl: Dictionary = gear["idler"]
	draw_wheel(img, xf * (sp["c"] as Vector2), float(sp["r"]), travel / float(sp["r"]) + rot, "sprocket", enemy)
	draw_wheel(img, xf * (idl["c"] as Vector2), float(idl["r"]), travel / float(idl["r"]) + rot, "idler", enemy)


static func _circles(gear: Dictionary, xf: Transform2D, wc: Array[Vector2]) -> Array:
	var circles: Array = []
	var idl: Dictionary = gear["idler"]
	var sp: Dictionary = gear["sprocket"]
	circles.append({"c": xf * (idl["c"] as Vector2), "r": float(idl["r"]) + 0.5})
	for rl: Dictionary in gear["rollers"]:
		circles.append({"c": xf * (rl["c"] as Vector2), "r": float(rl["r"]) + 0.5})
	if gear.has("horn_front"):
		var hf: Dictionary = gear["horn_front"]
		circles.append({"c": xf * (hf["c"] as Vector2), "r": float(hf["r"]) + 0.5})
	circles.append({"c": xf * (sp["c"] as Vector2), "r": float(sp["r"]) + 0.5})
	for i in range(wc.size() - 1, -1, -1):
		var w: Dictionary = gear["wheels"][i]
		circles.append({"c": wc[i], "r": float(w["r"]) + 0.5})
	return circles

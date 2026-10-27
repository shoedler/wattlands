extends SceneTree
## Writes the r6 tank mockups to build/v3mock/tank/r6/ (see notes.md there).
##   assets/tank/v3/tools_src/r6_base.sh first (the base), then
##   tools/godot.sh --headless --path . -s assets/tank/v3/tools_src/mock_r6.gd -- <job> [<job> ...]
## jobs: static, drive, tilt, loader, secbox, fire, hitbox, compare. GIFs: gifs_r3.sh r6.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const Tank = preload("res://assets/tank/v3/tools_src/tank.gd")
const Tank5 = preload("res://assets/tank/v3/tools_src/tank_r5.gd")
const Tank6 = preload("res://assets/tank/v3/tools_src/tank_r6.gd")
const Gear = preload("res://assets/tank/v3/tools_src/gear.gd")
const Light = preload("res://assets/tank/v3/tools_src/light.gd")

const OUT_DIR := "res://build/v3mock/tank/r6"
const ENV_BG := "C:/Projects/wt/tank3-env/assets/tank/v3env/planes/moderate/preview.png"
const BG := Color("#0a0f12")
const LABEL := Color("#e3a24a")
const DIM := Color("#a3937a")
const CREW_HERO := {"drive": 0, "gun": 2, "loader": 1, "lights": 3, "sec": -1}
const CREW_DRIVE := {"drive": 0, "gun": 2, "loader": 1, "lights": -1, "sec": 3}
const RPM := {"drive": 82.0, "gun": 88.0, "loader": 90.0, "lights": 85.0, "sec": 95.0}
const GROUND_Y := 385
const LEFT_X := 18

var B: Dictionary
var L: Dictionary


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	B = Tank6.build()
	L = B["L"]
	var jobs := OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	for j in jobs:
		var tj := Time.get_ticks_msec()
		match j:
			"static":
				job_static()
			"drive":
				job_drive()
			"tilt":
				job_tilt()
			"loader":
				job_loader()
			"secbox":
				job_secbox()
			"fire":
				job_fire()
			"hitbox":
				job_hitbox()
			"compare":
				job_compare()
		print("%s: %d ms" % [j, Time.get_ticks_msec() - tj])
	print("done in %d ms" % (Time.get_ticks_msec() - t0))
	quit()


func save(img: Image, name: String) -> void:
	var p := ProjectSettings.globalize_path(OUT_DIR + "/" + name)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_png(p)


func state(t: float, crew: Dictionary, fire_at := -1.0) -> Dictionary:
	var sec_on := int(crew.get("sec", -1)) >= 0
	return {
		"t": t, "travel": t * 40.0, "rpm": RPM, "crew": crew, "elev": 1.5 + 1.5 * sin(t * 1.6),
		"elev_rate": cos(t * 1.6), "sec_elev": 3.0 + 9.0 * sin(t * 2.4 + 1.0) if sec_on else 2.0,
		"load_t": fposmod(t * 1.2 + 0.2, Tank6.CYCLE), "ready": 2,
		"sec_revs": t * RPM["sec"] / 60.0 if sec_on else -1.0, "sec_rpm": RPM["sec"],
		"fire_t": t - fire_at if fire_at >= 0.0 else 99.0,
		"search_on": int(crew.get("lights", -1)) >= 0,
	}


func road(img: Image, y: int, travel: float) -> void:
	for x in img.get_width():
		var wx := x + floori(travel)
		for yy in range(y, img.get_height()):
			var d := yy - y
			var col := Color("#15171a") if d > 1 else Color("#262826")
			if d == 0:
				col = Color("#30302a")
			if d > 2 and Px.h2(wx, yy, 77) > 0.93:
				col = Color("#202224")
			if d > 1 and d < 5 and Px.h2(wx / 2, yy, 78) > 0.9:
				col = Color("#3a3830")
			img.set_pixel(x, yy, col)


## The tank's local -> canvas transform: its ground centre at `at` + (cx, ground), rotated by `rot`.
func xf_at(LL: Dictionary, at: Vector2, rot: float) -> Transform2D:
	var piv := Vector2(LL["size"].x * 0.5, float(LL["ground"]))
	var x := Transform2D(rot, Vector2.ZERO)
	x.origin = at + piv - x.basis_xform(piv)
	return x


## Composites the tank (rotated `rot` about its ground centre, nearest) with its bloom, lights and
## firing effects onto `canvas`. `gy` = the road's canvas y under the muzzle (for the dust kick).
func put_tank(canvas: Image, tank: Image, at: Vector2, rot: float, st: Dictionary, gy: float, LL: Dictionary = {}) -> void:
	if LL.is_empty():
		LL = L
	var xf := xf_at(LL, at, rot)
	var layer := Px.blank(canvas.get_width(), canvas.get_height())
	if absf(rot) < 0.0005:
		layer.blend_rect(tank, Rect2i(Vector2i.ZERO, tank.get_size()), Vector2i(at))
	else:
		var piv := Vector2(LL["size"].x * 0.5, float(LL["ground"]))
		Px.rotate_nearest(tank, rot, piv, layer, xf * piv)
	canvas.blend_rect(layer, Rect2i(Vector2i.ZERO, layer.get_size()), Vector2i.ZERO)
	var ft := float(st.get("fire_t", 99.0))
	var m := Tank6.muzzle(LL, st, xf)
	if LL.has("rack"):
		Tank6.blast(canvas, m["p"], m["a"], ft, gy)
		Tank6.bursts(canvas, LL, xf, st)
	var bb := layer.get_used_rect()
	Light.bloom(canvas, layer, bb)
	Light.tank_lights(canvas, LL, xf, bool(st.get("search_on", true)))
	if LL.has("rack") and ft >= 0.0 and ft < 0.16:
		var k := 1.0 - ft / 0.16
		Light.halo(canvas, m["p"], 150.0, Color("#ffc070"), 0.7 * k)
		Light.halo(canvas, m["p"] + Vector2(0, 60), 120.0, Color("#ffb060"), 0.3 * k)
		Light.halo(canvas, m["p"], 20.0, Color("#fff4d0"), 1.0 * k)


func env_backdrop() -> Image:
	var img := Image.load_from_file(ENV_BG)
	if img == null or img.is_empty():
		img = Px.blank(960, 540, BG)
	img.convert(Image.FORMAT_RGBA8)
	return img


func strip(frames: Array[Image], every: int, cols: int, title: String) -> Image:
	var picks: Array[Image] = []
	var idx: Array[int] = []
	for k in range(0, frames.size(), every):
		picks.append(frames[k])
		idx.append(k)
	var fw := picks[0].get_width()
	var fh := picks[0].get_height()
	var rows := ceili(picks.size() / float(cols))
	var o := Px.blank(cols * (fw + 4) + 4, rows * (fh + 4) + 18, Color("#06090b"))
	Px.text(o, 4, 3, title, LABEL)
	for i in picks.size():
		var at := Vector2i(4 + (i % cols) * (fw + 4), 18 + (i / cols) * (fh + 4))
		o.blend_rect(picks[i], Rect2i(Vector2i.ZERO, picks[i].get_size()), at)
		Px.text(o, at.x + 2, at.y + fh - 11, "%02d" % idx[i], DIM, false)
	return o


# --- statics ---------------------------------------------------------------------------------------------


func job_static() -> void:
	var st := state(2.2, CREW_HERO)
	st["elev"] = 2.0
	var tank := Tank6.frame(B, st)
	save(tank, "tank_r6_sprite_1x.png")
	var pad := Vector2(16, 46)
	var cv := Px.blank(tank.get_width() + 260, tank.get_height() + 60, BG)
	road(cv, int(pad.y) + int(L["ground"]), 0.0)
	put_tank(cv, tank, pad, 0.0, st, pad.y + float(L["ground"]))
	save(cv, "tank_r6_dark_1x.png")
	save(Px.scaled(cv, 4), "tank_r6_dark_4x.png")
	var env := env_backdrop()
	var at := Vector2(LEFT_X, GROUND_Y - int(L["ground"]))
	put_tank(env, tank, at, 0.0, st, float(GROUND_Y))
	save(env, "tank_r6_forest_1x.png")
	save(Px.scaled(env, 2), "tank_r6_forest_2x.png")
	save(Px.scaled(env.get_region(Rect2i(0, 160, 620, 250)), 4), "tank_r6_forest_crop_4x.png")


# --- driving, with a main-gun shot and the bow guns' bursts --------------------------------------------------


func job_drive() -> void:
	var frames: Array[Image] = []
	for k in 72:
		var t := k / 12.0
		var st := state(t, CREW_DRIVE, 1.0)
		var tank := Tank6.frame(B, st)
		var pad := Vector2(16, 40)
		var cv := Px.blank(tank.get_width() + 280, tank.get_height() + 50, BG)
		road(cv, int(pad.y) + int(L["ground"]), float(st["travel"]))
		put_tank(cv, tank, pad, deg_to_rad(Tank6.rock(float(st["fire_t"]))), st, pad.y + float(L["ground"]))
		frames.append(cv)
		save(Px.scaled(cv, 2), "frames/drive/f%03d.png" % k)
	save(strip(frames, 4, 3, "R6 DRIVING: A MAIN-GUN SHOT AT 1.0 S, THE BOW GUNS' BURSTS"), "drive_strip.png")


# --- the firing close-up at 3x ---------------------------------------------------------------------------------


func job_fire() -> void:
	var frames: Array[Image] = []
	for k in 36:
		var t := 2.0 + k / 20.0
		var st := state(t, CREW_DRIVE, 2.05)
		st["travel"] = 0.0
		var tank := Tank6.frame(B, st)
		var pad := Vector2(16, 40)
		var cv := Px.blank(tank.get_width() + 280, tank.get_height() + 50, BG)
		road(cv, int(pad.y) + int(L["ground"]), 0.0)
		put_tank(cv, tank, pad, deg_to_rad(Tank6.rock(float(st["fire_t"]))), st, pad.y + float(L["ground"]))
		var c := cv.get_region(Rect2i(300, 40, 300, 220))
		var big := Px.scaled(c, 3)
		Px.text(big, 8, 6, "R6 FIRING  %.2f S AFTER THE SHOT" % maxf(float(st["fire_t"]), 0.0), LABEL)
		frames.append(big)
		save(big, "frames/fire/f%03d.png" % k)
	save(strip(frames, 3, 4, "R6 FIRING CLOSE-UP (3X)"), "fire_strip.png")


# --- terrain tilt with suspension (method a) ------------------------------------------------------------------


func ground_y(x: float) -> float:
	return 232.0 + 4.0 * sin(x * TAU / 700.0) + 3.6 * sin(x * TAU / 150.0) + 2.2 * sin(x * TAU / 64.0 + 1.0)


func job_tilt() -> void:
	var E := Tank.build(Tank.layout_enemy())
	var LE: Dictionary = E["L"]
	(LE["gear"] as Dictionary)["up"] = 5.0
	(LE["gear"] as Dictionary)["droop"] = 4.0
	var env := env_backdrop()
	var size := Vector2i(760, 290)
	var frames: Array[Image] = []
	for k in 90:
		var t := k / 15.0
		var px_w := 60.0 + 40.0 * t
		var cam := px_w - 260.0
		var img := env.get_region(Rect2i(0, 90, size.x, size.y))
		for x in size.x:
			var wx := cam + x + 0.5
			var gy := ground_y(wx)
			for y in range(floori(gy), size.y):
				var d := float(y) - gy
				var col := Color("#141716") if d > 2.0 else Color("#2a2c26")
				if d < 1.0:
					col = Color("#34342c")
				if d > 2.0 and Px.h2(floori(wx), y, 77) > 0.94:
					col = Color("#1e2120")
				if d > 1.0 and d < 6.0 and Px.h2(floori(wx) / 2, y, 78) > 0.9:
					col = Color("#3a3a30")
				img.set_pixel(x, y, col)
		var gfn := func(x: float) -> float: return ground_y(x + cam)
		var ex := 780.0 - 20.0 * t - cam
		var pe := Tank.pose(LE, ex, gfn, true)
		var ste := {"t": t, "travel": 20.0 * t, "elev": 2.0 + 3.0 * sin(t)}
		ste["wc"] = _local_wheels(LE, pe, gfn)
		var eimg := Tank.frame(E, ste)
		eimg.flip_x()
		var esrc := Vector2(LE["size"].x * 0.5, float(LE["ground"]))
		Px.rotate_nearest(eimg, pe["rot"], esrc, img, (pe["xf"] as Transform2D) * esrc)
		var pp := Tank.pose(L, 260.0, gfn)
		var st := state(t, CREW_HERO)
		st["travel"] = 40.0 * t
		var wcl := _local_wheels(L, pp, gfn)
		# the hull rides on its springs: half the wheels' mean compression lifts it
		var comp := 0.0
		var i := 0
		for w: Dictionary in L["gear"]["wheels"]:
			comp += float(w["y"]) - wcl[i].y
			i += 1
		comp /= float(i)
		var lift := comp * 0.5
		for j in wcl.size():
			wcl[j] += Vector2(0, lift)
		st["wc"] = wcl
		var tank := Tank6.frame(B, st)
		var xf: Transform2D = pp["xf"]
		var psrc := Vector2(L["size"].x * 0.5, float(L["ground"]))
		var at := (xf * psrc) + Vector2(0, -lift).rotated(float(pp["rot"])) - psrc
		put_tank(img, tank, at, float(pp["rot"]), st, ground_y(cam + 700.0))
		var dg := float(pp["deg"])
		Px.text(img, 6, 4, "R6  SUSPENSION: EACH WHEEL ON ITS OWN ARM, THE HULL RIDES THE FIT (METHOD A)", LABEL)
		Px.text(img, 6, 17, "HULL %.1f DEG %s" % [absf(dg), "NOSE UP" if dg < 0.0 else "NOSE DOWN"], DIM, false)
		frames.append(img)
		save(Px.scaled(img, 2), "frames/tilt/f%03d.png" % k)
	save(strip(frames, 6, 3, "R6 SUSPENSION ON A BUMPY ROAD"), "tilt_a_strip.png")


func _local_wheels(LL: Dictionary, pose: Dictionary, gfn: Callable) -> Array[Vector2]:
	var xf: Transform2D = pose["xf"]
	var w := Gear.wheel_centres(LL["gear"], xf, gfn)
	var inv := xf.affine_inverse()
	var o: Array[Vector2] = []
	for p in w:
		o.append(inv * p)
	return o


# --- the loader close-up: the ready-rack window and the breech window -----------------------------------------


func job_loader() -> void:
	var crop := Rect2i(176, 80, 180, 108)
	var n := 70
	var small: Array[Image] = []
	for k in n:
		var lt := k * Tank6.CYCLE / n
		var st := state(2.0 + lt, CREW_HERO)
		st["load_t"] = lt
		st["elev"] = 1.0
		st["travel"] = 0.0
		var tank := Tank6.frame(B, st)
		var cv := Px.blank(tank.get_width(), tank.get_height(), BG)
		put_tank(cv, tank, Vector2.ZERO, 0.0, st, float(L["ground"]))
		var c := cv.get_region(crop)
		var big := Px.scaled(c, 5)
		var fr := Px.blank(big.get_width() + 24 + crop.size.x, big.get_height() + 30, Color("#06090b"))
		fr.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(8, 24))
		var col_x := big.get_width() + 16
		Px.text(fr, 8, 6, "LOADER  %.1f S  %s" % [lt, str(Tank6.step_at(lt)["step"])], LABEL)
		Px.text(fr, col_x, 24, "1X (GAME SCALE)", DIM, false)
		fr.blend_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(col_x, 36))
		save(fr, "frames/loader/f%03d.png" % k)
		var s3 := Px.scaled(c, 3)
		var sf := Px.blank(s3.get_width(), s3.get_height() + 15, Color("#06090b"))
		sf.blend_rect(s3, Rect2i(Vector2i.ZERO, s3.get_size()), Vector2i(0, 15))
		Px.text(sf, 2, 2, "%.1f S %s" % [lt, str(Tank6.step_at(lt)["step"])], LABEL, true)
		small.append(sf)
	var picks: Array[Image] = []
	for k in 16:
		picks.append(small[int(k * n / 16.0)])
	save(strip(picks, 1, 4, "R6 LOADER: RACK > HOIST > STOW > FEED > BREECH OPEN > RAM > SHUT > RESET"), "loader_strip.png")


# --- the secondaries close-up: both receivers ----------------------------------------------------------------


func job_secbox() -> void:
	var crop := Rect2i(340, 100, 140, 90)
	for k in 36:
		var t := k / 12.0
		var st := state(t, CREW_DRIVE)
		st["travel"] = 0.0
		var tank := Tank6.frame(B, st)
		var cv := Px.blank(tank.get_width() + 120, tank.get_height(), BG)
		put_tank(cv, tank, Vector2.ZERO, 0.0, st, float(L["ground"]))
		var c := cv.get_region(crop)
		var big := Px.scaled(c, 5)
		var fr := Px.blank(big.get_width() + 24 + crop.size.x, big.get_height() + 30, Color("#06090b"))
		fr.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(8, 24))
		Px.text(fr, 8, 6, "SECONDARIES: BELT FEED > BOTH RECEIVERS > THE TWIN BOW GUNS (TRACERS, CASES)", LABEL)
		Px.text(fr, big.get_width() + 16, 24, "1X", DIM, false)
		fr.blend_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(big.get_width() + 16, 36))
		save(fr, "frames/secbox/f%03d.png" % k)
		if k == 5:
			save(fr, "secondaries_closeup.png")


# --- the hitbox: kit data and an overlay -------------------------------------------------------------------------


func job_hitbox() -> void:
	var st := state(2.2, CREW_HERO)
	st["elev"] = 0.0
	var tank := Tank6.frame(B, st)
	var w := tank.get_width()
	var h := tank.get_height()
	var excl: Array[Rect2i] = [
		Rect2i(200, 0, 12, 77), Rect2i(290, 50, 30, 27), Rect2i(250, 55, 30, 15), Rect2i(90, 80, 26, 18),
		Rect2i(366, 95, 110, 14), Rect2i(402, 120, 30, 10), Rect2i(432, 133, 30, 10)
	]
	var pts: Array[Vector2] = []
	for y in h:
		var lo := 99999
		var hi := -1
		for x in w:
			if tank.get_pixel(x, y).a < 0.5:
				continue
			var skip := false
			for r in excl:
				if r.has_point(Vector2i(x, y)):
					skip = true
			if skip:
				continue
			lo = mini(lo, x)
			hi = maxi(hi, x)
		if hi >= 0:
			pts.append_array([Vector2(lo, y), Vector2(hi + 1, y), Vector2(lo, y + 1), Vector2(hi + 1, y + 1)])
	var poly := Geometry2D.convex_hull(PackedVector2Array(pts))
	var simple := _simplify(poly, 1.5)
	var g: Dictionary = L["gun"]
	var tr: Vector2 = g["trunnion"]
	var data := {
		"note": "r6 tank collision data in sprite px (sprite 475 x 216, origin top-left, facing right; mirror x for west). hull_poly: the body's convex outline without the antenna, roof lamps, barrel and bow barrels. rects [x, y, w, h]: coarse parts for broad phase. Muzzles at elevation 0 and no recoil; the main gun's muzzle turns about the trunnion with elevation, the bow guns' about their pivots.",
		"sprite_size": [w, h],
		"ground_contact": {"y": 209, "x_from": 20, "x_to": 437},
		"hull_poly": _arr(simple),
		"rects": {"hull": [14, 112, 444, 75], "turret": [178, 77, 190, 41], "track_run": [18, 187, 422, 22]},
		"trunnion": [tr.x, tr.y],
		"muzzle": [tr.x + float(g["len"]), tr.y],
		"bow_pivots": [[400.0, 126.9], [430.2, 139.0]],
		"bow_muzzles": [[423.5, 126.9], [452.2, 139.0]],
		"headlight": [457.0, 164.0],
	}
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/tank_r6_hitbox.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	var cv := Px.blank(w + 8, h + 8, BG)
	cv.blend_rect(tank, Rect2i(Vector2i.ZERO, tank.get_size()), Vector2i(4, 4))
	var big := Px.scaled(cv, 4)
	var off := Vector2(4, 4)
	for kk in simple.size():
		var a := (simple[kk] + off) * 4.0
		var b := (simple[(kk + 1) % simple.size()] + off) * 4.0
		Px.linef(big, a, b, Color("#ffe040"))
		Px.linef(big, a + Vector2(0, 1), b + Vector2(0, 1), Color("#ffe040"))
	var cols := {"hull": Color("#40e0ff"), "turret": Color("#ff60c0"), "track_run": Color("#60ff80")}
	for key: String in data["rects"]:
		var r: Array = data["rects"][key]
		var rr := Rect2((Vector2(r[0], r[1]) + off) * 4.0, Vector2(r[2], r[3]) * 4.0)
		for x in range(int(rr.position.x), int(rr.end.x)):
			Px.put(big, x, int(rr.position.y), cols[key])
			Px.put(big, x, int(rr.end.y), cols[key])
		for y in range(int(rr.position.y), int(rr.end.y)):
			Px.put(big, int(rr.position.x), y, cols[key])
			Px.put(big, int(rr.end.x), y, cols[key])
	for mk: Array in [data["trunnion"], data["muzzle"], data["bow_muzzles"][0], data["bow_muzzles"][1], data["headlight"]]:
		var p := (Vector2(mk[0], mk[1]) + off) * 4.0
		Px.rect(big, Rect2i(int(p.x) - 4, int(p.y) - 4, 9, 9), Color("#ff3030"))
	var gyl := int((209.0 + off.y) * 4.0)
	for x in range(int((20 + off.x) * 4), int((437 + off.x) * 4)):
		Px.put(big, x, gyl, Color("#ffffff"))
	Px.text(big, 8, 8, "R6 HITBOX: YELLOW HULL POLYGON; CYAN HULL, PINK TURRET, GREEN TRACK RECTS; RED POINTS; WHITE GROUND LINE", LABEL)
	save(big, "tank_r6_hitbox_4x.png")


func _simplify(poly: PackedVector2Array, eps: float) -> PackedVector2Array:
	var o := PackedVector2Array()
	for i in poly.size():
		var a := poly[(i - 1 + poly.size()) % poly.size()]
		var b := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var d := c - a
		if absf(d.cross(b - a)) / maxf(d.length(), 0.001) > eps:
			o.append(b)
	return o


func _arr(p: PackedVector2Array) -> Array:
	var o: Array = []
	for v in p:
		o.append([v.x, v.y])
	return o


# --- the comparison: the reference, r5, r6 ---------------------------------------------------------------------


func job_compare() -> void:
	var ref := Image.new()
	ref.load_webp_from_buffer(FileAccess.get_file_as_bytes("res://assets/tank/v2/source/reference.webp"))
	ref.convert(Image.FORMAT_RGBA8)
	var rc := ref.get_region(Rect2i(30, 150, 520, 252))
	rc.resize(468, 227, Image.INTERPOLATE_LANCZOS)
	var rows: Array = [[rc, "REFERENCE (ITS TANK, X0.9)"]]
	var B5 := Tank5.build()
	for pair: Array in [[B5, "V3 R5", 5], [B, "V3 R6 (TWO TURRET WINDOWS, BOTH RECEIVERS, SUSPENSION, FIRING)", 6]]:
		var st := state(2.2, CREW_HERO)
		st["elev"] = 2.0
		st["load_t"] = 3.0
		var tank: Image = Tank5.frame(pair[0], st) if int(pair[2]) == 5 else Tank6.frame(pair[0], st)
		var LL: Dictionary = (pair[0] as Dictionary)["L"]
		var mine := Px.blank(tank.get_width() + 60, 227, BG)
		road(mine, 227 - 216 + int(LL["ground"]), 0.0)
		put_tank(mine, tank, Vector2(0, 227 - 216), 0.0, st, 227.0 - 216.0 + float(LL["ground"]), LL)
		rows.append([mine, pair[1]])
	var wmax := 0
	for r: Array in rows:
		wmax = maxi(wmax, (r[0] as Image).get_width())
	var o := Px.blank(wmax * 4 + 16, rows.size() * (227 * 4 + 40) + 8, Color("#06090b"))
	var y := 8
	for r: Array in rows:
		var im := Px.scaled(r[0], 4)
		var lab := Px.blank(Px.text_w(r[1]) + 2, 13)
		Px.text(lab, 0, 0, r[1], LABEL)
		var lab4 := Px.scaled(lab, 3)
		o.blend_rect(lab4, Rect2i(Vector2i.ZERO, lab4.get_size()), Vector2i(8, y))
		o.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(8, y + 36))
		y += 227 * 4 + 40
	save(o, "compare_ref_r5_r6_4x.png")

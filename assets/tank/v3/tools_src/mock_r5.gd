extends SceneTree
## Writes the r4 tank mockups (the reference re-pixelled, live parts redrawn) to build/v3mock/tank/r5/.
##   assets/tank/v3/tools_src/r5_base.sh first (the base), then
##   tools/godot.sh --headless --path . -s assets/tank/v3/tools_src/mock_r5.gd -- <job> [<job> ...]
## jobs: static, drive, tilt, loader, compare, arcs. GIFs: assets/tank/v3/tools_src/gifs_r3.sh r5.
## The forest backdrop is the env builder's moderate preview (read only, from the tank3-env worktree).

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const Tank = preload("res://assets/tank/v3/tools_src/tank.gd")
const Tank4 = preload("res://assets/tank/v3/tools_src/tank_r4.gd")
const Tank5 = preload("res://assets/tank/v3/tools_src/tank_r5.gd")
const Gear = preload("res://assets/tank/v3/tools_src/gear.gd")
const Light = preload("res://assets/tank/v3/tools_src/light.gd")

const OUT_DIR := "res://build/v3mock/tank/r5"
const ENV_BG := "C:/Projects/wt/tank3-env/assets/tank/v3env/planes/moderate/preview.png"
const BG := Color("#0a0f12")
const LABEL := Color("#e3a24a")
const DIM := Color("#a3937a")
## The hero crew: lights manned (searchlight on), the secondaries' seat empty.
const CREW_HERO := {"drive": 0, "gun": 2, "loader": 1, "lights": 3, "sec": -1}
## The driving crew: the secondaries manned (they tilt and fire), the lights' seat empty.
const CREW_DRIVE := {"drive": 0, "gun": 2, "loader": 1, "lights": -1, "sec": 3}
const RPM := {"drive": 82.0, "gun": 88.0, "loader": 90.0, "lights": 85.0, "sec": 95.0}
## Where the tank stands in the env frame (its road band runs y 378..393; v2's rear x).
const V2_GROUND_Y := 385
const V2_LEFT_X := 24

var B: Dictionary
var L: Dictionary


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	B = Tank5.build()
	L = B["L"]
	var jobs := OS.get_cmdline_user_args()
	if jobs.is_empty():
		jobs = PackedStringArray(["static"])
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
			"compare":
				job_compare()
			"arcs":
				job_arcs()
			"secbox":
				job_secbox()
		print("%s: %d ms" % [j, Time.get_ticks_msec() - tj])
	print("done in %d ms" % (Time.get_ticks_msec() - t0))
	quit()


func save(img: Image, name: String) -> void:
	var p := ProjectSettings.globalize_path(OUT_DIR + "/" + name)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_png(p)


func state(t: float, crew: Dictionary) -> Dictionary:
	return {
		"t": t, "travel": t * 40.0, "rpm": RPM, "crew": crew, "elev": 1.5 + 1.5 * sin(t * 1.6),
		"elev_rate": cos(t * 1.6), "sec_elev": 3.0 + 10.0 * sin(t * 2.4 + 1.0) if int(crew.get("sec", -1)) >= 0 else 2.0,
		"load_t": fposmod(t * 1.4 + 0.2, Tank.LOAD_CYCLE), "ready": 2,
		"sec_revs": t * RPM["sec"] / 60.0 if int(crew.get("sec", -1)) >= 0 else -1.0, "fire_t": t - 0.1,
		"search_on": int(crew.get("lights", -1)) >= 0,
	}


## A flat dark road under a level tank, its stones scrolling with `travel`.
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


## The tank composited at `at` (its local origin) onto `canvas`, with bloom and its own lights.
func put_tank(canvas: Image, tank: Image, at: Vector2i, search_on: bool, LL: Dictionary = {}) -> void:
	if LL.is_empty():
		LL = L
	var layer := Px.blank(canvas.get_width(), canvas.get_height())
	layer.blend_rect(tank, Rect2i(Vector2i.ZERO, tank.get_size()), at)
	canvas.blend_rect(tank, Rect2i(Vector2i.ZERO, tank.get_size()), at)
	var rect := Rect2i(at, tank.get_size())
	Light.bloom(canvas, layer, rect)
	Light.tank_lights(canvas, LL, Transform2D(0.0, Vector2(at)), search_on)


func env_backdrop() -> Image:
	var img := Image.load_from_file(ENV_BG)
	if img == null or img.is_empty():
		img = Px.blank(960, 540, BG)
	img.convert(Image.FORMAT_RGBA8)
	return img


# --- statics ------------------------------------------------------------------------------------------


func job_static() -> void:
	var st := state(2.2, CREW_HERO)
	st["fire_t"] = 99.0
	st["elev"] = 2.0
	var tank := Tank5.frame(B, st)
	var used := tank.get_used_rect()
	print("r3 used %s" % used)
	save(tank, "tank_r5_sprite_1x.png")
	# on a dark background
	var pad := Vector2i(16, 46)
	var cv := Px.blank(tank.get_width() + 260, tank.get_height() + 60, BG)
	road(cv, pad.y + int(L["ground"]), 0.0)
	put_tank(cv, tank, pad, true)
	save(cv, "tank_r5_dark_1x.png")
	save(Px.scaled(cv, 4), "tank_r5_dark_4x.png")
	# over the env builder's forest frame, at v2's place
	var env := env_backdrop()
	var at := Vector2i(V2_LEFT_X - 6, V2_GROUND_Y - int(L["ground"]))
	put_tank(env, tank, at, true)
	save(env, "tank_r5_forest_1x.png")
	save(Px.scaled(env, 2), "tank_r5_forest_2x.png")
	save(Px.scaled(env.get_region(Rect2i(0, 160, 620, 250)), 4), "tank_r5_forest_crop_4x.png")


# --- driving --------------------------------------------------------------------------------------------


func job_drive() -> void:
	var frames: Array[Image] = []
	for k in 48:
		var t := k / 12.0
		var st := state(t, CREW_DRIVE)
		var tank := Tank5.frame(B, st)
		var pad := Vector2i(16, 40)
		var cv := Px.blank(tank.get_width() + 240, tank.get_height() + 50, BG)
		road(cv, pad.y + int(L["ground"]), float(st["travel"]))
		put_tank(cv, tank, pad, false)
		frames.append(cv)
		save(Px.scaled(cv, 2), "frames/drive/f%03d.png" % k)
	save(strip(frames, 3, 4, "R5 DRIVING (LIGHTS SEAT EMPTY, SECONDARIES MANNED)"), "drive_strip.png")


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


# --- terrain tilt, method a ------------------------------------------------------------------------------


func ground_y(x: float) -> float:
	return 232.0 + 10.0 * sin(x * TAU / 600.0) + 1.5 * sin(x * TAU / 150.0 + 1.0) + 0.9 * sin(x * TAU / 37.0)


func job_tilt() -> void:
	var E := Tank.build(Tank.layout_enemy())
	var LE: Dictionary = E["L"]
	var env := env_backdrop()
	var size := Vector2i(760, 290)
	var frames: Array[Image] = []
	for k in 90:
		var t := k / 15.0
		var px_w := 60.0 + 40.0 * t
		var cam := px_w - 260.0
		var img := env.get_region(Rect2i(0, 90, size.x, size.y))
		# the bumpy road over the env frame's flat one
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
		# the enemy (method a too)
		var ex := 780.0 - 20.0 * t - cam
		var pe := Tank.pose(LE, ex, gfn, true)
		var ste := {"t": t, "travel": 20.0 * t, "elev": 2.0 + 3.0 * sin(t)}
		ste["wc"] = _local_wheels(LE, pe, gfn)
		var eimg := Tank.frame(E, ste)
		eimg.flip_x()
		var esrc := Vector2(LE["size"].x * 0.5, float(LE["ground"]))
		Px.rotate_nearest(eimg, pe["rot"], esrc, img, (pe["xf"] as Transform2D) * esrc)
		# the tank: the whole composed sprite rotated at render time, nearest
		var pp := Tank.pose(L, 260.0, gfn)
		var st := state(t, CREW_HERO)
		st["travel"] = 40.0 * t
		st["wc"] = _local_wheels(L, pp, gfn)
		var tank := Tank5.frame(B, st)
		var psrc := Vector2(L["size"].x * 0.5, float(L["ground"]))
		var xf: Transform2D = pp["xf"]
		var layer := Px.blank(size.x, size.y)
		Px.rotate_nearest(tank, pp["rot"], psrc, layer, xf * psrc)
		img.blend_rect(layer, Rect2i(Vector2i.ZERO, layer.get_size()), Vector2i.ZERO)
		var bb := layer.get_used_rect()
		Light.bloom(img, layer, bb)
		Light.tank_lights(img, L, xf, true)
		var dg := float(pp["deg"])
		Px.text(img, 6, 4, "R5  METHOD A: THE COMPOSED SPRITE ROTATED AT RENDER TIME (NEAREST)", LABEL)
		Px.text(img, 6, 17, "HULL %.1f DEG %s" % [absf(dg), "NOSE UP" if dg < 0.0 else "NOSE DOWN"], DIM, false)
		frames.append(img)
		save(Px.scaled(img, 2), "frames/tilt/f%03d.png" % k)
	save(strip(frames, 6, 3, "R5 TERRAIN TILT, METHOD A"), "tilt_a_strip.png")


func _local_wheels(LL: Dictionary, pose: Dictionary, gfn: Callable) -> Array[Vector2]:
	var xf: Transform2D = pose["xf"]
	var w := Gear.wheel_centres(LL["gear"], xf, gfn)
	var inv := xf.affine_inverse()
	var o: Array[Vector2] = []
	for p in w:
		o.append(inv * p)
	return o


# --- the loader close-up -----------------------------------------------------------------------------------


func job_loader() -> void:
	var crop := Rect2i(176, 60, 186, 128)
	var n := 70
	var small: Array[Image] = []
	for k in n:
		var lt := k * Tank.LOAD_CYCLE / n
		var st := state(2.0 + lt, CREW_HERO)
		st["load_t"] = lt
		st["elev"] = 3.0
		st["travel"] = 0.0
		st["fire_t"] = 99.0
		var tank := Tank5.frame(B, st)
		var cv := Px.blank(tank.get_width(), tank.get_height(), BG)
		put_tank(cv, tank, Vector2i.ZERO, false)
		var c := cv.get_region(crop)
		var big := Px.scaled(c, 5)
		var fr := Px.blank(big.get_width() + 24 + crop.size.x * 2, big.get_height() + 30, Color("#06090b"))
		fr.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(8, 24))
		var col_x := big.get_width() + 16
		Px.text(fr, 8, 6, "LOADER  %.1f S  %s" % [lt, str(Tank.load_step(lt)["step"])], LABEL)
		Px.text(fr, col_x, 24, "1X (GAME SCALE)", DIM, false)
		fr.blend_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(col_x, 36))
		Px.text(fr, col_x, 36 + crop.size.y + 10, "2X", DIM, false)
		var c2 := Px.scaled(c, 2)
		fr.blend_rect(c2, Rect2i(Vector2i.ZERO, c2.get_size()), Vector2i(col_x, 36 + crop.size.y + 22))
		save(fr, "frames/loader/f%03d.png" % k)
		var s3 := Px.scaled(c, 3)
		var sf := Px.blank(s3.get_width(), s3.get_height() + 15, Color("#06090b"))
		sf.blend_rect(s3, Rect2i(Vector2i.ZERO, s3.get_size()), Vector2i(0, 15))
		Px.text(sf, 2, 2, "%.1f S %s" % [lt, str(Tank.load_step(lt)["step"])], LABEL, true)
		small.append(sf)
	var picks: Array[Image] = []
	for k in 16:
		picks.append(small[int(k * n / 16.0)])
	save(strip(picks, 1, 4, "R5 LOADER: RACK > HOIST > BREECH OPEN > RAM > BREECH SHUT > TRAY DOWN"), "loader_strip.png")


# --- the comparison: the reference, v2's 4-rider, r3, same scale, 4x -------------------------------------


func job_compare() -> void:
	var ref := Image.new()
	ref.load_webp_from_buffer(FileAccess.get_file_as_bytes("res://assets/tank/v2/source/reference.webp"))
	ref.convert(Image.FORMAT_RGBA8)
	var rc := ref.get_region(Rect2i(30, 150, 520, 252))
	rc.resize(468, 227, Image.INTERPOLATE_LANCZOS)
	var v2 := Image.load_from_file(ProjectSettings.globalize_path("res://assets/tank/v2/tank_4rider.png"))
	var v2u := v2.get_used_rect()
	var v2c := Px.blank(v2u.size.x + 8, 227, BG)
	v2c.blend_rect(v2.get_region(v2u), Rect2i(Vector2i.ZERO, v2u.size), Vector2i(4, 227 - v2u.size.y - 4))
	var rows: Array = [[rc, "REFERENCE (ITS TANK, X0.9)"]]
	var B4 := Tank4.build()
	var L4: Dictionary = B4["L"]
	for pair: Array in [[B4, L4, "V3 R4", 4], [B, L, "V3 R5 (BRIGHTER, BIG WHEELS, CUTAWAYS, AIMED LIGHTS)", 5]]:
		var st := state(2.2, CREW_HERO)
		st["fire_t"] = 99.0
		st["elev"] = 2.0
		var tank: Image = Tank4.frame(pair[0], st) if int(pair[3]) == 4 else Tank5.frame(pair[0], st)
		var LL: Dictionary = pair[1]
		var mine := Px.blank(tank.get_width() + 60, 227, BG)
		road(mine, 227 - 216 + int(LL["ground"]), 0.0)
		put_tank(mine, tank, Vector2i(0, 227 - 216), true, LL)
		rows.append([mine, pair[2]])
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
	save(o, "compare_ref_r4_r5_4x.png")
	var o2 := o.duplicate() as Image
	o2.resize(o.get_width() / 4, o.get_height() / 4, Image.INTERPOLATE_NEAREST)
	save(o2, "compare_ref_r4_r5_1x.png")


# --- the two angle widgets ---------------------------------------------------------------------------------


func job_arcs() -> void:
	var st := state(2.2, CREW_HERO)
	st["elev"] = 12.0
	st["sec_elev"] = 8.0
	st["fire_t"] = 99.0
	var tank := Tank5.frame(B, st)
	var off := Vector2i(10, 40)
	var cv := Px.blank(tank.get_width() + 90, tank.get_height() + 50, BG)
	road(cv, off.y + int(L["ground"]), 0.0)
	put_tank(cv, tank, off, true)
	var keep := PackedByteArray()
	keep.resize(cv.get_width() * cv.get_height())
	for y in tank.get_height():
		for x in tank.get_width():
			if tank.get_pixel(x, y).a > 0.5:
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var X := x + off.x + dx
						var Y := y + off.y + dy
						if X >= 0 and Y >= 0 and X < cv.get_width() and Y < cv.get_height():
							keep[Y * cv.get_width() + X] = 1
	var g: Dictionary = L["gun"]
	var s: Dictionary = L["bow"][0]
	_arc(cv, keep, (g["trunnion"] as Vector2) + Vector2(off), float(g["len"]) + 8.0, -12.0, 30.0, 12.0, 15.0, Color("#e3a24a"), Color("#9fd4ec"), true)
	_arc(cv, keep, (s["pivot"] as Vector2) + Vector2(off), float(s["len"]) + 7.0, -10.0, 20.0, 8.0, 14.0, Color("#cfe6ff"), Color("#7fb6e8"), false)
	save(Px.scaled(cv, 2), "arcs_2x.png")
	save(Px.scaled(cv.get_region(Rect2i(320, 10, cv.get_width() - 320, 200)), 4), "arcs_crop_4x.png")


func _arc(
	cv: Image, keep: PackedByteArray, piv: Vector2, r: float, lo: float, hi: float, elev: float, order: float,
	col: Color, ord_col: Color, tall: bool
) -> void:
	var w := cv.get_width()
	var put := func(p: Vector2, c: Color, a: float) -> void:
		var x := floori(p.x)
		var y := floori(p.y)
		if x < 0 or y < 0 or x >= w or y >= cv.get_height() or keep[y * w + x] != 0:
			return
		Px.mix(cv, x, y, c, a)
	var dirf := func(deg: float) -> Vector2: return Vector2(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg)))
	var steps := ceili((hi - lo) * r / 57.3 * 2.0)
	for k in steps + 1:
		put.call(piv + (dirf.call(lerpf(lo, hi, float(k) / steps)) as Vector2) * r, col, 0.6)
	var deg := ceilf(lo / 10.0) * 10.0
	while deg <= hi:
		for rr in [r + 1.0, r + 2.0]:
			put.call(piv + (dirf.call(deg) as Vector2) * rr, col, 0.6)
		deg += 10.0
	for rr in range(int(r) + 3, int(r) + 7):
		put.call(piv + (dirf.call(order) as Vector2) * rr, ord_col, 1.0)
	for rr in range(int(r) - 2, int(r) + 4):
		put.call(piv + (dirf.call(elev) as Vector2) * rr, col, 1.0)
	var lab := ("+" if elev > 0 else "") + str(roundi(elev)) + "°"
	if tall:
		var end: Vector2 = piv + (dirf.call(hi) as Vector2) * (r + 4.0)
		Px.text(cv, floori(end.x) + 2, floori(end.y) - 12, lab, col)
	else:
		var e2: Vector2 = piv + (dirf.call(lo) as Vector2) * (r + 4.0)
		Px.text(cv, floori(e2.x) + 2, floori(e2.y) + 1, lab, col, false)


# --- the secondaries close-up: the front room's belt feed and the bow guns' opened box ----------------


func job_secbox() -> void:
	var crop := Rect2i(340, 104, 120, 84)
	var crew := {"drive": 0, "gun": 2, "loader": 1, "lights": -1, "sec": 3}
	for k in 36:
		var t := k / 12.0
		var st := state(t, crew)
		st["travel"] = 0.0
		var tank := Tank5.frame(B, st)
		var cv := Px.blank(tank.get_width(), tank.get_height(), BG)
		put_tank(cv, tank, Vector2i.ZERO, false)
		var c := cv.get_region(crop)
		var big := Px.scaled(c, 5)
		var fr := Px.blank(big.get_width() + 24 + crop.size.x, big.get_height() + 30, Color("#06090b"))
		fr.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(8, 24))
		Px.text(fr, 8, 6, "SECONDARIES: BELT FEED (FRONT ROOM) > THE BOX'S RECEIVERS > THE TWIN BOW GUNS", LABEL)
		Px.text(fr, big.get_width() + 16, 24, "1X", DIM, false)
		fr.blend_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(big.get_width() + 16, 36))
		save(fr, "frames/secbox/f%03d.png" % k)
		if k == 4:
			save(fr, "secondaries_closeup.png")

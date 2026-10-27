extends SceneTree
## Writes the v3 tank mockups to build/v3mock/tank/ (see notes.md there).
##   tools/godot.sh --headless --path . -s assets/tank/v3/tools_src/mock_v3.gd -- <job> [<job> ...]
## jobs: static, drive, loader, bays, tilt, arc, sheet. GIFs: assets/tank/v3/tools_src/gifs.sh.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const Tank = preload("res://assets/tank/v3/tools_src/tank.gd")
const Gear = preload("res://assets/tank/v3/tools_src/gear.gd")
const Hull = preload("res://assets/tank/v3/tools_src/hull.gd")

const OUT_DIR := "res://build/v3mock/tank"
const BG := Color("#0c1216")
const LABEL := Color("#e3a24a")
const DIM := Color("#a3937a")
const CREW := {"drive": 0, "loader": 1, "gun": 2, "sec": 3, "lights": -1}
const CREW_ALL := {"drive": 0, "loader": 1, "gun": 2, "sec": 3, "lights": 0}
const RPM := {"drive": 82.0, "gun": 88.0, "loader": 90.0, "lights": 85.0, "sec": 95.0}
const ARC_MAIN := Color("#e3a24a")
const ARC_COOL := Color("#9fd4ec")
const ARC_SEC := Color("#cfe6ff")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
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
			"loader":
				job_loader()
			"bays":
				job_bays()
			"tilt":
				job_tilt(["A"])
			"tilt_all":
				job_tilt(["B", "C"])
			"arc":
				job_arc()
			"sheet":
				job_sheet()
		print("%s: %d ms" % [j, Time.get_ticks_msec() - tj])
	print("done in %d ms" % (Time.get_ticks_msec() - t0))
	quit()


func path(name: String) -> String:
	return ProjectSettings.globalize_path(OUT_DIR + "/" + name)


func save(img: Image, name: String) -> void:
	var p := path(name)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_png(p)


func on_bg(img: Image, pad: int, bg := BG) -> Image:
	var o := Px.blank(img.get_width() + pad * 2, img.get_height() + pad * 2, bg)
	o.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(pad, pad))
	return o


func layout(name: String) -> Dictionary:
	for L: Dictionary in Tank.layouts():
		if L["name"] == name:
			return L
	return {}


func base_state(t: float) -> Dictionary:
	return {
		"t": t, "travel": t * 40.0, "rpm": RPM, "crew": CREW, "elev": 6.0, "sec_elev": 4.0,
		"load_t": fposmod(t, Tank.LOAD_CYCLE), "ready": 2, "sec_revs": t * RPM["sec"] / 60.0,
	}


## The driving state at time t: guns laying up and down, the loader mid-cycle, one shot at the start.
func drive_state(t: float) -> Dictionary:
	var st := base_state(t)
	st["elev"] = 7.0 + 9.0 * sin(t * 1.6)
	st["elev_rate"] = cos(t * 1.6)
	st["sec_elev"] = 4.0 + 10.0 * sin(t * 2.4 + 1.0)
	st["load_t"] = fposmod(t * 1.4 + 0.2, Tank.LOAD_CYCLE)
	st["fire_t"] = t - 0.1
	return st


## A dark road strip under a level tank: earth with stones that scroll with `travel`.
func road(img: Image, y: int, travel: float, x0 := 0, x1 := -1) -> void:
	if x1 < 0:
		x1 = img.get_width()
	for x in range(x0, x1):
		var wx := x + floori(travel)
		for yy in range(y, img.get_height()):
			var d := yy - y
			var col := Color("#1b1d17") if d > 1 else Color("#34352a")
			if d == 0:
				col = Color("#3f3f31")
			if d > 2 and Px.h2(wx, yy, 77) > 0.93:
				col = Color("#2c2d24")
			if d > 1 and d < 5 and Px.h2(wx / 2, yy, 78) > 0.9:
				col = Color("#4a4838")
			img.set_pixel(x, yy, col)


# --- static options ---------------------------------------------------------------------------------


func job_static() -> void:
	for L: Dictionary in Tank.layouts():
		var B := Tank.build(L)
		var st := base_state(2.2)
		st["fire_t"] = 99.0
		var img := Tank.frame(B, st)
		var used := img.get_used_rect()
		print("%s used %s (size %dx%d)" % [L["name"], used, used.size.x, used.size.y])
		var one := on_bg(img, 8)
		road(one, 8 + int(L["ground"]), 0.0)
		save(one, "option_%s_1x.png" % L["name"])
		save(Px.scaled(one, 4), "option_%s_4x.png" % L["name"])


# --- drive animations ---------------------------------------------------------------------------------


func job_drive() -> void:
	for L: Dictionary in Tank.layouts():
		var B := Tank.build(L)
		var n := 48
		var frames: Array[Image] = []
		for k in n:
			var t := k / 12.0
			var st := drive_state(t)
			var img := Tank.frame(B, st)
			var one := on_bg(img, 8)
			road(one, 8 + int(L["ground"]), float(st["travel"]))
			frames.append(one)
			save(Px.scaled(one, 2), "frames/drive_%s/f%03d.png" % [L["name"], k])
		save(strip(frames, 3, 4, "DRIVE %s" % L["name"]), "drive_%s_strip.png" % L["name"])


## A grid of every `every`-th frame (16 of them), `cols` wide, frame numbers in the corner.
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


# --- the loader close-up ---------------------------------------------------------------------------


func job_loader() -> void:
	var L := layout("A")
	var B := Tank.build(L)
	var crop := Rect2i(214, 38, 120, 108)
	var n := 70
	var frames: Array[Image] = []
	var small: Array[Image] = []
	for k in n:
		var lt := k * Tank.LOAD_CYCLE / n
		var st := base_state(2.0 + lt)
		st["load_t"] = lt
		st["elev"] = 4.0
		st["travel"] = 0.0
		st["fire_t"] = 99.0
		var img := Tank.frame(B, st)
		var bgi := on_bg(img, 0)
		var c := bgi.get_region(crop)
		var big := Px.scaled(c, 5)
		var fr := Px.blank(big.get_width() + 24 + crop.size.x * 2, big.get_height() + 30, Color("#06090b"))
		fr.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(8, 24))
		var col_x := big.get_width() + 16
		Px.text(fr, 8, 6, "LOADER  %.1f S  %s   READY RACK 2/3 (TURRET, LEFT OF THE HOIST)" % [lt, str(Tank.load_step(lt)["step"])], LABEL)
		Px.text(fr, col_x, 24, "1X (GAME SCALE)", DIM, false)
		fr.blend_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(col_x, 36))
		Px.text(fr, col_x, 36 + crop.size.y + 10, "2X", DIM, false)
		var c2 := Px.scaled(c, 2)
		fr.blend_rect(c2, Rect2i(Vector2i.ZERO, c2.get_size()), Vector2i(col_x, 36 + crop.size.y + 22))
		frames.append(fr)
		save(fr, "frames/loader/f%03d.png" % k)
		# the strip: 1x crops at 3x with the step
		var s3 := Px.scaled(c, 3)
		var sf := Px.blank(s3.get_width(), s3.get_height() + 15, Color("#06090b"))
		sf.blend_rect(s3, Rect2i(Vector2i.ZERO, s3.get_size()), Vector2i(0, 15))
		Px.text(sf, 2, 2, "%.1f S %s" % [lt, str(Tank.load_step(lt)["step"])], LABEL, true)
		small.append(sf)
	# 16 frames across the cycle
	var picks: Array[Image] = []
	for k in 16:
		picks.append(small[int(k * n / 16.0)])
	save(strip(picks, 1, 4, "LOADER CYCLE (OPTION A): RACK > HOIST > BREECH OPEN > RAM > BREECH SHUT > TRAY DOWN"), "loader_strip.png")
	# the bay at 1x inside the whole tank, the crop boxed
	var st2 := base_state(2.0 + 4.2)
	st2["load_t"] = 4.2
	st2["elev"] = 4.0
	st2["fire_t"] = 99.0
	var whole := on_bg(Tank.frame(B, st2), 8)
	var bx := Rect2i(crop.position + Vector2i(8, 8), crop.size)
	for x in range(bx.position.x, bx.end.x):
		Px.put(whole, x, bx.position.y - 1, LABEL)
		Px.put(whole, x, bx.end.y, LABEL)
	for y in range(bx.position.y, bx.end.y):
		Px.put(whole, bx.position.x - 1, y, LABEL)
		Px.put(whole, bx.end.x, y, LABEL)
	save(whole, "loader_in_tank_1x.png")
	save(Px.scaled(whole, 2), "loader_in_tank_2x.png")


# --- the five bays up close (all five crewed, so every machine runs) ---------------------------------


func job_bays() -> void:
	var L := layout("A")
	var B := Tank.build(L)
	var n := 24
	for k in n:
		var t := k / 12.0
		var st := drive_state(t)
		st["crew"] = CREW_ALL
		st["fire_t"] = 99.0
		st["load_t"] = fposmod(1.0 + t * 1.5, Tank.LOAD_CYCLE)
		var img := Tank.frame(B, st)
		var bays: Array = L["bays"]
		var tiles: Array[Image] = []
		var tw := 0
		for b: Dictionary in bays:
			var r: Rect2i = b["rect"]
			var rr := Rect2i(r.position.x - 3, r.position.y - 4, r.size.x + 6, r.size.y + 8)
			if str(b["id"]) == "sec":
				rr = Rect2i(r.position.x - 3, r.position.y - 16, r.size.x + 30, r.size.y + 20)
			if str(b["id"]) == "loader":
				rr = Rect2i(r.position.x - 3, 40, r.size.x + 46, r.end.y + 4 - 40)
			var tile := Px.scaled(on_bg(img, 0).get_region(rr), 3)
			tiles.append(tile)
			tw += tile.get_width() + 6
		var th := 0
		for tl in tiles:
			th = maxi(th, tl.get_height())
		var o := Px.blank(tw + 6, th + 26, Color("#06090b"))
		var x := 6
		var names := ["DRIVE  DIESEL", "LIGHTS  ARC GENERATOR", "GUN  DYNAMO", "LOADER  STEAM + HOIST", "SECONDARIES  TWIN BELT FEED"]
		for i in tiles.size():
			o.blend_rect(tiles[i], Rect2i(Vector2i.ZERO, tiles[i].get_size()), Vector2i(x, 22 + th - tiles[i].get_height()))
			Px.text(o, x, 6, names[i], LABEL, false)
			x += tiles[i].get_width() + 6
		save(o, "frames/bays/f%03d.png" % k)
		if k == 6:
			save(o, "bays_A_3x.png")


# --- terrain tilt ---------------------------------------------------------------------------------------


func ground_y(x: float) -> float:
	return 224.0 + 12.0 * sin(x * TAU / 600.0) + 1.6 * sin(x * TAU / 150.0 + 1.0) + 0.9 * sin(x * TAU / 37.0)


func scene_bg(img: Image, cam: float) -> void:
	var h := img.get_height()
	for y in h:
		var c := Color("#0a1418").lerp(Color("#14262a"), float(y) / h)
		for x in img.get_width():
			img.set_pixel(x, y, c)
	# a far tree line, parallax 0.3
	for x in img.get_width():
		var wx := x + cam * 0.3
		var top := 150.0 + 10.0 * Px.vnoise(wx, 0, 23.0, 5) + 8.0 * Px.vnoise(wx, 0, 6.0, 6)
		for y in range(int(top), h):
			img.set_pixel(x, y, Color("#0d1b1c"))
	for x in img.get_width():
		var wx := cam + x + 0.5
		var gy := ground_y(wx)
		for y in range(floori(gy), h):
			var d := float(y) - gy
			var col := Color("#1b1f19") if d > 2.0 else Color("#3a3c2e")
			if d < 1.0:
				col = Color("#4a4a38")
			if d > 2.0 and Px.h2(floori(wx), y, 77) > 0.94:
				col = Color("#2e3127")
			if d > 1.0 and d < 6.0 and Px.h2(floori(wx) / 2, y, 78) > 0.9:
				col = Color("#4c4b3a")
			img.set_pixel(x, y, col)


## One tilt scene frame: the player tank `L` and the enemy over the bumpy road, by `method`:
## a = the composed sprite rotated at render time (nearest), b = the composed sprite RotSprite-rotated
## at whole-degree steps, c = per part: the hull RotSprite at 1 deg, running gear and guns drawn in
## world space every frame (wheels on the ground).
func tilt_frame(B: Dictionary, E: Dictionary, t: float, method: String, size: Vector2i) -> Dictionary:
	var L: Dictionary = B["L"]
	var LE: Dictionary = E["L"]
	var px_w := 60.0 + 40.0 * t
	var cam := px_w - 250.0
	var img := Px.blank(size.x, size.y)
	scene_bg(img, cam)
	var gfn := func(x: float) -> float: return ground_y(x + cam)
	var info := {}
	# the enemy first (behind), driving west
	var ex := 750.0 - 20.0 * t - cam
	var pe := Tank.pose(LE, ex, gfn, true)
	var ste := {"t": t, "travel": 20.0 * t, "elev": 2.0 + 3.0 * sin(t), "gear": true}
	ste["wc"] = _local_wheels(LE, pe, gfn)
	var eimg := Tank.frame(E, ste)
	eimg.flip_x()
	var episrc := Vector2(LE["size"].x * 0.5, float(LE["ground"]))
	var epdst: Vector2 = (pe["xf"] as Transform2D) * Vector2(LE["size"].x * 0.5, float(LE["ground"]))
	if method == "a":
		Px.rotate_nearest(eimg, pe["rot"], episrc, img, epdst)
	else:
		var erq := deg_to_rad(roundf(float(pe["deg"])))
		Px.rotate_rotsprite(Px.rotsprite_prep(eimg), erq, episrc, img, epdst)
	# the player
	var pp := Tank.pose(L, 250.0, gfn)
	var st := drive_state(t)
	st["travel"] = 40.0 * t
	var psrc := Vector2(L["size"].x * 0.5, float(L["ground"]))
	var pdst: Vector2 = (pp["xf"] as Transform2D) * psrc
	info["deg"] = pp["deg"]
	if method == "a" or method == "b":
		st["wc"] = _local_wheels(L, pp, gfn)
		var timg := Tank.frame(B, st)
		if method == "a":
			Px.rotate_nearest(timg, pp["rot"], psrc, img, pdst)
		else:
			var rq := deg_to_rad(roundf(float(pp["deg"])))
			Px.rotate_rotsprite(Px.rotsprite_prep(timg), rq, psrc, img, pdst)
	else:
		var rq2 := deg_to_rad(roundf(float(pp["deg"])))
		var xq := Transform2D(rq2, Vector2.ZERO)
		xq.origin = pdst - xq.basis_xform(psrc)
		var wcw := Gear.wheel_centres(L["gear"], xq, gfn)
		st["gear"] = false
		st["guns"] = false
		var body := Tank.frame(B, st)
		Gear.draw_back(img, L["gear"], xq, wcw, float(st["travel"]))
		Px.rotate_rotsprite(Px.rotsprite_prep(body), rq2, psrc, img, pdst)
		Gear.draw_front(img, L["gear"], xq, wcw, float(st["travel"]))
		Tank.guns(img, L, xq, st)
	return {"img": img, "deg": info["deg"]}


## The road wheels' centres in a hull's local px for its pose over the ground.
func _local_wheels(L: Dictionary, pose: Dictionary, gfn: Callable) -> Array[Vector2]:
	var xf: Transform2D = pose["xf"]
	var w := Gear.wheel_centres(L["gear"], xf, gfn)
	var inv := xf.affine_inverse()
	var o: Array[Vector2] = []
	for p in w:
		o.append(inv * p)
	return o


func job_tilt(names: Array) -> void:
	var E := Tank.build(Tank.layout_enemy())
	var titles := {
		"a": "(A) TRUE ROTATION AT RENDER TIME, NEAREST",
		"b": "(B) ROTSPRITE OF THE COMPOSED SPRITE, 1 DEG STEPS",
		"c": "(B2) PER PART: HULL ROTSPRITE 1 DEG + GEAR AND GUNS IN WORLD",
	}
	for name: String in names:
		var B := Tank.build(layout(name))
		var size := Vector2i(720, 270)
		for m: String in ["a", "b", "c"]:
			var n := 90
			var frames: Array[Image] = []
			for k in n:
				var t := k / 15.0
				var r := tilt_frame(B, E, t, m, size)
				var img: Image = r["img"]
				Px.text(img, 6, 4, "OPTION %s  %s" % [name, titles[m]], LABEL)
				var dg := float(r["deg"])
				Px.text(img, 6, 17, "HULL %.1f DEG %s" % [absf(dg), "NOSE UP" if dg < 0.0 else "NOSE DOWN"], DIM, false)
				frames.append(img)
				save(Px.scaled(img, 2), "frames/tilt_%s_%s/f%03d.png" % [name, m, k])
			save(strip(frames, 6, 3, "TILT %s %s" % [name, titles[m]]), "tilt_%s_%s_strip.png" % [name, m])
			print("tilt %s %s done" % [name, m])


# --- the elevation arcs --------------------------------------------------------------------------------


func job_arc() -> void:
	var L := layout("A")
	var B := Tank.build(L)
	var st := base_state(2.2)
	st["elev"] = 12.0
	st["sec_elev"] = 8.0
	st["fire_t"] = 99.0
	var tank := Tank.frame(B, st)
	var off := Vector2i(10, 40)
	var cv := Px.blank(tank.get_width() + 70, tank.get_height() + 50, BG)
	cv.blend_rect(tank, Rect2i(Vector2i.ZERO, tank.get_size()), off)
	road(cv, off.y + int(L["ground"]), 0.0)
	# keep-out: the tank's opaque pixels grown by 2
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
	var s: Dictionary = L["sec"]
	_arc(cv, keep, (g["trunnion"] as Vector2) + Vector2(off), float(g["len"]) + 8.0, -12.0, 30.0, 12.0, 15.0, ARC_MAIN, ARC_COOL, true)
	_arc(cv, keep, (s["pivot"] as Vector2) + Vector2(off), float(s["len"]) + 7.0, -10.0, 20.0, 8.0, 14.0, ARC_SEC, Color("#7fb6e8"), false)
	save(Px.scaled(cv, 2), "arcs_A_2x.png")
	var crop := cv.get_region(Rect2i(300, 0, cv.get_width() - 300, 175))
	save(Px.scaled(crop, 4), "arcs_A_crop_4x.png")


## A v2-style elevation arc: the arc (col at 0.6), a tick per 10 deg, the actual elevation's mark,
## the ordered elevation's mark outside, the label past the upper end; never on `keep`.
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
		var d: Vector2 = dirf.call(lerpf(lo, hi, float(k) / steps))
		put.call(piv + d * r, col, 0.6)
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
	var end: Vector2 = piv + (dirf.call(hi) as Vector2) * (r + 4.0)
	if tall:
		Px.text(cv, floori(end.x) + 2, floori(end.y) - 12, lab, col)
	else:
		var e2: Vector2 = piv + (dirf.call(lo) as Vector2) * (r + 4.0)
		Px.text(cv, floori(e2.x) + 2, floori(e2.y) + 1, lab, col, false)


# --- contact sheet ----------------------------------------------------------------------------------------


func job_sheet() -> void:
	var tiles: Array[Image] = []
	var labels: Array[PackedStringArray] = []
	var maxh := 0
	for L: Dictionary in Tank.layouts():
		var B := Tank.build(L)
		var st := base_state(2.2)
		st["fire_t"] = 99.0
		var img := Tank.frame(B, st)
		var used := img.get_used_rect()
		var one := on_bg(img, 6)
		road(one, 6 + int(L["ground"]), 0.0)
		tiles.append(Px.scaled(one, 2))
		var gear: Dictionary = L["gear"]
		labels.append(PackedStringArray([
			str(L["title"]),
			"%d X %d ART PX (WITH GUN), TRACK %d PX" % [used.size.x, used.size.y, _track_len(L)],
		]))
		maxh = maxi(maxh, tiles[-1].get_height())
	var v2 := Image.load_from_file(ProjectSettings.globalize_path("res://assets/tank/v2/tank_4rider.png"))
	var v2u := v2.get_used_rect()
	var v2one := on_bg(v2.get_region(v2u), 6)
	tiles.append(Px.scaled(v2one, 2))
	labels.append(PackedStringArray(["V2 4-RIDER (CUT-OUT), FOR SCALE", "%d X %d ART PX" % [v2u.size.x, v2u.size.y]]))
	maxh = maxi(maxh, tiles[-1].get_height())
	var tw := 0
	for tl in tiles:
		tw += tl.get_width() + 16
	var o := Px.blank(tw + 16, maxh + 90, Color("#06090b"))
	label2x(o, 16, 6, "DIESEL DOMESTIQUES V3: TANK RECONSTRUCTION OPTIONS (2X, SAME SCALE AS V2)", LABEL, true)
	var x := 16
	for i in tiles.size():
		var y := 34 + maxh - tiles[i].get_height()
		o.blend_rect(tiles[i], Rect2i(Vector2i.ZERO, tiles[i].get_size()), Vector2i(x, y))
		label2x(o, x, 30 + maxh + 8, labels[i][0], LABEL, true)
		label2x(o, x, 30 + maxh + 34, labels[i][1], DIM, false)
		x += tiles[i].get_width() + 16
	save(o, "contact_sheet.png")


## Text at 2x (the pixel font doubled), for the 2x contact sheet.
func label2x(o: Image, x: int, y: int, s: String, c: Color, tall: bool) -> void:
	var t := Px.blank(Px.text_w(s) + 2, 13, Color(0, 0, 0, 0))
	Px.text(t, 0, 0, s, c, tall)
	var t2 := Px.scaled(t, 2)
	o.blend_rect(t2, Rect2i(Vector2i.ZERO, t2.get_size()), Vector2i(x, y))


func _track_len(L: Dictionary) -> int:
	var g: Dictionary = L["gear"]
	var idl: Dictionary = g["idler"]
	var sp: Dictionary = g["sprocket"]
	var x0 := (idl["c"] as Vector2).x - float(idl["r"]) - float(g["T"])
	var x1 := (sp["c"] as Vector2).x + float(sp["r"]) + float(g["T"])
	return roundi(x1 - x0)

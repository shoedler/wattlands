extends SceneTree
## Bakes the production v3 tank kit (assets/tank/v3/) from the r6 generator:
##   tank_base.png        the r6 base (the reference's tank re-pixelled, 63 colours) with its static
##                        dressing: the quarters' sitters, the commander in the cupola, the rear
##                        searchlight on its post and the turret searchlight unlit
##   tank_lit.png         the turret searchlight's lit lens (a small overlay, kit.json "lit")
##   gear_*.png           road wheel, sprocket, idler and return roller frames over their symmetry
##   track.png            one track shoe (4 sub-px per px along the shoe, 2 per px across), the top
##                        run's lit rows over the unlit ones; the view maps it along the belt
##   barrel.png, bow_*.png the main gun and the bow guns at 0 degrees (the view rotates them)
##   blast_air.png        the main gun's blast at 30 fps along the bore (star flash, brake jets,
##                        fire ball and fragments, the smoke cloud and ring); the sparks are drawn
##                        by the view
##   blast_ground.png     the blast's dust under the muzzle at 30 fps (the dust, the shockwave
##                        along the road, the pebbles)
##   (planes/*.png, the forest planes at moderate tilt-shift, come from env_planes.gd; kit.json lists them)
##   kit.json             every rect, anchor, room, wheel, window, lamp and sheet the view reads
## Run: bash assets/tank/v3/tools_src/bake.sh (it runs r6_base.sh first).

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const Gear = preload("res://assets/tank/v3/tools_src/gear.gd")
const Dress = preload("res://assets/tank/v3/tools_src/dress.gd")
const Tank5 = preload("res://assets/tank/v3/tools_src/tank_r5.gd")
const Tank6 = preload("res://assets/tank/v3/tools_src/tank_r6.gd")

const OUT := "res://assets/tank/v3/"
## The forest planes (env_planes.gd bakes them into planes/): stage y of their top on the 960 x 540
## stage (the road line at 385), parallax, and the layer: back (behind the world), road (the verge
## under the road band), near (the near shoulder over the road band's near rows), front (over the
## tank).
const PLANES := [
	{"name": "far", "y0": -35.0, "parallax": 0.04, "layer": "back"},
	{"name": "ridge", "y0": 45.0, "parallax": 0.12, "layer": "back"},
	{"name": "forest", "y0": 45.0, "parallax": 0.3, "layer": "back"},
	{"name": "verge", "y0": 341.0, "parallax": 1.0, "layer": "road"},
	{"name": "near", "y0": 401.0, "parallax": 1.0, "layer": "near"},
	{"name": "foreground", "y0": 389.0, "parallax": 1.35, "layer": "front"},
]
## The turret block (sprite px): everything the traverse mirrors about TURRET_PIVOT_X.
const TURRET := Rect2i(176, 0, 196, 113)
const TURRET_PIVOT_X := 272.0
const FPS := 30.0
const AIR_BOX := Rect2i(-20, -96, 168, 150)
const GROUND_BOX := Rect2i(-160, -66, 320, 70)
const GROUND_FRAMES := 48
const AIR_FRAMES := 60
const SHEET_COLS := 10

var L: Dictionary
var B: Dictionary


func _init() -> void:
	B = Tank6.build()
	L = B["L"]
	var kit := {}
	kit["note"] = "The v3 tank kit (assets/tank/v3/tools_src/bake.gd). Sprite px, origin top-left, facing right."
	kit["size"] = [int(L["size"].x), int(L["size"].y)]
	kit["ground"] = float(L["ground"])
	_base(kit)
	_gear(kit)
	_track(kit)
	_guns(kit)
	_blast(kit)
	_planes(kit)
	_layout(kit)
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT + "kit.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(kit, "  ", false))
	f.close()
	print("bake done")
	quit()


func save(img: Image, rel: String) -> void:
	var p := ProjectSettings.globalize_path(OUT + rel)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_png(p)


# --- the base ------------------------------------------------------------------------------------------


func _dressed(lit: bool) -> Image:
	var sz: Vector2i = L["size"]
	var img := Px.blank(sz.x, sz.y)
	img.blend_rect(B["img"], Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
	Dress._open = B["open"]
	Dress._w = int(B["w"])
	Dress._h = int(B["h"])
	Dress._g = 6
	var q: Rect2i = L["rooms"]["quarters"]
	for k in [0, 2, 3, 5]:
		Dress.sitter(img, q.position.x + 14 + k * 20, q.end.y - 1, 1 if k % 2 == 0 else -1, k)
	Tank5.roof(img, {"search_on": lit})
	return img


func _base(kit: Dictionary) -> void:
	var dark := _dressed(false)
	var lit := _dressed(true)
	save(dark, "tank_base.png")
	var bb := Rect2i()
	var first := true
	for y in dark.get_height():
		for x in dark.get_width():
			if not dark.get_pixel(x, y).is_equal_approx(lit.get_pixel(x, y)):
				var r := Rect2i(x, y, 1, 1)
				bb = r if first else bb.merge(r)
				first = false
	var ov := Px.blank(bb.size.x, bb.size.y)
	for y in bb.size.y:
		for x in bb.size.x:
			var p := bb.position + Vector2i(x, y)
			if not dark.get_pixel(p.x, p.y).is_equal_approx(lit.get_pixel(p.x, p.y)):
				ov.set_pixel(x, y, lit.get_pixel(p.x, p.y))
	save(ov, "tank_lit.png")
	kit["base"] = "tank_base.png"
	kit["lit"] = {"file": "tank_lit.png", "at": [bb.position.x, bb.position.y]}
	kit["turret"] = {"rect": [TURRET.position.x, TURRET.position.y, TURRET.size.x, TURRET.size.y], "pivot_x": TURRET_PIVOT_X}


# --- running gear ----------------------------------------------------------------------------------------


func _sheet(kind: String, r: float, frames: int, period: float, half: int) -> Dictionary:
	var size := half * 2
	var img := Px.blank(size * frames, size)
	for k in frames:
		var one := Px.blank(size, size)
		Gear.draw_wheel(one, Vector2(half, half), r, period * k / frames, kind)
		img.blend_rect(one, Rect2i(0, 0, size, size), Vector2i(k * size, 0))
	save(img, "gear_%s.png" % kind)
	return {"file": "gear_%s.png" % kind, "frames": frames, "period": period, "size": size, "r": r}


func _gear(kit: Dictionary) -> void:
	var g: Dictionary = L["gear"]
	var sp: Dictionary = g["sprocket"]
	var idl: Dictionary = g["idler"]
	var rl: Dictionary = g["rollers"][0]
	var w0: Dictionary = g["wheels"][0]
	var sheets := {
		"road": _sheet("road", float(w0["r"]), 12, TAU / 6.0, 14),
		"sprocket": _sheet("sprocket", float(sp["r"]), 48, TAU, 21),
		"idler": _sheet("idler", float(idl["r"]), 12, TAU / 5.0, 13),
		"roller": _sheet("roller", float(rl["r"]), 6, TAU / 3.0, 4),
	}
	var wheels: Array = []
	for w: Dictionary in g["wheels"]:
		wheels.append({"x": w["x"], "y": w["y"], "r": w["r"]})
	var rollers: Array = []
	for r2: Dictionary in g["rollers"]:
		rollers.append({"c": _v(r2["c"]), "r": r2["r"]})
	kit["gear"] = {
		"T": g["T"], "up": g["up"], "droop": g["droop"], "skirt_y": g["skirt_y"], "pitch": Gear.LINK_PITCH,
		"idler": {"c": _v(idl["c"]), "r": idl["r"]}, "sprocket": {"c": _v(sp["c"]), "r": sp["r"]},
		"rollers": rollers, "wheels": wheels, "sheets": sheets,
		"underside": {"rect": [44, 176, 368, 28], "split_y": 198, "top": "#0a0705", "bottom": "#070504"},
		"skirt_shade": {"x0": 20, "x1": 445, "y0": 180, "y1": 200, "from": 0.3},
	}


## One shoe of the track as draw_track() paints it (pitch exactly LINK_PITCH), sampled at 4 sub-px
## along and 2 across: rows 0..17 the top run (lit), 18..35 the rest.
func _track(kit: Dictionary) -> void:
	var pitch: float = Gear.LINK_PITCH
	var thick := float(L["gear"]["T"])
	var sub_u := 4
	var rows := int((thick + 4.0) * 2.0)
	var img := Px.blank(int(pitch) * sub_u, rows * 2)
	var c1 := Color("#0d0a08")
	var c2 := Color("#15110d")
	var c3 := Color("#1e1913")
	var c4 := Color("#3a3024")
	var horn0 := pitch * 0.4
	var horn1 := pitch * 0.4 + 2.0
	var gr0 := pitch * 0.3
	var gr1 := pitch * 0.3 + 2.6
	for lit_i in 2:
		var lit := lit_i == 0
		for iv in rows:
			var dd := -2.0 + (iv + 0.5) * 0.5
			for iu in img.get_width():
				var u := (iu + 0.5) / sub_u
				var horn := u >= horn0 and u < horn1
				var grouser := u >= gr0 and u < gr1
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
					col = c4 if u < 1.3 else (c2 if u > 1.8 else Gear.TRK0)
				elif dd < thick - 1.0:
					col = Gear.TRK0 if u < 0.8 else (c2 if lit else c1)
					if dd < 2.0 and u >= 0.8 and u < 1.8:
						col = c3
				elif dd < thick:
					col = Gear.TRK0 if u < 0.8 else (c3 if lit else c2)
				elif dd < thick + 1.0:
					if grouser:
						col = c4 if lit else c3
					else:
						outl = true
				else:
					outl = grouser
				if col.a == 0.0 and outl:
					col = Gear.OUT
				img.set_pixel(iu, lit_i * rows + iv, col)
	save(img, "track.png")
	kit["track"] = {"file": "track.png", "sub_u": sub_u, "rows": rows, "dd0": -2.0, "row_px": 0.5, "lit_ny": -0.35}


# --- guns ------------------------------------------------------------------------------------------------


func _guns(kit: Dictionary) -> void:
	var g: Dictionary = L["gun"]
	var ln := float(g["len"])
	var c: Array = Tank6.BARREL
	var lit := Color("#8a7458")
	var o := Vector2(0.0, 7.0)
	var img := Px.blank(int(ceil(ln)) + 3, 14)
	Px.profile(img, o, 0.0, [
		[9.0, 12.0, 4.6, 4.6, Color("#3a3026"), Color("#241c14"), Color("#100a06")],
		[12.0, 25.0, 3.4, 3.0, c[0], c[1], c[2]],
		[24.0, 26.0, 3.6, 3.6, lit, c[0], c[2]],
		[26.0, ln * 0.62, 2.3, 2.1, c[0], c[1], c[2]],
		[ln * 0.62, ln * 0.71, 3.0, 3.0, c[0], c[1], c[2]],
		[ln * 0.62, ln * 0.62 + 1.0, 3.0, 3.0, lit, c[0], c[2]],
		[ln * 0.71, ln - 7.0, 2.0, 1.9, c[0], c[1], c[2]],
		[ln - 7.0, ln, 3.2, 3.2, c[0], c[1], c[2]],
		[ln - 4.5, ln - 3.5, 3.2, 3.2, Tank6.OUT, Tank6.OUT, Tank6.OUT],
		[ln - 1.0, ln, 3.2, 3.2, lit, c[0], c[2]],
	])
	save(img, "barrel.png")
	var bows: Array = []
	var k := 0
	for b: Dictionary in L["bow"]:
		var bl := float(b["len"])
		var bo := Vector2(0.0, 4.0)
		var bi := Px.blank(int(ceil(bl)) + 2, 8)
		Px.profile(bi, bo, 0.0, [
			[2.0, 10.0, 1.6, 1.6, Color("#4a4238"), Color("#2c261e"), Color("#120e0a")],
			[10.0, bl, 0.9, 0.9, Color("#6a5c4a"), Color("#3a3228"), Color("#16110c")],
			[bl - 2.5, bl, 1.3, 1.3, Color("#2c261e"), Color("#2c261e"), Color("#120e0a")],
		])
		save(bi, "bow_%d.png" % k)
		bows.append({"file": "bow_%d.png" % k, "origin": [bo.x, bo.y], "pivot": _v(b["pivot"]), "len": bl})
		k += 1
	var ball := Px.blank(10, 10)
	var bc := Vector2(3.0, 5.0)
	Px.profile(ball, bc, 0.0, [[-1.0, 3.0, 3.2, 2.8, Color("#3a2c1e"), Color("#22180f"), Color("#100a06")]])
	save(ball, "bow_ball.png")
	kit["gun"] = {"trunnion": _v(g["trunnion"]), "len": ln, "file": "barrel.png", "origin": [o.x, o.y]}
	kit["bow"] = {"guns": bows, "ball": {"file": "bow_ball.png", "origin": [bc.x, bc.y]}}


# --- the main gun's blast --------------------------------------------------------------------------------


func _blast(kit: Dictionary) -> void:
	var air := _grid(AIR_BOX.size, AIR_FRAMES)
	var gnd := _grid(GROUND_BOX.size, GROUND_FRAMES)
	for k in AIR_FRAMES:
		var one := Px.blank(AIR_BOX.size.x, AIR_BOX.size.y)
		var m := Vector2(-AIR_BOX.position.x, -AIR_BOX.position.y) + Vector2(0.5, 0.5)
		blast_air(one, m, k / FPS)
		_put(air, one, k, AIR_BOX.size)
	for k in GROUND_FRAMES:
		var one2 := Px.blank(GROUND_BOX.size.x, GROUND_BOX.size.y)
		var mg := Vector2(-GROUND_BOX.position.x, -GROUND_BOX.position.y) + Vector2(0.5, 0.0)
		blast_ground(one2, mg, k / FPS)
		_put(gnd, one2, k, GROUND_BOX.size)
	save(air, "blast_air.png")
	save(gnd, "blast_ground.png")
	kit["blast"] = {
		"fps": FPS, "cols": SHEET_COLS,
		"air": {"file": "blast_air.png", "frames": AIR_FRAMES, "size": [AIR_BOX.size.x, AIR_BOX.size.y], "origin": [-AIR_BOX.position.x, -AIR_BOX.position.y]},
		"ground": {"file": "blast_ground.png", "frames": GROUND_FRAMES, "size": [GROUND_BOX.size.x, GROUND_BOX.size.y], "origin": [-GROUND_BOX.position.x, -GROUND_BOX.position.y]},
	}


func _grid(sz: Vector2i, n: int) -> Image:
	var rows := ceili(float(n) / SHEET_COLS)
	return Px.blank(sz.x * SHEET_COLS, sz.y * rows)


func _put(sheet: Image, one: Image, k: int, sz: Vector2i) -> void:
	sheet.blend_rect(one, Rect2i(Vector2i.ZERO, sz), Vector2i((k % SHEET_COLS) * sz.x, (k / SHEET_COLS) * sz.y))


## Tank6.blast() along the bore (angle 0) without the dust and the sparks: the smoke, the ring, the
## fire ball and its fragments, the star flash with the brake's jets.
func blast_air(img: Image, m: Vector2, ft: float) -> void:
	var d := Vector2.RIGHT
	var n := Vector2.DOWN
	var a := 0.0
	if ft > 0.08:
		var age := ft - 0.08
		for j in 16:
			var sp := 18.0 + 46.0 * Px.h2(j, 1, 41)
			var up := 10.0 + 26.0 * Px.h2(j, 2, 41)
			var slow := 1.0 / (1.0 + age * 1.2)
			var c := m + d * (6.0 + j * 4.5 + sp * age * slow) + n * ((Px.h2(j, 3, 41) - 0.5) * 26.0 * minf(age * 2.0, 1.0)) + Vector2(0, -up * age)
			var r := 4.0 + 13.0 * minf(age * 1.1, 1.0) + Px.h2(j, 4, 41) * 4.0
			Tank6.puff(img, c, r, Tank6.SMOKE, clampf((age - 0.9) / 1.0, 0.0, 1.0), j * 13)
		var rc := m + d * (8.0 + 60.0 * age / (1.0 + age))
		var rr := 5.0 + 16.0 * minf(age * 1.6, 1.0)
		var fade := clampf((age - 0.5) / 0.8, 0.0, 1.0)
		for k in 72:
			var t := TAU * k / 72.0
			for w in 2:
				var q := rc + d * cos(t) * (rr * 0.42 + w) + n * sin(t) * (rr + w)
				if Px.h2(k, 9 + w, 5) >= fade:
					Px.put(img, floori(q.x), floori(q.y), Tank6.SMOKE[2] if sin(t) < 0 else Tank6.SMOKE[1])
	if ft >= 0.05 and ft < 0.24:
		var u := ft - 0.05
		var fb := m + d * (12.0 + 90.0 * u)
		var fr := 19.0 - 30.0 * u
		Tank6.puff(img, fb, fr + 3.0, [Tank6.F_DRED, Tank6.F_RED, Tank6.F_ORA, Tank6.F_YEL], clampf((u - 0.12) / 0.07, 0.0, 1.0) * 0.6, 77)
		Tank6.puff(img, fb - d * 2.0 + n * 3.0, fr * 0.62, [Tank6.F_ORA, Tank6.F_YEL, Tank6.F_WHITE, Tank6.F_WHITE], 0.0, 78)
		Tank6.puff(img, fb + d * (fr * 0.7) - n * 5.0, fr * 0.45, [Tank6.F_RED, Tank6.F_ORA, Tank6.F_YEL, Tank6.F_YEL], 0.0, 79)
		for j in 7:
			var fa := a + (Px.h2(j, 11, 49) - 0.5) * 2.4
			var fp := m + Vector2(cos(fa), sin(fa)) * (20.0 + 160.0 * u) + Vector2(0, 50.0 * u * u)
			Tank6.puff(img, fp, 2.5 + 1.5 * Px.h2(j, 12, 49), [Tank6.F_DRED, Tank6.F_RED, Tank6.F_ORA, Tank6.F_YEL], 0.0, 80 + j)
	if ft < 0.075:
		var big := 1.0 if ft < 0.04 else 0.75
		var bk := m - d * 4.0
		for y in range(floori(m.y) - 34, ceili(m.y) + 35):
			for x in range(floori(m.x) - 16, ceili(m.x) + 58):
				var v := Vector2(x + 0.5, y + 0.5) - m
				var rho := v.length()
				var phi := atan2(v.dot(n), v.dot(d))
				var R := (8.0 + 40.0 * pow(maxf(cos(phi), 0.0), 7.0) + 20.0 * pow(maxf(cos(4.0 * phi), 0.0), 12.0) + 10.0 * pow(maxf(cos(8.0 * phi + 0.4), 0.0), 16.0)) * big
				var vb := Vector2(x + 0.5, y + 0.5) - bk
				var jet := absf(vb.dot(d)) < 2.5 - absf(vb.dot(n)) * 0.06 and absf(vb.dot(n)) < 24.0 * big
				if rho > R + 1.5 and not jet:
					continue
				var col := Tank6.F_ORA
				if jet:
					col = Tank6.F_YEL if absf(vb.dot(n)) < 14.0 * big else Tank6.F_ORA
				elif rho > R:
					col = Tank6.F_RED
				elif rho < R * 0.45:
					col = Tank6.F_WHITE
				elif rho < R * 0.72:
					col = Tank6.F_YEL
				Px.put(img, x, y, col)


## Tank6.blast()'s dust with the road at `m.y` (m.x under the muzzle).
func blast_ground(img: Image, m: Vector2, ft: float) -> void:
	var gy := m.y
	if ft <= 0.02 or ft >= 1.6:
		return
	var dust := [Tank6.DUST[0], Tank6.DUST[0], Tank6.DUST[1], Tank6.DUST[2]]
	var age2 := ft - 0.02
	for j in 9:
		var c2 := Vector2(m.x - 30.0 + j * 9.0 + 14.0 * age2, gy - 3.0 - 22.0 * age2 * (0.4 + Px.h2(j, 5, 43)))
		Tank6.puff(img, c2, 3.0 + 7.0 * minf(age2 * 1.8, 1.0), dust, clampf((age2 - 0.6) / 0.8, 0.0, 1.0), j * 7 + 100)
	if age2 < 0.9:
		for side in [-1.0, 1.0]:
			for j in 4:
				var xr: float = m.x + side * (14.0 + 150.0 * age2 - j * 7.0)
				Tank6.puff(img, Vector2(xr, gy - 2.0), 2.0 + 1.5 * Px.h2(j, 6, 44), dust, clampf(age2 / 0.9, 0.0, 1.0), j * 5 + 200 + int(side))
	if age2 < 0.8:
		for j in 12:
			var vx := (Px.h2(j, 7, 45) - 0.3) * 120.0
			var vy := -70.0 - 80.0 * Px.h2(j, 8, 45)
			var pp := Vector2(m.x - 10.0 + j * 3.0, gy - 1.0) + Vector2(vx, vy) * age2 + Vector2(0, 260.0 * age2 * age2)
			if pp.y <= gy:
				Px.put(img, floori(pp.x), floori(pp.y), Tank6.DUST[0] if j % 2 else Color("#1a140e"))
				Px.put(img, floori(pp.x) + 1, floori(pp.y), Tank6.DUST[1])


# --- planes -----------------------------------------------------------------------------------------------


func _planes(kit: Dictionary) -> void:
	var rows: Array = []
	for p: Dictionary in PLANES:
		var row := p.duplicate()
		row["file"] = "planes/%s.png" % p["name"]
		rows.append(row)
	kit["planes"] = rows


# --- layout -----------------------------------------------------------------------------------------------


func _layout(kit: Dictionary) -> void:
	var rooms := {}
	for k: String in L["rooms"]:
		rooms[k] = _r(L["rooms"][k])
	kit["rooms"] = rooms
	kit["seats"] = [
		{"id": "drive", "room": "drive", "engine": "diesel"},
		{"id": "gun", "room": "gun", "engine": "dynamo"},
		{"id": "loader", "room": "loader", "engine": "steam"},
		{"id": "lights", "room": "lights", "engine": "arc"},
		{"id": "sec", "room": "sec", "engine": "feed"},
	]
	var windows := {}
	for k2: String in ["shaft", "rackwin", "breechwin", "boxwin", "boxwin2"]:
		windows[k2] = _r(L[k2])
	kit["windows"] = windows
	var lamps: Array = []
	for c: Dictionary in L["cuts"]:
		if c.has("lamp"):
			lamps.append(_v(c["lamp"]))
	kit["window_lamps"] = lamps
	var rk: Dictionary = L["rack"]
	kit["rack"] = {"pivot": _v(rk["pivot"]), "slots_x": rk["slots_x"], "slots_y": rk["slots_y"], "head": _v(rk["head"])}
	var details: Array = []
	for d: Dictionary in L["details"]:
		var row := {}
		for key: String in d:
			var val: Variant = d[key]
			if val is Vector2 or val is Vector2i:
				row[key] = _v(val)
			else:
				row[key] = val
		details.append(row)
	kit["details"] = details
	kit["exhaust"] = [40.0, 112.0]
	kit["room_groups"] = {"drive": 1, "lights": 2, "gun": 3, "loader": 4, "sec": 5, "quarters": 6, "turret_drive": 6, "upper_front": 6}
	kit["hitbox"] = "r6_hitbox.json"


func _v(p: Variant) -> Array:
	var q: Vector2 = Vector2(p)
	return [q.x, q.y]


func _r(r: Rect2i) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]

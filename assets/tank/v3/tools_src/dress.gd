extends RefCounted
## Cutaway interiors of the v3 tank mock: the lamp-lit wall (riveted panels, ribs, a darker lower
## band, a warm pool under a hanging lamp, a grating floor) and the bay dressing (ceiling pipes with
## flanges and hangers, a cable run down one wall, a bulkhead door with its handwheel, a shelf with
## cans, boxes and tools, gauges, a valve on a pipe drop). Static: drawn once per layout, under the
## machines.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")

const OUT := Color("#0b0806")
const WALL: Array = [
	Color("#0d0805"), Color("#1a1009"), Color("#2c1c0e"), Color("#462c14"), Color("#6a4420"), Color("#9a6a30"),
	Color("#d09a4c")
]
const WALL_COLD: Array = [
	Color("#06090c"), Color("#0e161c"), Color("#18263a"), Color("#284058"), Color("#406686"), Color("#6c98b8"),
	Color("#b8daf0")
]
const WALL_STEAM: Array = [
	Color("#0c0805"), Color("#1a110a"), Color("#2e1d10"), Color("#4c3018"), Color("#764a22"), Color("#a8702e"),
	Color("#e0a050")
]
const BEAM := Color("#100a06")
const LAMP := Color("#ffd98a")
const LAMP_CORE := Color("#fff6d8")
const CU0 := Color("#5e3018")
const CU1 := Color("#9a5832")
const CU2 := Color("#d08a58")
const ST0 := Color("#1f1e1c")
const ST1 := Color("#3a3834")
const ST2 := Color("#5f5c55")
const ST3 := Color("#8e8a7e")
const BR0 := Color("#5e4220")
const BR1 := Color("#a07c40")
const BR2 := Color("#e0bd74")

static var _open: PackedByteArray
static var _w := 0
static var _h := 0
static var _g := 0


static func _p(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= _w or y >= _h or _open[y * _w + x] != _g:
		return
	img.set_pixel(x, y, c)


static func _r(img: Image, r: Rect2i, c: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_p(img, x, y, c)


## The lamp of opening `o`: its own `lamp`, else a hanging lamp 9 px under the ceiling, centred.
static func lamp_at(o: Dictionary) -> Vector2:
	var r: Rect2i = o["rect"]
	return o.get("lamp", Vector2(r.position.x + r.size.x * 0.5, r.position.y + 9))


## Lights the opening's wall and floor from its lamp, and draws the cut's own shadows.
static func light(img: Image, open: PackedByteArray, w: int, h: int, o: Dictionary, g: int) -> void:
	_open = open
	_w = w
	_h = h
	_g = g
	var r: Rect2i = o["rect"]
	var lamp := lamp_at(o)
	var lamps: Array = o.get("lamps", [lamp])
	var ramp: Array = WALL
	match str(o.get("tint", "warm")):
		"cold":
			ramp = WALL_COLD
		"steam":
			ramp = WALL_STEAM
	var has_lamp := bool(o.get("has_lamp", true))
	var reach := float(o.get("reach", maxf(r.size.x * 0.7, r.size.y * 1.1)))
	var dim := float(o.get("dim", 0.0))
	var floor_on := bool(o.get("floor", true))
	var beam := bool(o.get("beam", true))
	var fy := r.end.y - 3
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= w or y >= h or open[y * w + x] != g:
				continue
			var v := 0.0
			for lp: Vector2 in lamps:
				var d := Vector2(x + 0.5 - lp.x, (y + 0.5 - lp.y) * (0.8 if y > lp.y else 1.6))
				v = maxf(v, clampf(1.0 - d.length() / reach, 0.0, 1.0))
			v = v * v * 0.95 + 0.06 - dim
			if not has_lamp:
				v = 0.12 - dim
			var rx := (x - r.position.x) % 12
			if rx == 0:
				v -= 0.16
			elif rx == 1:
				v += 0.05
			elif rx == 2 and (y - r.position.y) % 6 == 3:
				v += 0.25
			if floor_on and y > fy - 9 and y < fy:
				v -= 0.08
				if y == fy - 9:
					v += 0.12
			elif (y - r.position.y) % 9 == 8:
				v -= 0.06
			var col := Px.dither(ramp, v, x, y)
			if beam and y < r.position.y + 2:
				col = BEAM
			if floor_on and y >= fy:
				var fl := clampf(1.0 - absf(x + 0.5 - lamp.x) / (reach * 0.8), 0.0, 1.0)
				if y == fy:
					col = Px.dither([Color("#4a3418"), BR0, BR1, BR2], 0.25 + fl * 0.75, x, y)
				elif y == fy + 1:
					col = ST2 if (x % 2 == 0 and fl > 0.3) else (ST1 if x % 2 == 0 else ST0)
				else:
					col = ST0 if x % 3 else ST1
			img.set_pixel(x, y, col)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= w or y >= h or open[y * w + x] != g:
				continue
			var up1 := y - 1 >= 0 and open[(y - 1) * w + x] != g
			var up2 := y - 2 >= 0 and open[(y - 2) * w + x] != g
			var lw := x - 1 >= 0 and open[y * w + x - 1] != g
			var lw2 := x - 2 >= 0 and open[y * w + x - 2] != g
			if up1 or lw:
				img.set_pixel(x, y, BEAM)
			elif up2 or lw2:
				Px.mix(img, x, y, BEAM, 0.5)


## Furnishes a bay: o.dress = {door: "L"/"R"/"", shelf: [x0, x1] (opening px) or [], gauges: x
## or -1, valve: x or -1, seed}.
static func bay(img: Image, open: PackedByteArray, w: int, h: int, o: Dictionary) -> void:
	var ds: Dictionary = o["dress"]
	var r: Rect2i = o["rect"]
	_open = open
	_w = w
	_h = h
	_g = int(o.get("group", 0))
	var seed := int(ds.get("seed", 1))
	var fy := r.end.y - 3
	var lamp := lamp_at(o)
	# ceiling pipes
	var py := r.position.y + 3
	var pipes := bool(ds.get("pipes", true))
	for x in range(r.position.x, r.end.x if pipes else r.position.x):
		_p(img, x, py, CU2)
		_p(img, x, py + 1, CU0)
		_p(img, x, py + 3, ST3)
		_p(img, x, py + 4, ST1)
		var k := (x - r.position.x) % 12
		if k == 5:
			_p(img, x, py - 1, BR1)
			_p(img, x, py + 2, BR0)
		elif k == 11:
			_p(img, x, py, OUT)
			_p(img, x, py + 2, OUT)
			_p(img, x, py + 3, ST2)
	# cable run down the left wall, clamped
	var cx := r.position.x + 2
	for y in range(py + 5, fy if pipes else py + 5):
		_p(img, cx, y, Color("#1a1612"))
		_p(img, cx + 1, y, Color("#3a2a1c"))
		if (y - py) % 7 == 0:
			_p(img, cx, y, BR1)
			_p(img, cx + 1, y, BR1)
			_p(img, cx + 2, y, OUT)
	# bulkhead door with its handwheel
	var door := str(ds.get("door", ""))
	if door != "":
		var dx := r.position.x + 5 if door == "L" else r.end.x - 13
		var dr := Rect2i(dx, fy - 23, 9, 23)
		for y in range(dr.position.y, dr.end.y):
			for x in range(dr.position.x, dr.end.x):
				var top := y - dr.position.y
				var corner := top < 2 and (x == dr.position.x or x == dr.end.x - 1)
				if corner:
					continue
				var edge := x == dr.position.x or x == dr.end.x - 1 or y == dr.position.y
				var col := OUT if edge else (ST1 if x > dr.position.x + 1 else ST2)
				if not edge and top == 1:
					col = ST3
				_p(img, x, y, col)
		var hc := Vector2(dr.position.x + 4.5, dr.position.y + 10.5)
		for k in 16:
			var a := TAU * k / 16.0
			_p(img, floori(hc.x + cos(a) * 2.6), floori(hc.y + sin(a) * 2.6), BR2 if k < 8 else BR1)
		_p(img, floori(hc.x), floori(hc.y), BR1)
		_p(img, floori(hc.x) - 1, floori(hc.y), BR0)
		_p(img, floori(hc.x) + 1, floori(hc.y), BR0)
		for hy in [dr.position.y + 4, dr.end.y - 6]:
			_p(img, dr.position.x - 1 if door == "L" else dr.end.x, hy, ST3)
			_p(img, dr.position.x - 1 if door == "L" else dr.end.x, hy + 1, OUT)
	# shelf with cans, boxes and tools
	var sh: Array = ds.get("shelf", [])
	if sh.size() == 2:
		var sy := r.position.y + 13
		var sx0 := int(sh[0])
		var sx1 := int(sh[1])
		_r(img, Rect2i(sx0, sy, sx1 - sx0, 1), BR1)
		_r(img, Rect2i(sx0, sy + 1, sx1 - sx0, 1), OUT)
		for bx in [sx0 + 1, sx1 - 2]:
			_p(img, bx, sy + 2, ST2)
			_p(img, bx, sy + 3, ST2)
		var x := sx0 + 1
		var n := 0
		while x < sx1 - 2:
			var kind := floori(Px.h2(x, n, seed) * 5.0)
			match kind:
				0:
					_r(img, Rect2i(x, sy - 4, 3, 4), Color("#8a2a1c"))
					_r(img, Rect2i(x, sy - 4, 3, 1), Color("#c8583c"))
					x += 4
				1:
					_r(img, Rect2i(x, sy - 3, 2, 3), Color("#3e4528"))
					_p(img, x + 2, sy - 3, ST3)
					x += 4
				2:
					_r(img, Rect2i(x, sy - 3, 5, 3), Color("#6a4a22"))
					_r(img, Rect2i(x, sy - 3, 5, 1), Color("#9a7038"))
					_p(img, x + 2, sy - 2, OUT)
					x += 6
				3:
					_r(img, Rect2i(x, sy - 5, 1, 5), Color("#3a5a4a"))
					_p(img, x, sy - 6, ST3)
					x += 3
				_:
					# a wrench hung under the shelf
					_p(img, x, sy + 2, ST3)
					_p(img, x + 1, sy + 3, ST3)
					_p(img, x + 2, sy + 4, ST3)
					_p(img, x + 3, sy + 5, ST2)
					_p(img, x + 2, sy + 2, ST2)
					x += 5
			n += 1
	# gauges on a pipe drop from the steel pipe
	var gx := int(ds.get("gauges", -1))
	if gx >= 0:
		var gy := r.position.y + 16
		_r(img, Rect2i(gx + 3, py + 5, 1, gy - py - 7), ST2)
		for k in 2:
			var gc := Vector2(gx + 0.5 + k * 6, gy + 0.5)
			for y in range(gy - 3, gy + 4):
				for xx in range(gx - 3 + k * 6, gx + 4 + k * 6):
					var dd := Vector2(xx + 0.5, y + 0.5).distance_to(gc)
					if dd < 1.8:
						_p(img, xx, y, Color("#e8dcc0"))
					elif dd < 2.8:
						_p(img, xx, y, BR1 if y < gy else BR0)
			var na := PI * (1.15 + 0.5 * Px.h2(gx, k, seed))
			_p(img, floori(gc.x + cos(na) * 1.2), floori(gc.y + sin(na) * 1.2), OUT)
	# a valve wheel on a copper drop
	var vx := int(ds.get("valve", -1))
	if vx >= 0:
		var vy := r.position.y + 13
		_r(img, Rect2i(vx, py + 2, 2, vy - py - 2), CU1)
		_r(img, Rect2i(vx + 1, py + 2, 1, vy - py - 2), CU0)
		var vc := Vector2(vx + 1.0, vy + 1.0)
		for k in 14:
			var a := TAU * k / 14.0
			_p(img, floori(vc.x + cos(a) * 2.7), floori(vc.y + sin(a) * 2.7), Color("#b0402a") if k < 7 else Color("#7a2a1c"))
		_p(img, floori(vc.x), floori(vc.y), BR2)
	# the hanging lamp: cord, shade, bulb
	if bool(o.get("has_lamp", true)):
		var lx := floori(lamp.x)
		var ly := floori(lamp.y)
		for y in range(r.position.y + 2, ly - 1):
			_p(img, lx, y, OUT)
		_r(img, Rect2i(lx - 2, ly - 2, 5, 1), OUT)
		_r(img, Rect2i(lx - 1, ly - 2, 3, 1), BR1)
		_p(img, lx - 3, ly - 1, OUT)
		_p(img, lx + 3, ly - 1, OUT)
		_r(img, Rect2i(lx - 2, ly - 1, 5, 1), BR0)
		_p(img, lx - 1, ly, LAMP)
		_p(img, lx, ly, LAMP_CORE)
		_p(img, lx + 1, ly, LAMP)
		_p(img, lx, ly + 1, LAMP)


# --- r3: the crew quarters (the upper deck, v2's look) ---------------------------------------------------


## A seated crewman facing `dir` (1 right, -1 left) at a table, feet on floor row `fy` (non-rider).
static func sitter(img: Image, x: int, fy: int, dir: int, seed: int) -> void:
	var uni := Color("#5a4c32")
	var uni_l := Color("#7a6844")
	var skin := Color("#b88a62")
	var hx := x - dir * 3 - (0 if dir > 0 else 1)
	_p(img, x, fy - 1, Color("#100a06"))
	_p(img, x + dir, fy - 1, Color("#100a06"))
	_p(img, x, fy - 2, Color("#2a2a30"))
	_p(img, x, fy - 3, Color("#2a2a30"))
	_r(img, Rect2i(mini(x, x - dir * 3), fy - 4, 4, 1), Color("#2a2a30"))
	_r(img, Rect2i(x - dir * 3 - (0 if dir > 0 else 1), fy - 10, 2, 6), uni)
	_r(img, Rect2i(mini(x - dir * 2, x), fy - 7, 3, 1), uni_l)
	_r(img, Rect2i(hx, fy - 13, 3, 3), skin)
	_r(img, Rect2i(hx, fy - 14, 3, 1), Color("#3a3428") if seed % 2 else Color("#2a2620"))
	_r(img, Rect2i(x - dir * 4 - 1, fy - 4, 3, 1), Color("#5e4220"))
	_p(img, x - dir * 4, fy - 3, Color("#3a2814"))
	_p(img, x - dir * 4, fy - 2, Color("#3a2814"))


static func quarters(img: Image, open: PackedByteArray, w: int, h: int, o: Dictionary) -> void:
	var r: Rect2i = o["rect"]
	_open = open
	_w = w
	_h = h
	_g = int(o.get("group", 0))
	var fy := r.end.y - 3
	var q: Dictionary = o["quarters"]
	for bx in q.get("walls", []):
		var x := int(bx)
		_r(img, Rect2i(x, r.position.y, 2, fy - r.position.y - 14), Color("#140c07"))
		_r(img, Rect2i(x, r.position.y, 1, fy - r.position.y - 14), Color("#3a2818"))
		_r(img, Rect2i(x - 1, fy - 15, 4, 1), Color("#5e4220"))
	for bx in q.get("bunks", []):
		var x := int(bx)
		for tier in 2:
			var y := fy - 3 - tier * 9
			_r(img, Rect2i(x, y - 2, 18, 2), Color("#5a4a38") if tier == 0 else Color("#6a5842"))
			_r(img, Rect2i(x, y - 2, 18, 1), Color("#8a7458"))
			_r(img, Rect2i(x, y, 18, 1), Color("#140c07"))
			_r(img, Rect2i(x + 1, y - 3, 4, 1), Color("#a89070"))
		_r(img, Rect2i(x, fy - 21, 1, 21), Color("#3a2814"))
		_r(img, Rect2i(x + 17, fy - 21, 1, 21), Color("#3a2814"))
	var n := 0
	for tx in q.get("tables", []):
		var x := int(tx)
		_r(img, Rect2i(x - 4, fy - 7, 9, 1), Color("#9a7040"))
		_r(img, Rect2i(x - 4, fy - 6, 9, 1), Color("#3a2814"))
		_r(img, Rect2i(x - 3, fy - 5, 1, 5), Color("#3a2814"))
		_r(img, Rect2i(x + 3, fy - 5, 1, 5), Color("#3a2814"))
		_p(img, x - 1, fy - 8, Color("#c8c0b0"))
		_p(img, x + 1, fy - 9, Color("#e8d8a0"))
		sitter(img, x - 7, fy, 1, n)
		if n % 2 == 0:
			sitter(img, x + 7, fy, -1, n + 1)
		n += 1
	for lx in q.get("lockers", []):
		var x := int(lx)
		for k in 2:
			var lr := Rect2i(x + k * 5, fy - 18, 5, 18)
			_r(img, lr, Color("#2c2a24"))
			_r(img, Rect2i(lr.position.x, lr.position.y, 5, 1), Color("#5a564a"))
			_r(img, Rect2i(lr.position.x + 4, lr.position.y, 1, 18), Color("#141210"))
			_p(img, lr.position.x + 3, lr.position.y + 8, Color("#a08a5a"))
			_r(img, Rect2i(lr.position.x + 1, lr.position.y + 3, 2, 1), Color("#141210"))
	for lx in q.get("ladders", []):
		var x := int(lx)
		_r(img, Rect2i(x, r.position.y + 2, 1, fy - r.position.y + 3), Color("#7a5a34"))
		_r(img, Rect2i(x + 5, r.position.y + 2, 1, fy - r.position.y + 3), Color("#7a5a34"))
		for y in range(r.position.y + 4, fy + 4, 4):
			_r(img, Rect2i(x + 1, y, 4, 1), Color("#9a7444"))
	if q.has("ring"):
		var rc: Vector2 = q["ring"]
		var rr := float(q.get("ring_r", 40.0))
		for y in range(r.position.y, fy):
			for x in range(r.position.x, r.end.x):
				var d := Vector2(x + 0.5, y + 0.5) - rc
				var rho := d.length()
				if d.y < 0.0 or rho < rr - 5.0 or rho > rr + 0.6:
					continue
				var phi := atan2(d.y, d.x)
				var c := Color("#2a221a")
				if rho > rr - 0.4:
					c = Color("#0a0806")
				elif rho > rr - 1.6:
					c = Color("#6a5236")
				elif rho < rr - 3.6:
					c = Color("#4a3a28") if fposmod(phi * 60.0 / TAU, 1.0) < 0.5 else Color("#0a0806")
				_p(img, x, y, c)
	for lp: Vector2 in o.get("lamps", []):
		var lx := floori(lp.x)
		var ly := floori(lp.y)
		_r(img, Rect2i(lx - 1, r.position.y + 2, 3, 1), Color("#3a2814"))
		_r(img, Rect2i(lx - 1, ly - 1, 3, 1), BR0)
		_p(img, lx - 1, ly, LAMP)
		_p(img, lx, ly, LAMP_CORE)
		_p(img, lx + 1, ly, LAMP)


## Dark rear machinery seen through a narrow cut: cabinets with dials, pipes, a fuel tank.
static func machinery(img: Image, open: PackedByteArray, w: int, h: int, o: Dictionary) -> void:
	var r: Rect2i = o["rect"]
	_open = open
	_w = w
	_h = h
	_g = int(o.get("group", 0))
	var fy := r.end.y - 3
	var x := r.position.x + 2
	var k := 0
	while x < r.end.x - 4:
		var bh := 10 + (k * 7) % 9
		var bw := 8 + (k * 3) % 5
		var b := Rect2i(x, fy - bh, bw, bh)
		_r(img, b, Color("#1e1c18"))
		_r(img, Rect2i(b.position.x, b.position.y, bw, 1), Color("#3e3a30"))
		_r(img, Rect2i(b.end.x - 1, b.position.y, 1, bh), Color("#0a0806"))
		_p(img, b.position.x + 2, b.position.y + 3, Color("#c89a50"))
		_p(img, b.position.x + 4, b.position.y + 3, Color("#7ab060") if k % 2 else Color("#c8503c"))
		x += bw + 1
		k += 1
	var tk := Rect2i(r.position.x + 3, r.position.y + 6, r.size.x - 8, 14)
	_r(img, tk, Color("#2a2418"))
	_r(img, Rect2i(tk.position.x, tk.position.y, tk.size.x, 1), Color("#4a4030"))
	_r(img, Rect2i(tk.position.x, tk.position.y + 5, tk.size.x, 1), Color("#5e4220"))
	for y in range(r.position.y + 2, fy):
		_p(img, r.end.x - 4, y, CU0)
		_p(img, r.end.x - 3, y, CU1 if y % 5 else BR1)

class_name FishingPlaceholderArt
extends RefCounted
## The view's last-resort sprites (FishingSprites uses them when neither a generated PNG nor the
## art builder's fallback script exists): simple palette shapes at each sprite's art.json size,
## with the navy outline and the boat's and angler's red PaletteSwap key ramp in the right places,
## so the layout, the recolouring and every animation can be judged before art lands.

const CLEAR := Color(0, 0, 0, 0)


static func image(id: String, size: Vector2i) -> Image:
	var w := maxi(size.x, 1)
	var h := maxi(size.y, 1)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	match id:
		"boat":
			_boat(img)
		"rig_bike":
			_bike(img)
		"rig_angler":
			_angler(img)
		"rig_crank":
			_disc(img, Vector2(w, h) * 0.5 - Vector2(0.5, 0.5), 2.5, FishingPalette.GREY_3)
			_line(img, Vector2(1, h / 2), Vector2(w - 2, h / 2), FishingPalette.GREY_4)
			_rect(img, Rect2i(0, h / 2 - 1, 2, 2), FishingPalette.NAVY)
			_rect(img, Rect2i(w - 2, h / 2 - 1, 2, 2), FishingPalette.NAVY)
		"rig_reel":
			_disc(
				img,
				Vector2(w, h) * 0.5 - Vector2(0.5, 0.5),
				float(mini(w, h)) * 0.5 - 0.5,
				FishingPalette.GOLD
			)
			_line(img, Vector2(w / 2, 1), Vector2(w / 2, h - 2), FishingPalette.NAVY)
			_line(img, Vector2(1, h / 2), Vector2(w - 2, h / 2), FishingPalette.NAVY)
			_rect(img, Rect2i(w / 2 - 1, h / 2 - 1, 2, 2), FishingPalette.GREY_1)
		"fish_mackerel":
			_fish(img, FishingPalette.TEAL, FishingPalette.GREY_1, FishingPalette.SEA_3, false)
		"fish_mahi":
			_fish(img, FishingPalette.LIME, FishingPalette.YELLOW, FishingPalette.SEA_2, false)
		"fish_tuna":
			_fish(img, FishingPalette.NAVY_2, FishingPalette.GREY_1, FishingPalette.YELLOW, false)
		"fish_marlin":
			_fish(img, FishingPalette.SEA_3, FishingPalette.GREY_1, FishingPalette.SEA_1, true)
		"gull_up":
			_gull(img, true)
		"gull_down":
			_gull(img, false)
		"bait_ball":
			for i in 14:
				var x := 3 + (i * 7) % (w - 6)
				var y := 2 + (i * 5) % (h - 4)
				_rect(
					img,
					Rect2i(x, y, 2, 1),
					FishingPalette.GREY_1 if i % 2 == 0 else FishingPalette.WHITE
				)
		"sonar_mark":
			for x in w:
				var y := roundi(absf(float(x) - float(w - 1) * 0.5) * 0.6)
				_px(img, x, clampi(y, 0, h - 1), FishingPalette.LIME)
		"current_seam":
			for x in w:
				if (x / 3) % 3 != 2:
					_px(img, x, 1 + (x / 5) % 2, FishingPalette.FOAM)
		"splash":
			_droplets(img, FishingPalette.WHITE, FishingPalette.SKY_0, 9)
		"spray":
			_droplets(img, FishingPalette.WHITE, FishingPalette.FOAM, 18)
		"catch_flash":
			_star(img, FishingPalette.GOLD, FishingPalette.YELLOW)
		"trophy_badge":
			_disc(
				img,
				Vector2(w, h) * 0.5 - Vector2(0.5, 0.5),
				float(w) * 0.5 - 0.5,
				FishingPalette.GOLD
			)
			_rect(img, Rect2i(4, h / 2 - 1, w - 8, 3), FishingPalette.YELLOW)
			_px(img, 4, h / 2, FishingPalette.NAVY)
		"clouds":
			for i in 5:
				var cx := 20.0 + float(i) * float(w) / 5.0
				_ellipse(
					img,
					Vector2(cx, h - 7),
					Vector2(16 + (i % 3) * 5, 6),
					FishingPalette.WHITE,
					FishingPalette.GREY_1
				)
		"islands_far":
			_humps(img, FishingPalette.GREY_2, 3)
		"island_palm":
			_ellipse(
				img,
				Vector2(w * 0.5, h - 1),
				Vector2(w * 0.35, 4),
				FishingPalette.SAND_1,
				FishingPalette.SAND_2
			)
			_line(img, Vector2(w * 0.45, h - 4), Vector2(w * 0.5, 6), FishingPalette.WOOD_1)
			_ellipse(
				img,
				Vector2(w * 0.5, 6),
				Vector2(8, 3),
				FishingPalette.GREEN,
				FishingPalette.GREEN_D
			)
		"sun":
			_disc(
				img,
				Vector2(w, h) * 0.5 - Vector2(0.5, 0.5),
				float(w) * 0.5 - 0.5,
				FishingPalette.YELLOW
			)
		"wake":
			for x in w:
				if x % 4 != 3:
					_px(img, x, 2 + (x / 6) % 2, FishingPalette.FOAM)
					_px(img, x, 4, FishingPalette.WHITE if x % 3 == 0 else CLEAR)
		"surface_strip":
			for x in w:
				var y := 1 + roundi(sin(float(x) / float(w) * TAU * 4.0))
				_px(img, x, y, FishingPalette.FOAM)
				for yy in range(y + 1, h):
					_px(img, x, yy, FishingPalette.SEA_1)
		"light_rays":
			var ray := Color(FishingPalette.SKY_0, 0.18)
			for y in h:
				for k in 4:
					var x0 := 10 + k * 30 + y / 3
					for x in range(x0, mini(x0 + 6, w)):
						if y < h - (k * 7) % 20:
							_px(img, x, y, ray)
		"reef_back":
			_humps(img, FishingPalette.GREEN_D, 7)
			_flat_end(img, 24)
		"reef_front":
			_reef_front(img)
			_flat_end(img, 24)
		"sand_strip":
			img.fill(FishingPalette.SAND_1)
			for x in range(0, w, 5):
				_px(img, x, (x / 5) % h, FishingPalette.SAND_2)
		_:
			img.fill(FishingPalette.GREY_2)
			_outline(img)
	return img


static func _boat(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var deck := h - 12
	for y in range(deck, h - 1):
		var inset := (y - deck) / 2
		for x in range(6 + inset, w - 2 - (y - deck)):
			_px(img, x, y, FishingPalette.WHITE if y < h - 4 else FishingPalette.GREY_1)
	_line(img, Vector2(6, deck), Vector2(w - 3, deck), FishingPalette.KEY_LIGHT)
	_line(img, Vector2(7, deck + 1), Vector2(w - 4, deck + 1), FishingPalette.KEY_DARK)
	_rect(img, Rect2i(1, deck - 2, 6, 10), FishingPalette.GREY_3)
	_rect(img, Rect2i(2, deck + 8, 3, 3), FishingPalette.GREY_4)
	_line(img, Vector2(34, 6), Vector2(34, deck - 1), FishingPalette.GREY_3)
	_line(img, Vector2(56, 6), Vector2(56, deck - 1), FishingPalette.GREY_3)
	_rect(img, Rect2i(30, 3, 30, 2), FishingPalette.KEY_LIGHT)
	_rect(img, Rect2i(30, 5, 30, 1), FishingPalette.KEY_DARK)
	_outline(img)


static func _bike(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	_rect(img, Rect2i(1, h - 2, w - 2, 2), FishingPalette.GREY_4)
	_line(img, Vector2(7, h - 3), Vector2(9, 4), FishingPalette.GREY_3)
	_rect(img, Rect2i(5, 3, 6, 2), FishingPalette.NAVY)
	_line(img, Vector2(10, 8), Vector2(w - 6, 8), FishingPalette.GREY_3)
	_line(img, Vector2(w - 6, 8), Vector2(w - 4, 2), FishingPalette.GREY_3)
	_rect(img, Rect2i(w - 6, 1, 4, 2), FishingPalette.GREY_4)
	_disc(img, Vector2(w - 6, h - 6), 3.0, FishingPalette.GREY_2)
	_outline(img)


static func _angler(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	_rect(img, Rect2i(3, 5, 6, h - 5), FishingPalette.KEY_LIGHT)
	_rect(img, Rect2i(3, h - 2, 6, 2), FishingPalette.KEY_DARK)
	_rect(img, Rect2i(4, 1, 5, 4), FishingPalette.SKIN_1)
	_rect(img, Rect2i(3, 0, 6, 2), FishingPalette.KEY_LIGHT)
	_rect(img, Rect2i(8, 1, 3, 1), FishingPalette.KEY_DARK)
	_line(img, Vector2(8, 7), Vector2(w - 1, 8), FishingPalette.SKIN_2)
	_outline(img)


static func _fish(img: Image, back: Color, belly: Color, fin: Color, bill: bool) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var body_w := roundi(float(w) * 0.75)
	var x0 := 4 if bill else 0
	var c := Vector2((x0 + body_w) * 0.5, (h - 1) * 0.5)
	_ellipse(img, c, Vector2((body_w - x0) * 0.5, h * 0.36), back, belly)
	for y in h:
		var half := absf(float(y) - (h - 1) * 0.5)
		var reach := roundi(float(w - body_w) * (half / maxf(h * 0.5, 1.0)))
		for x in range(body_w - 1, body_w - 1 + maxi(reach, 1)):
			_px(img, mini(x, w - 1), y, fin)
	if bill:
		_line(img, Vector2(0, c.y), Vector2(x0 + 2, c.y), FishingPalette.GREY_4)
		_line(img, Vector2(c.x - 6, 1), Vector2(c.x + 6, c.y - 2), fin)
	_px(img, x0 + 3, roundi(c.y) - 1, FishingPalette.NAVY)
	_outline(img)


static func _gull(img: Image, up: bool) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var cy := h / 2
	for x in w:
		var dx := absi(x - w / 2)
		var y := cy - dx / 2 if up else cy + dx / 3
		_px(img, x, clampi(y, 0, h - 1), FishingPalette.WHITE)
		_px(
			img,
			x,
			clampi(y + 1, 0, h - 1),
			FishingPalette.GREY_1 if dx > 3 else FishingPalette.WHITE
		)
	_px(img, w / 2 + 1, cy, FishingPalette.YELLOW)
	_outline(img)


static func _droplets(img: Image, a: Color, b: Color, count: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for i in count:
		var x := (i * 7 + 3) % w
		var y := h - 1 - (i * 5) % h
		_rect(img, Rect2i(x, y, 2, 2), a if i % 2 == 0 else b)


static func _star(img: Image, a: Color, b: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	_line(img, Vector2(w / 2, 0), Vector2(w / 2, h - 1), a)
	_line(img, Vector2(0, h / 2), Vector2(w - 1, h / 2), a)
	_line(img, Vector2(w / 4, h / 4), Vector2(3 * w / 4, 3 * h / 4), b)
	_line(img, Vector2(3 * w / 4, h / 4), Vector2(w / 4, 3 * h / 4), b)


static func _humps(img: Image, fill: Color, count: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for x in w:
		var v := 0.5 + 0.3 * sin(float(x) / float(w) * TAU * float(count))
		v += 0.15 * sin(float(x) / float(w) * TAU * float(count * 3) + 1.0)
		var top := clampi(roundi(float(h) * (1.0 - v)), 0, h - 1)
		_px(img, x, top, FishingPalette.NAVY)
		for y in range(top + 1, h):
			_px(img, x, y, fill)


static func _reef_front(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var cols := [
		FishingPalette.PINK,
		FishingPalette.ORANGE,
		FishingPalette.GREEN,
		FishingPalette.GREY_3,
		FishingPalette.CORAL
	]
	for i in range(0, w, 9):
		var tall := 4 + (i * 13) % maxi(h - 4, 1)
		var col: Color = cols[(i / 9) % cols.size()]
		_rect(img, Rect2i(i, h - tall, 5, tall), col)
		_px(img, i + 2, h - tall - 1, FishingPalette.NAVY)


## Clears the last `px` columns' tops down to a flat rock line (the reefs end flat on the
## right, brief 3.3).
static func _flat_end(img: Image, px: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for x in range(maxi(w - px, 0), w):
		for y in h:
			_px(img, x, y, CLEAR if y < h - 3 else FishingPalette.GREY_3)


static func _ellipse(img: Image, c: Vector2, r: Vector2, fill: Color, low: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var dx := (float(x) - c.x) / maxf(r.x, 0.5)
			var dy := (float(y) - c.y) / maxf(r.y, 0.5)
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, low if float(y) > c.y + r.y * 0.3 else fill)


static func _disc(img: Image, c: Vector2, r: float, fill: Color) -> void:
	_ellipse(img, c, Vector2(r, r), fill, fill)


static func _rect(img: Image, r: Rect2i, col: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_px(img, x, y, col)


static func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var steps := maxi(roundi(maxf(absf(b.x - a.x), absf(b.y - a.y))), 1)
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		_px(img, roundi(p.x), roundi(p.y), col)


static func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)


## A 1 px navy outline round every opaque pixel (the art direction's dark navy outline).
static func _outline(img: Image) -> void:
	var src := img.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			if src.get_pixel(x, y).a > 0.5:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + d
				if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
					continue
				if src.get_pixel(q.x, q.y).a > 0.5:
					img.set_pixel(x, y, FishingPalette.NAVY)
					break

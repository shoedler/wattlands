class_name SiegeHudDraw
extends RefCounted
## The materials of Castellum Rotae's HUD (src/games/siege/art/hud_mock.mjs, the approved mock), in
## art px of the 960 x 540 base under the Control's scale: the plate (dark wax in a limestone frame
## with a brick course, the fort's wall in section), the tabula ansata plaque, the red chip that is
## the only alarm, flat bars, the baked icons and slot shapes. A plate's stone joints and wax specks
## are one small texture per size, so a redraw costs one rect.

const STONE_HI := Color("#eadcbe")
const STONE := Color("#d3c19c")
const STONE_LO := Color("#9c8a68")
const BRICK := Color("#9c4a30")
const INK := Color("#2b1e13")
const WAX := Color("#1d1611")
const WAX_LIFT := Color("#262019")
const WAX_LINE := Color("#3f3224")
const BRONZE_HI := Color("#e0b76c")
const BRONZE := Color("#a9783a")
const BRONZE_LO := Color("#5e3f1e")
const TEXT := Color("#f2e6cb")
const DIM := Color("#b3a283")
const TRACK := Color("#3b2f22")
const GOOD := Color("#7fc4a4")
const UNDER := Color("#8fb4cf")
const AMBER := Color("#e8b24a")
const GOLD := Color("#eabb52")
const ALARM := Color("#c8321f")
const OXBLOOD := Color("#5a140e")
const TERRA := Color("#b9583a")
const VERD := Color("#5fa596")
const HEART := Color("#c0877f")
const PITCH := Color("#a0663a")
const WARM := Color("#7d5f86")
const LIT := Color("#3a2412")
const PLATE_SHADOW := Color(0.0, 0.0, 0.0, 0.42)
## A generated face's strokes reach one row over its cap; a chip keeps 2 px clear beyond that.
const GLYPH_CHIP_PAD := 3
const FIXED_WHITE := Color.WHITE

static var _plates: Dictionary = {}


static func rect(c: CanvasItem, x: float, y: float, w: float, h: float, col: Color) -> void:
	c.draw_rect(Rect2(x, y, w, h), col)


## A plate at (x, y), its shadow 2 px down and right; `alarm` swaps the stone for the red frame,
## `fill` lights the wax.
static func plate(
	c: CanvasItem, x: int, y: int, w: int, h: int, alarm: bool = false, fill: Color = WAX
) -> void:
	c.draw_rect(Rect2(x + 2, y + h, w, 2), PLATE_SHADOW)
	c.draw_rect(Rect2(x + w, y + 2, 2, h), PLATE_SHADOW)
	var tex := plate_texture(w, h, alarm, fill)
	if tex != null:
		c.draw_texture(tex, Vector2(x, y))


## The plate's own texture, built once per look and size.
static func plate_texture(w: int, h: int, alarm: bool = false, fill: Color = WAX) -> Texture2D:
	var key := "%d/%d/%d/%s" % [w, h, int(alarm), fill.to_html()]
	var tex: Variant = _plates.get(key, null)
	if tex is Texture2D:
		return tex
	var img := Image.create_from_data(
		w, h, false, Image.FORMAT_RGB8, _plate_bytes(w, h, alarm, fill)
	)
	var made := ImageTexture.create_from_image(img)
	_plates[key] = made
	return made


static func _plate_bytes(w: int, h: int, alarm: bool, fill: Color) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h * 3)
	var frame := ALARM if alarm else STONE
	_fill(out, w, 0, 0, w, h, frame)
	_fill(out, w, 0, 0, w, 1, frame if alarm else STONE_HI)
	_fill(out, w, 0, h - 1, w, 1, STONE_LO)
	_fill(out, w, w - 1, 0, 1, h, STONE_LO)
	if not alarm:
		# coursing: a joint every few pixels along the stone
		var i := 5
		while i < w - 3:
			_fill(out, w, i, 1, 1, 1, STONE_LO)
			_fill(out, w, i + 4, h - 2, 1, 1, STONE_LO)
			i += 9
		var j := 5
		while j < h - 3:
			_fill(out, w, 1, j, 1, 1, STONE_LO)
			_fill(out, w, w - 2, j + 4, 1, 1, STONE_LO)
			j += 9
	_fill(out, w, 2, 2, w - 4, h - 4, OXBLOOD if alarm else BRICK)
	_fill(out, w, 3, 3, w - 6, h - 6, fill)
	# the wax's grain
	var noise := w * 31 + h * 17
	for py in range(3, h - 3):
		for px in range(3, w - 3):
			noise = (noise * 1103515245 + 12345) & 0x7fffffff
			if (noise >> 8) % 23 == 0:
				_fill(out, w, px, py, 1, 1, WAX_LIFT)
	return out


static func _fill(
	out: PackedByteArray, stride: int, x: int, y: int, w: int, h: int, col: Color
) -> void:
	var r := col.r8
	var g := col.g8
	var b := col.b8
	var rows := out.size() / 3 / stride
	for j in range(y, mini(y + h, rows)):
		var at := (j * stride + x) * 3
		for i in mini(w, stride - x):
			out[at] = r
			out[at + 1] = g
			out[at + 2] = b
			at += 3


## The tabula ansata: an inscription plaque with dovetail handles, a peg hole in each, an inset
## moulding. `lead` leaves room before the text (a slot shape). Returns the plaque's width.
static func ansata(
	c: CanvasItem, x: int, y: int, text: String, face: String = "LABEL", lead: int = 0
) -> int:
	var cap := int(SiegeHudType.face(face).get("cap", 9))
	var w := SiegeHudType.width(text, face) + lead + 10
	var h := cap + 8
	var mid := (h - 1) / 2.0
	for i in range(1, 6):
		var half := roundi(mid * (0.4 + 0.12 * i))
		var top := floori(mid - half)
		var run := ceili(mid + half) - top + 1
		var col := STONE_LO if i == 5 else STONE
		c.draw_rect(Rect2(x - i, y + top, 1, run), col)
		c.draw_rect(Rect2(x + w - 1 + i, y + top, 1, run), col)
	c.draw_rect(Rect2(x - 3, y + roundi(mid), 1, 1), INK)
	c.draw_rect(Rect2(x + w + 2, y + roundi(mid), 1, 1), INK)
	c.draw_rect(Rect2(x, y, w, h), STONE)
	c.draw_rect(Rect2(x, y, w, 1), STONE_HI)
	c.draw_rect(Rect2(x, y + h - 1, w, 1), STONE_LO)
	c.draw_rect(Rect2(x + 1, y + 1, w - 2, 1), STONE_LO)
	c.draw_rect(Rect2(x + 1, y + h - 2, w - 2, 1), STONE_HI)
	SiegeHudType.draw(c, text, x + 5 + lead, y + 4, face, INK, false)
	return w


## A flat bar, `frac` filled in `col`.
static func bar(
	c: CanvasItem,
	x: float,
	y: float,
	w: float,
	h: float,
	frac: float,
	col: Color,
	track: Color = TRACK
) -> void:
	c.draw_rect(Rect2(x, y, w, h), track)
	c.draw_rect(Rect2(x, y, roundf(w * clampf(frac, 0.0, 1.0)), h), col)


## A chip: light text on a filled block, the only alarm when red. `right` puts its right edge at x.
## Returns the far edge.
static func chip(
	c: CanvasItem,
	text: String,
	x: int,
	y: int,
	face: String = "LABEL",
	right: bool = false,
	bg: Color = ALARM,
	fg: Color = TEXT
) -> int:
	var w := SiegeHudType.width(text, face) + 6
	var cap := int(SiegeHudType.face(face).get("cap", 9))
	var lx := x - w if right else x
	var pad := GLYPH_CHIP_PAD if face != "LABEL" else 2
	c.draw_rect(Rect2(lx, y - pad, w, cap + pad * 2), bg)
	SiegeHudType.draw(c, text, lx + 3, y, face, fg, false)
	return lx + w


## A baked icon: '#' pixels in `tint`, the fixed-colour pixels as baked.
static func icon(c: CanvasItem, icon_name: String, x: float, y: float, tint: Color) -> void:
	var tex := SiegeHudType.atlas()
	var e: Dictionary = (SiegeHudType.manifest().get("icons", {}) as Dictionary).get(icon_name, {})
	if tex == null or e.is_empty():
		return
	_blit(c, tex, e["tint"], x, y, tint)
	if e.has("fixed"):
		_blit(c, tex, e["fixed"], x, y, FIXED_WHITE)


## A slot's shape (`shape` is Wl.SLOT_SHAPES' name) in the slot's colour.
static func shape(c: CanvasItem, shape_name: String, x: float, y: float, col: Color) -> void:
	var tex := SiegeHudType.atlas()
	var all: Array = SiegeHudType.manifest().get("shapes", [])
	var i := Wl.SLOT_SHAPES.find(shape_name)
	if tex == null or i < 0 or i >= all.size():
		return
	_blit(c, tex, all[i], x, y, col)


static func _blit(c: CanvasItem, tex: Texture2D, r: Array, x: float, y: float, col: Color) -> void:
	c.draw_texture_rect_region(tex, Rect2(x, y, r[2], r[3]), Rect2(r[0], r[1], r[2], r[3]), col)

class_name SiegeHudType
extends RefCounted
## The Castellum Rotae letter at runtime: the faces baked by src/games/siege/art/hud_bake.mjs from
## the mock's own code (assets/siege/hud/hud_atlas.png and .json). LABEL (cap 9), BODY (12), LINE
## (14), NUM (14), KEY (24), KEY28 and KEY36 (72 px at 1080p). Sizes are art px, drawn under the
## Control's scale with nearest filtering. Text is upper-cased at draw time; an accented letter
## folds to its base letter and any other character outside the atlas draws as FALLBACK, so a
## rider's name can never crash the HUD. Faces of cap 14 and up cast a 1 px shadow on the wax, as
## in the mock.

const ATLAS := "res://assets/siege/hud/hud_atlas.png"
const MANIFEST := "res://assets/siege/hud/hud_atlas.json"
const FALLBACK := "?"
const SHADOW := Color(0.043, 0.027, 0.02, 0.85)
## The face and the sizes the platform's toasts and help use (HudSpec.palette font): BODY on a
## 14 px font, twice that at 1080p.
const KIT_FACE := "BODY"
const KIT_FONT_PX := 14
const FOLD := {
	"À": "A",
	"Á": "A",
	"Â": "A",
	"Ã": "A",
	"Ä": "A",
	"Å": "A",
	"Æ": "A",
	"Ç": "C",
	"È": "E",
	"É": "E",
	"Ê": "E",
	"Ë": "E",
	"Ì": "I",
	"Í": "I",
	"Î": "I",
	"Ï": "I",
	"Ñ": "N",
	"Ò": "O",
	"Ó": "O",
	"Ô": "O",
	"Õ": "O",
	"Ö": "O",
	"Ø": "O",
	"Ù": "U",
	"Ú": "U",
	"Û": "U",
	"Ü": "U",
	"Ý": "Y",
	"Š": "S",
	"Ž": "Z",
	"…": ".",
	"’": "'",
	"–": "-",
	"—": "-",
	"×": "X",
}

static var _manifest: Dictionary = {}
static var _atlas: Texture2D = null
static var _font: Font = null


## The baked manifest ({} when the file is missing).
static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var f := FileAccess.open(MANIFEST, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_manifest = d
	return _manifest


static func atlas() -> Texture2D:
	if _atlas == null:
		_atlas = load(ATLAS) as Texture2D
	return _atlas


static func face(name: String) -> Dictionary:
	return (manifest().get("faces", {}) as Dictionary).get(name, {})


static func has_glyph(ch: String, face_name: String) -> bool:
	return (face(face_name).get("glyphs", {}) as Dictionary).has(ch)


## The glyph's atlas row [x, y, w, h, advance, pad] after folding; the fallback's outside the set.
static func _glyph(glyphs: Dictionary, ch: String) -> Array:
	var g: Variant = glyphs.get(ch, null)
	if g == null:
		g = glyphs.get(str(FOLD.get(ch, FALLBACK)), glyphs.get(FALLBACK, null))
	return g if g is Array else []


## The text's width in art px (upper-cased, like draw).
static func width(text: String, face_name: String) -> int:
	var f := face(face_name)
	if f.is_empty():
		return 0
	var glyphs: Dictionary = f["glyphs"]
	var space := int(f["space"])
	var w := 0
	var s := text.to_upper()
	for i in s.length():
		var ch := s[i]
		if ch == " ":
			w += space
			continue
		var g := _glyph(glyphs, ch)
		if not g.is_empty():
			w += int(g[4])
	return maxi(0, w - int(f["track"]))


## Draws `text` with its cap top at (x, y). Returns the x after it.
static func draw(
	c: CanvasItem, text: String, x: int, y: int, face_name: String, col: Color, shadow: bool = true
) -> int:
	var f := face(face_name)
	var tex := atlas()
	if f.is_empty() or tex == null:
		return x
	var s := text.to_upper()
	if shadow and bool(f["shadow"]):
		_run(c, tex, f, s, x + 1, y + 1, SHADOW)
	_run(c, tex, f, s, x, y, col)
	return x + width(s, face_name)


## Right-aligned at `right`. Returns the left edge.
static func draw_r(
	c: CanvasItem, text: String, right: int, y: int, face_name: String, col: Color
) -> int:
	var left := right - width(text, face_name)
	draw(c, text, left, y, face_name, col)
	return left


static func _run(
	c: CanvasItem, tex: Texture2D, f: Dictionary, s: String, x: int, y: int, col: Color
) -> void:
	var glyphs: Dictionary = f["glyphs"]
	var space := int(f["space"])
	var cx := x
	for i in s.length():
		var ch := s[i]
		if ch == " ":
			cx += space
			continue
		var g := _glyph(glyphs, ch)
		if g.is_empty():
			continue
		var pad := int(g[5])
		c.draw_texture_rect_region(
			tex, Rect2(cx - pad, y - pad, g[2], g[3]), Rect2(g[0], g[1], g[2], g[3]), col
		)
		cx += int(g[4])


## `text` cut to fit `max_w` art px (a full stop marks the cut).
static func fit(text: String, face_name: String, max_w: int) -> String:
	if width(text, face_name) <= max_w:
		return text
	var s := text
	while s.length() > 0 and width(s + ".", face_name) > max_w:
		s = s.substr(0, s.length() - 1)
	return s.strip_edges() + "." if s.length() > 0 else ""


## The BODY face as a Font for the platform's toasts, game banner and help (HudSpec.palette font):
## both cases draw the capitals. Null when the atlas's image can't be read (a headless renderer).
static func kit_font() -> Font:
	if _font != null:
		return _font
	var tex := atlas()
	var f := face(KIT_FACE)
	var img: Image = tex.get_image() if tex != null else null
	if img == null or f.is_empty():
		return null
	var ff := FontFile.new()
	var sz := Vector2i(KIT_FONT_PX, 0)
	var cap := int(f["cap"])
	ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	ff.generate_mipmaps = false
	ff.fixed_size = KIT_FONT_PX
	ff.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	ff.hinting = TextServer.HINTING_NONE
	ff.allow_system_fallback = false
	ff.set_texture_image(0, sz, 0, img)
	ff.set_cache_ascent(0, KIT_FONT_PX, cap)
	ff.set_cache_descent(0, KIT_FONT_PX, KIT_FONT_PX - cap)
	var glyphs: Dictionary = f["glyphs"]
	for ch: String in glyphs:
		_font_glyph(ff, sz, ch, glyphs[ch], cap)
		var lower := ch.to_lower()
		if lower != ch:
			_font_glyph(ff, sz, lower, glyphs[ch], cap)
	ff.set_glyph_advance(0, KIT_FONT_PX, 32, Vector2(int(f["space"]), 0))
	_font = ff
	return _font


static func _font_glyph(ff: FontFile, sz: Vector2i, ch: String, g: Array, cap: int) -> void:
	var idx := ch.unicode_at(0)
	var pad := int(g[5])
	ff.set_glyph_advance(0, sz.x, idx, Vector2(int(g[4]), 0))
	ff.set_glyph_offset(0, sz, idx, Vector2(-pad, -cap - pad))
	ff.set_glyph_size(0, sz, idx, Vector2(g[2], g[3]))
	ff.set_glyph_uv_rect(0, sz, idx, Rect2(g[0], g[1], g[2], g[3]))
	ff.set_glyph_texture_idx(0, sz, idx, 0)

class_name PixelFont
extends RefCounted
## A pixel font from the Image Font importer, made ready to set text on its art grid. The importer
## hangs a glyph by half its cell, which draws the caps under a Label's box and the descenders out
## of it; hang() hangs every glyph from the baseline by its cap height and narrows the space.

static var _hung: Dictionary = {}


## The font at `path` with every glyph `cap_rows` above the baseline and the space `space_advance`
## glyph px wide, done once per path (the resource is shared, so the first call's numbers stand). A
## Font that is not a FontFile comes back as loaded, unchanged; null when `path` holds no Font.
static func hang(path: String, cap_rows: int, space_advance: int) -> Font:
	if _hung.has(path):
		return _hung[path]
	var font := load(path) as Font
	if font == null:
		return null
	var ff := font as FontFile
	if ff != null:
		for i in ff.get_cache_count():
			for sz in ff.get_size_cache_list(i):
				for g in ff.get_glyph_list(i, sz):
					ff.set_glyph_offset(i, sz, g, Vector2(0, -cap_rows))
				ff.set_glyph_advance(i, sz.x, 32, Vector2(space_advance, 0))
	_hung[path] = font
	return font

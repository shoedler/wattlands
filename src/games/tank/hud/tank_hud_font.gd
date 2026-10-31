class_name TankHudFont
extends RefCounted
## Torque Company's own pixel type (brief 3.6), authored here as grids and written to the PNGs
## under assets/tank/hud/ by write() (the PNGs are committed; a test checks they still match):
##  - TEXT: a square, condensed, stencil-flavoured 5 x 7 face (capitals with stencil breaks in the
##    closed bowls of B D O P Q R, lower case with 2-row descenders, a slashed zero), one 5 x 9 grid
##    per character, laid out for Godot's Image Font importer (tank_stencil_5x7.png, COLUMNS x ROWS
##    cells of CELL, in character_ranges order; the .import next to it). Drawn at whole multiples
##    of CELL.y (9 px at 1x).
##  - TALL: the same glyphs stretched to a 9 px cap (tank_stencil_5x9.png): the rider-facing text.
##  - DIGITS: the key-number face, 7 x 12 grids with 2 px stems doubled to 14 x 24 art px
##    (tank_digits_14x24.png, one strip of DIGIT_CELL cells in DIGIT_CHARS order); TankHudDraw
##    blits it per glyph, so key numbers are 24 art px tall (48 px at 1080p).

const TEXT_PNG := "res://assets/tank/hud/tank_stencil_5x7.png"
const DIGITS_PNG := "res://assets/tank/hud/tank_digits_14x24.png"
const COLUMNS := 16
const ROWS := 7
const CELL := Vector2i(6, 9)
## The tall face: the same glyphs stretched to a 9 px cap (TALL_PNG, cell CELL_T, ascent 9,
## descent 2) by doubling two stem rows (capitals, digits, signs: rows 1 and 4; lower case: rows
## 3 and 5 of the x-height), so the stencil look stays and the advance stays 6 px. Every text a
## rider reads mid-effort uses it (8-9 art px cap, 18 px at 1080p).
const TALL_PNG := "res://assets/tank/hud/tank_stencil_5x9.png"
const CELL_T := Vector2i(6, 11)
const FIRST := 32
const LAST := 126
## en dash, middle dot, ellipsis, degree sign
const EXTRA: Array[int] = [0x2013, 0xB7, 0x2026, 0xB0]

## Glyphs by character: 7 cap rows (and 2 optional descender rows), "/" between rows.
const TEXT := {
	" ": ".....",
	"!": "..#../..#../..#../..#../..#../...../..#..",
	'"': ".#.#./.#.#.",
	"#": ".#.#./#####/.#.#./.#.#./.#.#./#####/.#.#.",
	"$": "..#../#####/#.#../#####/..#.#/#####/..#..",
	"%": "##..#/##.#./...#./..#../.#.../.#.##/#..##",
	"&": ".##../#..#./#.#../.#.../#.#.#/#..#./.##.#",
	"'": "..#../..#..",
	"(": "...#./..#../.#.../.#.../.#.../..#../...#.",
	")": ".#.../..#../...#./...#./...#./..#../.#...",
	"*": "...../..#../#.#.#/.###./#.#.#/..#..",
	"+": "...../..#../..#../#####/..#../..#..",
	",": "...../...../...../...../...../..#../..#../.#...",
	"-": "...../...../...../.###.",
	".": "...../...../...../...../...../...../..#..",
	"/": "....#/....#/...#./..#../.#.../#..../#....",
	"0": ".###./#...#/#..##/#.#.#/##..#/#...#/.###.",
	"1": "..#../.##../..#../..#../..#../..#../.###.",
	"2": "####./....#/....#/.###./#..../#..../#####",
	"3": "####./....#/....#/.###./....#/....#/####.",
	"4": "#...#/#...#/#...#/#####/....#/....#/....#",
	"5": "#####/#..../#..../####./....#/....#/####.",
	"6": ".###./#..../#..../####./#...#/#...#/.###.",
	"7": "#####/....#/...#./..#../..#../..#../..#..",
	"8": ".###./#...#/#...#/.###./#...#/#...#/.###.",
	"9": ".###./#...#/#...#/.####/....#/....#/.###.",
	":": "...../..#../...../...../...../..#..",
	";": "...../..#../...../...../...../..#../..#../.#...",
	"<": "...#./..#../.#.../#..../.#.../..#../...#.",
	"=": "...../...../#####/...../#####",
	">": ".#.../..#../...#./....#/...#./..#../.#...",
	"?": ".###./#...#/....#/...#./..#../...../..#..",
	"@": ".###./#...#/#.###/#.#.#/#.###/#..../.####",
	"A": ".###./#...#/#...#/#####/#...#/#...#/#...#",
	"B": "##.#./#...#/#...#/####./#...#/#...#/##.#.",
	"C": ".####/#..../#..../#..../#..../#..../.####",
	"D": "##.#./#...#/#...#/#...#/#...#/#...#/##.#.",
	"E": "#####/#..../#..../####./#..../#..../#####",
	"F": "#####/#..../#..../####./#..../#..../#....",
	"G": ".####/#..../#..../#.###/#...#/#...#/.####",
	"H": "#...#/#...#/#...#/#####/#...#/#...#/#...#",
	"I": ".###./..#../..#../..#../..#../..#../.###.",
	"J": "..###/...#./...#./...#./...#./#..#./.##..",
	"K": "#...#/#..#./#.#../##.../#.#../#..#./#...#",
	"L": "#..../#..../#..../#..../#..../#..../#####",
	"M": "#...#/##.##/#.#.#/#.#.#/#...#/#...#/#...#",
	"N": "#...#/##..#/##..#/#.#.#/#..##/#..##/#...#",
	"O": ".#.#./#...#/#...#/#...#/#...#/#...#/.#.#.",
	"P": "##.#./#...#/#...#/####./#..../#..../#....",
	"Q": ".#.#./#...#/#...#/#...#/#.#.#/#..#./.##.#",
	"R": "##.#./#...#/#...#/####./#.#../#..#./#...#",
	"S": ".####/#..../#..../.###./....#/....#/####.",
	"T": "#####/..#../..#../..#../..#../..#../..#..",
	"U": "#...#/#...#/#...#/#...#/#...#/#...#/.###.",
	"V": "#...#/#...#/#...#/#...#/#...#/.#.#./..#..",
	"W": "#...#/#...#/#...#/#.#.#/#.#.#/##.##/#...#",
	"X": "#...#/#...#/.#.#./..#../.#.#./#...#/#...#",
	"Y": "#...#/#...#/.#.#./..#../..#../..#../..#..",
	"Z": "#####/....#/...#./..#../.#.../#..../#####",
	"[": ".###./.#.../.#.../.#.../.#.../.#.../.###.",
	"\\": "#..../#..../.#.../..#../...#./....#/....#",
	"]": ".###./...#./...#./...#./...#./...#./.###.",
	"^": "..#../.#.#./#...#",
	"_": "...../...../...../...../...../...../#####",
	"`": ".#.../..#..",
	"a": "...../...../.###./....#/.####/#...#/.####",
	"b": "#..../#..../####./#...#/#...#/#...#/####.",
	"c": "...../...../.####/#..../#..../#..../.####",
	"d": "....#/....#/.####/#...#/#...#/#...#/.####",
	"e": "...../...../.###./#...#/#####/#..../.####",
	"f": "..##./.#.../.#.../####./.#.../.#.../.#...",
	"g": "...../...../.####/#...#/#...#/#...#/.####/....#/.###.",
	"h": "#..../#..../####./#...#/#...#/#...#/#...#",
	"i": "..#../...../.##../..#../..#../..#../.###.",
	"j": "...#./...../..##./...#./...#./...#./...#./#..#./.##..",
	"k": "#..../#..../#..#./#.#../##.../#.#../#..#.",
	"l": ".##../..#../..#../..#../..#../..#../.###.",
	"m": "...../...../##.#./#.#.#/#.#.#/#.#.#/#.#.#",
	"n": "...../...../####./#...#/#...#/#...#/#...#",
	"o": "...../...../.###./#...#/#...#/#...#/.###.",
	"p": "...../...../####./#...#/#...#/#...#/####./#..../#....",
	"q": "...../...../.####/#...#/#...#/#...#/.####/....#/....#",
	"r": "...../...../#.##./##..#/#..../#..../#....",
	"s": "...../...../.####/#..../.###./....#/####.",
	"t": ".#.../.#.../####./.#.../.#.../.#.../..##.",
	"u": "...../...../#...#/#...#/#...#/#...#/.####",
	"v": "...../...../#...#/#...#/#...#/.#.#./..#..",
	"w": "...../...../#...#/#...#/#.#.#/#.#.#/.#.#.",
	"x": "...../...../#...#/.#.#./..#../.#.#./#...#",
	"y": "...../...../#...#/#...#/#...#/#...#/.####/....#/.###.",
	"z": "...../...../#####/...#./..#../.#.../#####",
	"{": "...##/..#../..#../.#.../..#../..#../...##",
	"|": "..#../..#../..#../..#../..#../..#../..#..",
	"}": "##.../..#../..#../...#./..#../..#../##...",
	"~": "...../...../.#.../#.#.#/...#.",
	"–": "...../...../...../#####",
	"·": "...../...../...../..#..",
	"…": "...../...../...../...../...../...../#.#.#",
	"°": ".##../#..#./#..#./.##..",
}

## The key-number face: 7 x 12 grids (2 px stems, 1 px bars: thick verticals, thin
## horizontals, like stencilled hull numbers), doubled to DIGIT_CELL.
const DIGIT_CHARS := "0123456789:.-"
const DIGIT_CELL := Vector2i(14, 24)
## Advance of each digit glyph in art px (glyph width + 2 px gap); ':' '.' are narrow.
const DIGIT_ADVANCE := {":": 9, ".": 7}
const DIGIT_ADVANCE_DEFAULT := 16
const DIGITS := {
	"0":
	[
		".#####.",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		".#####."
	],
	"1":
	[
		"...##..",
		"..###..",
		".####..",
		"...##..",
		"...##..",
		"...##..",
		"...##..",
		"...##..",
		"...##..",
		"...##..",
		"...##..",
		".######"
	],
	"2":
	[
		".#####.",
		"##...##",
		".....##",
		".....##",
		".....##",
		"....##.",
		"...##..",
		"..##...",
		".##....",
		"##.....",
		"##.....",
		"#######"
	],
	"3":
	[
		".#####.",
		"##...##",
		".....##",
		".....##",
		".....##",
		"..####.",
		".....##",
		".....##",
		".....##",
		".....##",
		"##...##",
		".#####."
	],
	"4":
	[
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"#######",
		".....##",
		".....##",
		".....##",
		".....##",
		".....##"
	],
	"5":
	[
		"#######",
		"##.....",
		"##.....",
		"##.....",
		"######.",
		".....##",
		".....##",
		".....##",
		".....##",
		".....##",
		"##...##",
		".#####."
	],
	"6":
	[
		".#####.",
		"##...##",
		"##.....",
		"##.....",
		"######.",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		".#####."
	],
	"7":
	[
		"#######",
		".....##",
		".....##",
		".....##",
		"....##.",
		"....##.",
		"...##..",
		"...##..",
		"..##...",
		"..##...",
		"..##...",
		"..##..."
	],
	"8":
	[
		".#####.",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		".#####.",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		".#####."
	],
	"9":
	[
		".#####.",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		"##...##",
		".######",
		".....##",
		".....##",
		".....##",
		"##...##",
		".#####."
	],
	":":
	[
		".......",
		".......",
		".......",
		".##....",
		".##....",
		".......",
		".......",
		".......",
		".##....",
		".##....",
		".......",
		"......."
	],
	".":
	[
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		"##.....",
		"##....."
	],
	"-":
	[
		".......",
		".......",
		".......",
		".......",
		".......",
		".#####.",
		".......",
		".......",
		".......",
		".......",
		".......",
		"......."
	],
}
## Stencil bridges of the key-number face: none (round 2 fix: a bridged 0 read as "()" at
## distance; the stencil stays on the letters).
const DIGIT_CUTS := {}


## The characters in grid order.
static func chars() -> Array[String]:
	var out: Array[String] = []
	for c in range(FIRST, LAST + 1):
		out.append(char(c))
	for c in EXTRA:
		out.append(char(c))
	return out


## The text face's grid image: white ink on clear.
static func text_image() -> Image:
	var img := Image.create_empty(COLUMNS * CELL.x, ROWS * CELL.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cs := chars()
	for i in cs.size():
		var g := str(TEXT.get(cs[i], ""))
		if g == "":
			push_warning("TankHudFont: no glyph for %s" % cs[i])
			continue
		var at := Vector2i((i % COLUMNS) * CELL.x, (i / COLUMNS) * CELL.y)
		var rows := g.split("/")
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] == "#":
					img.set_pixel(at.x + x, at.y + y, Color.WHITE)
	return img


## Glyph `ch` stretched to the tall face's 11 rows (9 cap, 2 descender).
static func tall_rows(ch: String) -> Array[String]:
	var rows := Array(str(TEXT.get(ch, "")).split("/"))
	while rows.size() < 9:
		rows.append(".....")
	var dup: Array[int] = [1, 4]
	if ch.unicode_at(0) >= 97 and ch.unicode_at(0) <= 122:
		dup = [3, 5]
	var out: Array[String] = []
	for y in 7:
		out.append(str(rows[y]))
		if y in dup:
			out.append(str(rows[y]))
	out.append(str(rows[7]))
	out.append(str(rows[8]))
	return out


static func tall_image() -> Image:
	var img := Image.create_empty(COLUMNS * CELL_T.x, ROWS * CELL_T.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cs := chars()
	for i in cs.size():
		var at := Vector2i((i % COLUMNS) * CELL_T.x, (i / COLUMNS) * CELL_T.y)
		var rows := tall_rows(cs[i])
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] == "#":
					img.set_pixel(at.x + x, at.y + y, Color.WHITE)
	return img


## The key-number strip: DIGIT_CHARS cells of DIGIT_CELL, white on clear.
static func digits_image() -> Image:
	var n := DIGIT_CHARS.length()
	var img := Image.create_empty(n * DIGIT_CELL.x, DIGIT_CELL.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in n:
		var ch := DIGIT_CHARS[i]
		var rows: Array = DIGITS[ch]
		var ox := i * DIGIT_CELL.x
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] == "#":
					img.fill_rect(Rect2i(ox + x * 2, y * 2, 2, 2), Color.WHITE)
		for r: Rect2i in DIGIT_CUTS.get(ch, []):
			img.fill_rect(
				Rect2i(ox + r.position.x, r.position.y, r.size.x, r.size.y), Color(0, 0, 0, 0)
			)
	return img


## Writes both PNGs (globalized res:// paths). Returns OK or the first error.
static func write() -> int:
	var e := text_image().save_png(ProjectSettings.globalize_path(TEXT_PNG))
	if e != OK:
		return e
	e = tall_image().save_png(ProjectSettings.globalize_path(TALL_PNG))
	if e != OK:
		return e
	return digits_image().save_png(ProjectSettings.globalize_path(DIGITS_PNG))

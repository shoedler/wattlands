class_name FishingArtGrids
extends RefCounted
## Turbo Reel's hand-authored pixel art: every sprite as a palette-indexed text grid (one
## character per FishingPalette colour, LEGEND; '.' is transparent) plus the few frames derived
## in code (the fish's tail beat, the cards composed from other sprites).
## tools/fishing_write_sprites.gd writes build() to assets/fishing/sprites/<id>.png (frames side
## by side) and sprites.json; the view only loads the PNGs (FishingSprites). Boat parts are
## drawn to FishingRig's points. Style: flat top-lit planes, no outlines, no dither, 2 px
## structure, hard horizontal and vertical edges, diagonals only in even 1:1 and 2:1 runs.

const LEGEND := {
	"W": FishingPalette.FOAM,
	"1": FishingPalette.SKY,
	"h": FishingPalette.HAZE,
	"a": FishingPalette.SURFACE,
	"b": FishingPalette.UPPER,
	"c": FishingPalette.MID,
	"d": FishingPalette.DEEP,
	"x": FishingPalette.ABYSS,
	"s": FishingPalette.SAGE,
	"w": FishingPalette.WOOD,
	"u": FishingPalette.SLATE,
	"Y": FishingPalette.ACCENT,
}
## Every fish sprite id (fish_<species id>), shallow to legendary.
const FISH: Array[String] = [
	"fish_mackerel",
	"fish_sea_bream",
	"fish_snapper",
	"fish_mahi",
	"fish_tuna",
	"fish_wahoo",
	"fish_swordfish",
	"fish_marlin",
	"fish_grouper",
	"fish_oarfish",
]
## Swim frames per fish: the tail (the last TAIL of the body) beats a pixel up and down.
const SWIM_FRAMES := 4
const SWIM_BEAT: Array[int] = [0, -1, 0, 1]
const TAIL := 0.22
## Crank frames per pose in boat_crew (driving frames first, then fishing).
const CREW_FRAMES := 4
## The minimap and leaderboard action icons, in FishingActions order.
const ICONS: Array[String] = [
	"icon_drive",
	"icon_sprint",
	"icon_wait",
	"icon_fight",
	"icon_landed",
	"icon_paused",
	"icon_afk",
]
## The town's sage ground rows.
const TOWN_BASE_ROWS := 2
## Card size (the game's picker card and the Free Roam and workout cards).
const CARD := Vector2i(160, 90)
## The offset of boat()'s image over the hull's boat-local frame (rows added above for the rod).
const BOAT_PAD := Vector2i(0, 16)

## The winch drum in flat planes (wood top, the wound line, its shade); the line band narrows
## and widens as it turns.
const WINCH: Array = [
	["wwww", "hhhh", "hhhh", "uuuu"],
	["wwww", "hhhh", "uuuu", "uuuu"],
]
## The outboard's prop seen from the side, one tone (it is always under water): four turns.
const PROP: Array = [
	["uu.", "uuu", "uuu", "uuu", ".uu"],
	["...", "uuu", "uuu", "uuu", "..."],
	[".uu", "uuu", "uuu", "uuu", "uu."],
	["...", ".u.", "uuu", ".u.", "..."],
]
## The diving wobbler: lip (accent), lit back, body, belly; two wobble frames.
const LURE: Array = [
	["..bbbb", "YYcccc", "..dddd"],
	["..bbb.", "YYcccc", "..dddd"],
]
const GULL: Array = [
	["uu...uu", "..uuu.."],
	["..uuu..", "uu...uu"],
]
## Splash: a foam crown rising and falling back (every pixel in a run of two or more).
const SPLASH: Array = [
	[
		"...........",
		"...........",
		"...........",
		"...........",
		"...WW.WW...",
		"..WWWWWWW..",
		".hhWWWWWhh.",
	],
	[
		"...........",
		"..WW...WW..",
		"...........",
		"...WW.WW...",
		"..WW...WW..",
		".hh.....hh.",
		"...........",
	],
	[
		".WW.....WW.",
		"...........",
		"...........",
		"...........",
		"...........",
		"...........",
		".hh.....hh.",
	],
]
const SPARKLE: Array = [
	["..W..", "..W..", "WWWWW", "..W..", "..W.."],
	[".....", "..W..", ".WWW.", "..W..", "....."],
	[".....", ".....", ".WW..", ".WW..", "....."],
]
## 11 x 9 action icons: W takes the slot colour (the HUD modulates it), x is the dark detail.
const ICON_GRIDS := {
	"icon_drive":
	[
		[
			"...........",
			"...........",
			"...........",
			"....x......",
			"....x......",
			"..WWWWWWWWx",
			"x.xWWWWWWx.",
			"xxx.xxxxx..",
			"x..........",
		],
		[
			"...........",
			"...........",
			"...........",
			"....x......",
			"....x......",
			"..WWWWWWWWx",
			"..xWWWWWWx.",
			"xxx.xxxxx..",
			"..x........",
		],
	],
	"icon_sprint":
	[
		[
			"...........",
			"...........",
			"....x......",
			"....x......",
			"..WWWWWWWWx",
			"x.xWWWWWWx.",
			"xxx.xxxxx..",
			"...........",
			"WW.WWW.WWWW",
		],
		[
			"...........",
			"...........",
			"....x......",
			"....x......",
			"..WWWWWWWWx",
			"..xWWWWWWx.",
			"xxx.xxxxx..",
			"...........",
			"W.WWW.WWWW.",
		],
	],
	"icon_wait":
	[
		[
			"x..........",
			".x.........",
			"x.x........",
			"x..x.......",
			"x...xWWWWWx",
			"x....xWWWx.",
			"x.....xxx..",
			"x..........",
			"x..........",
		],
		[
			"x..........",
			".x.........",
			"x.x........",
			"x..x.......",
			"x...xWWWWWx",
			"x....xWWWx.",
			"x.....xxx..",
			"x..........",
			"...........",
		],
	],
	"icon_fight":
	[
		[
			"..xxx....W.",
			".x...x...W.",
			"x.....x..W.",
			"x......x.W.",
			"x...xWWW...",
			"x....xWW.W.",
			"x.....xx...",
			"x..........",
			"x..........",
		],
		[
			"..xxx...W..",
			".x...x..W..",
			"x.....x.W..",
			"x......xW..",
			"x...xWWW...",
			"x....xWWW..",
			"x.....xx...",
			"x..........",
			"x..........",
		],
	],
	"icon_landed":
	[
		[
			"...........",
			"...........",
			"...WWWW..x.",
			".WWWWWWW.xx",
			"WxWWWWWWWWx",
			".WWWWWWW.xx",
			"...WWWW..x.",
			"...........",
			"...........",
		],
	],
	"icon_paused":
	[
		[
			"...........",
			"...xx.xx...",
			"...WW.WW...",
			"...WW.WW...",
			"...WW.WW...",
			"...WW.WW...",
			"...WW.WW...",
			"...xx.xx...",
			"...........",
		],
	],
	"icon_afk":
	[
		[
			"......WWWW.",
			".........W.",
			"........W..",
			".......W...",
			"WWW...WWWW.",
			"..W........",
			".W.........",
			"WWW........",
			"...........",
		],
	],
}


## Every sprite: {id: {"frames": Array[Image], "anchor": Vector2i, "desc": String}}.
static func build() -> Dictionary:
	var out := {}
	_add(
		out, "boat_hull", hull_poses(), Vector2i.ZERO, "pedal boat hull, level and two bow-up poses"
	)
	_add(out, "boat_crew", frames_of(CREW), Vector2i.ZERO, "seated cyclist, flywheel, clutch")
	_add(out, "boat_winch", frames_of(WINCH), Vector2i(2, 2), "winch drum with wound line")
	_add(out, "boat_prop", frames_of(PROP), Vector2i(1, 2), "screw propeller")
	_add(out, "lure", frames_of(LURE), Vector2i(0, 1), "diving wobbler lure")
	_add(out, "gull", frames_of(GULL), Vector2i(3, 1), "gull, two wingbeats")
	_add(out, "fx_splash", frames_of(SPLASH), Vector2i(5, 6), "splash")
	_add(out, "fx_sparkle", frames_of(SPARKLE), Vector2i(2, 2), "catch sparkle")
	for id: String in FISH:
		var base := img(fish_grid(id))
		var frames: Array[Image] = []
		for k in SWIM_FRAMES:
			frames.append(swim(base, k))
		_add(out, id, frames, Vector2i(0, mouth_row(base) + 1), "fish facing left, mouth at anchor")
	for id: String in ICONS:
		_add(out, id, frames_of(ICON_GRIDS[id]), Vector2i(5, 4), "action icon")
	var town := town_img()
	_add(out, "scenery_town", [town], Vector2i(0, town.get_height()), "harbour town in the haze")
	_add(out, "scenery_pier", [img(SCENERY_PIER)], Vector2i(0, 6), "pier, deck top on row 6")
	_add(out, "picker_card", [card(0)], Vector2i.ZERO, "the game's picker card")
	_add(out, "card_roam", [card(1)], Vector2i.ZERO, "Free Roam card")
	_add(out, "card_workout", [card(2)], Vector2i.ZERO, "workout card")
	return out


## The harbour town: its haze houses on a TOWN_BASE_ROWS sage ground strip, so it reads as land
## and not as a swell of the far water.
static func town_img() -> Image:
	var town := img(hjoin(SCENERY_TOWN_L, SCENERY_TOWN_R))
	for y in range(town.get_height() - TOWN_BASE_ROWS, town.get_height()):
		for x in town.get_width():
			if town.get_pixel(x, y).a > 0.5:
				town.set_pixel(x, y, FishingPalette.SAGE)
	return town


static func _add(
	out: Dictionary, id: String, frames: Array[Image], anchor: Vector2i, desc: String
) -> void:
	out[id] = {"frames": frames, "anchor": anchor, "desc": desc}


static func fish_grid(id: String) -> Array[String]:
	match id:
		"fish_mackerel":
			return FISH_MACKEREL
		"fish_sea_bream":
			return FISH_SEA_BREAM
		"fish_snapper":
			return FISH_SNAPPER
		"fish_mahi":
			return FISH_MAHI
		"fish_tuna":
			return FISH_TUNA
		"fish_wahoo":
			return FISH_WAHOO
		"fish_swordfish":
			return FISH_SWORDFISH
		"fish_marlin":
			return FISH_MARLIN
		"fish_grouper":
			return FISH_GROUPER
	return FISH_OARFISH


## An image from text rows (LEGEND; '.' and unknown characters are transparent).
static func img(rows: Array) -> Image:
	var w := 1
	for r: String in rows:
		w = maxi(w, r.length())
	var out := Image.create_empty(w, maxi(rows.size(), 1), false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if LEGEND.has(ch):
				out.set_pixel(x, y, LEGEND[ch])
	return out


## Rows of `a` followed by the same rows of `b`.
static func hjoin(a: Array[String], b: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for i in a.size():
		out.append(a[i] + b[i])
	return out


## The hull level and in each bow-up pose (FishingRig.TILT): every column of the level grid
## moved by its band's whole pixels, so the planes stay flat with clean 1 px steps between bands.
static func hull_poses() -> Array[Image]:
	var level := img(BOAT_HULL[0])
	var out: Array[Image] = [level]
	for pose in range(1, FishingRig.TILT.size()):
		var f := Image.create_empty(
			level.get_width(), level.get_height(), false, level.get_format()
		)
		f.fill(Color(0, 0, 0, 0))
		for x in level.get_width():
			var dy := FishingRig.tilt_dy(pose, x)
			for y in level.get_height():
				var c := level.get_pixel(x, y)
				if c.a > 0.5 and y + dy >= 0 and y + dy < level.get_height():
					f.set_pixel(x, y + dy, c)
		out.append(f)
	return out


static func frames_of(grids: Array) -> Array[Image]:
	var out: Array[Image] = []
	for g: Array in grids:
		out.append(img(g))
	return out


## The first row with a pixel in the leftmost column (the mouth of a left-facing fish).
static func mouth_row(base: Image) -> int:
	for y in base.get_height():
		if base.get_pixel(0, y).a > 0.5:
			return y
	return base.get_height() / 2


## Swim frame k of a left-facing fish: the tail block (the last TAIL of the columns) moves by
## SWIM_BEAT[k] rows as a whole, so the body keeps its flat planes. The frame gains a row top
## and bottom so nothing is clipped.
static func swim(base: Image, k: int) -> Image:
	var w := base.get_width()
	var h := base.get_height()
	var out := Image.create_empty(w, h + 2, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var tail_x := floori(float(w) * (1.0 - TAIL))
	for x in w:
		var dy := SWIM_BEAT[posmod(k, SWIM_BEAT.size())] if x >= tail_x else 0
		for y in h:
			var c := base.get_pixel(x, y)
			if c.a > 0.5:
				out.set_pixel(x, y + 1 + dy, c)
	return out


## The pixels of FishingRig's runs through `points` in `c`.
static func plot(target: Image, points: Array[Vector2i], c: Color) -> void:
	var r := Rect2i(Vector2i.ZERO, target.get_size())
	for p in FishingRig.raster_path(points):
		if r.has_point(p):
			target.set_pixel(p.x, p.y, c)


## `src` drawn onto `dst` at `at` (opaque pixels only).
static func blit(dst: Image, src: Image, at: Vector2i) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			var p := at + Vector2i(x, y)
			if c.a > 0.5 and Rect2i(Vector2i.ZERO, dst.get_size()).has_point(p):
				dst.set_pixel(p.x, p.y, c)


## The assembled boat (hull, crew, winch, prop, rod, cap and pennant in the first player's
## colour, the rows under the waterline in one water tone) as one image: `fishing` false drives
## (leaning to the bar, clutch forward, rod stowed), true fishes. Cards and previews use it.
static func boat(fishing: bool, k: int = 0) -> Image:
	var out := img(BOAT_HULL[0])
	var pose := 1 if fishing else 0
	blit(out, img(CREW[pose * CREW_FRAMES + posmod(k, CREW_FRAMES)]), Vector2i(FishingRig.CREW_AT))
	blit(out, img(WINCH[posmod(k, 2) if fishing else 0]), Vector2i(FishingRig.WINCH_AT))
	blit(out, img(PROP[0 if fishing else posmod(k, 4)]), Vector2i(FishingRig.PROP_AT))
	var rod := FishingRig.rod(1.0 if fishing else 0.0, 0.0)
	var tall := Image.create_empty(
		out.get_width(), out.get_height() + BOAT_PAD.y, false, out.get_format()
	)
	tall.fill(Color(0, 0, 0, 0))
	blit(tall, out, BOAT_PAD)
	for p in rod:
		tall.set_pixelv(p + BOAT_PAD, FishingPalette.SLATE)
	var col := FishingPalette.player(0)
	tall.fill_rect(Rect2i(FishingRig.CAP.position + BOAT_PAD, FishingRig.CAP.size), col)
	tall.fill_rect(Rect2i(FishingRig.FLAG.position + BOAT_PAD, FishingRig.FLAG.size), col)
	for y in range(FishingRig.WATERLINE + BOAT_PAD.y, tall.get_height()):
		for x in tall.get_width():
			if tall.get_pixel(x, y).a > 0.5:
				tall.set_pixel(x, y, FishingPalette.UPPER)
	return tall


## Card `kind` (0 the game's picker card, 1 Free Roam, 2 workout): the flat sky, the haze town,
## the water bands, the boat and a fish, composed from the sprites above.
static func card(kind: int) -> Image:
	var out := Image.create_empty(CARD.x, CARD.y, false, Image.FORMAT_RGBA8)
	var surf := 46
	out.fill(FishingPalette.SKY)
	if kind != 2:
		blit(out, town_img(), Vector2i(-20 if kind == 0 else -60, surf - 2 - 30))
	out.fill_rect(Rect2i(0, surf - 2, CARD.x, 2), FishingPalette.HAZE)
	var tops: Array[int] = [surf, surf + 18, surf + 30, surf + 39]
	for i in tops.size():
		out.fill_rect(Rect2i(0, tops[i], CARD.x, CARD.y - tops[i]), FishingPalette.SEA[i])
	var fish := "fish_marlin" if kind == 0 else ("fish_grouper" if kind == 1 else "fish_tuna")
	var fimg := swim(img(fish_grid(fish)), 1)
	var fat := Vector2i(96, 58) if kind == 1 else Vector2i(4, 64 if kind == 0 else 66)
	var band := 0
	for i in tops.size():
		if fat.y + fimg.get_height() / 2 >= tops[i]:
			band = i
	_shift(fimg, FishingPaletteMap.shift_for(band))
	var b := boat(kind != 1, 1)
	var bat := Vector2i(40 if kind == 1 else 58, surf - FishingRig.WATERLINE) - BOAT_PAD
	if kind == 1:
		blit(out, fimg, fat)
		blit(out, b, bat)
		var stern := bat + BOAT_PAD + Vector2i(FishingRig.WAKE_AT)
		for k in 3:
			var w: int = [8, 5, 3][k]
			var x0: int = stern.x - 2 - [0, 12, 21][k] - w
			out.fill_rect(Rect2i(x0, surf, w, 1), FishingPalette.FOAM)
		return out
	fimg.flip_x()
	blit(out, fimg, fat)
	blit(out, b, bat)
	var tip := FishingRig.rod(1.0, 0.0)[-1] + bat + BOAT_PAD
	var mouth := fat + Vector2i(fimg.get_width() - 1, mouth_row(img(fish_grid(fish))) + 1)
	for p in FishingRig.raster(tip, mouth):
		out.set_pixelv(p, FishingPalette.LINE if p.y < surf else FishingView.line_under())
	return out


## Every LADDER colour in `image` moved `steps` steps (FishingPaletteMap's shift, baked).
static func _shift(image: Image, steps: int) -> void:
	var to := {}
	for c in FishingPalette.LADDER:
		to[c.to_html(false)] = FishingPalette.darker(c, steps)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a > 0.5 and to.has(c.to_html(false)):
				image.set_pixel(x, y, to[c.to_html(false)])


## The hull, level (hull_poses() derives the bow-up frames from it).
const BOAT_HULL: Array = [
	[
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
		".......................................................................................u........",
		".......................................................................................u........",
		".......................................................................................u........",
		".......................................................................................u........",
		".......................................................................................u........",
		".......................................................................................u........",
		"...................wwwww..wwwwwwww.....................................................u........",
		"...................uuuuu..uuuuuuuu.....................................................u........",
		"...................uuuuu..uuuuuuuu..........................................WWWWWWWWWWWWW.......",
		".....................uu...uuuuuuuu..........................................WWWWWWWWWWWWWW......",
		".....................uu.WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWwwwwwwwwwwwwwww.....",
		".....................uu.WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWwwwwwwwwwwwwwww.....",
		".....................uu.wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwuuuuuuuuuuuuuuu.....",
		".....................uu.wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwuuuuuuuuuuuuuu......",
		".....................uu.uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu......",
		".....................uu.uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu.......",
		".....................uu.uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu.......",
		".....................uu.uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu........",
		".....................uu.uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu........",
		".....................uu.uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu.........",
		".....................uu.uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu..........",
		".........................uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu............",
		"...........................uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu...............",
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
		"................................................................................................",
	],
]
const CREW: Array = [
	[
		"..............................",
		"..............................",
		"..........xx..................",
		"..........xx..................",
		".........uxww.................",
		".........uxxx.................",
		".........uxxxxxxxx............",
		".........uxxxxxxxx............",
		"....YY...uxxx.....uuuu........",
		"....uu...uxxx...uuuuuuuu......",
		"....uu...uxxx...uu....uu......",
		"...uu....uxxx..uu......uu.....",
		"...uu....uxxxxxxxxxxxxxxu.....",
		"...uu....uxxxxxxxxxxxxxxu.....",
		".........uxxx..uu......uu.....",
		"........wwwwww..uu....uu......",
		"........uuuuuu..uuuuuuuu......",
		"........uuuuuu....uuuu........",
	],
	[
		"..............................",
		"..............................",
		"..........xx..................",
		"..........xx..................",
		".........uxww.................",
		".........uxxx.................",
		".........uxxxxxxxx............",
		".........uxxxxxxxx............",
		"....YY...uxxx.....uuuu........",
		"....uu...uxxx...uuuuuuuu......",
		"....uu...uxxx...uu....uu......",
		"...uu....uxxx..uu......uu.....",
		"...uu....uxxxxxxxxxxx..uu.....",
		"...uu....uxxxxxxxxxxx..uu.....",
		".........uxxx..uu..xx..uu.....",
		"........wwwwww..uu.xx.uu......",
		"........uuuuuu..uuuxxuuu......",
		"........uuuuuu....uuuu........",
	],
	[
		"..............................",
		"..............................",
		"..........xx..................",
		"..........xx..................",
		".........uxww.................",
		".........uxxx.................",
		".........uxxxxxxxx............",
		".........uxxxxxxxx............",
		"....YY...uxxx.....uuuu........",
		"....uu...uxxx...uuuuuuuu......",
		"....uu...uxxx...uu....uu......",
		"...uu....uxxx..uu......uu.....",
		"...uu....uxxxxxxxx.YY..uu.....",
		"...uu....uxxxxxxxx.YY..uu.....",
		".........uxxx..uu......uu.....",
		"........wwwwww..uu....uu......",
		"........uuuuuu..uuuuuuuu......",
		"........uuuuuu....uuuu........",
	],
	[
		"..............................",
		"..............................",
		"..........xx..................",
		"..........xx..................",
		".........uxww.................",
		".........uxxx.................",
		".........uxxxxxxxx............",
		".........uxxxxxxxx............",
		"....YY...uxxx.....uuuu........",
		"....uu...uxxx...uuuxxuuu......",
		"....uu...uxxx...uu.xx.uu......",
		"...uu....uxxxxxxxxxxx..uu.....",
		"...uu....uxxxxxxxxxxx..uu.....",
		"...uu....uxxx..uu..YY..uu.....",
		".........uxxx..uu......uu.....",
		"........wwwwww..uu....uu......",
		"........uuuuuu..uuuuuuuu......",
		"........uuuuuu....uuuu........",
	],
	[
		"..............................",
		"..............................",
		"..........xx..................",
		"..........xx..................",
		".........uxww.................",
		".........uxxx.................",
		".........uxxx.................",
		"...xxxxxxuxxx.................",
		".YYxxxxxxuxxx.....uuuu........",
		".uu......uxxx...uuuuuuuu......",
		".uu......uxxx...uu....uu......",
		"..uu.....uxxx..uu......uu.....",
		"..uu.....uxxxxxxxxxxxxxxu.....",
		"..uu.....uxxxxxxxxxxxxxxu.....",
		".........uxxx..uu......uu.....",
		"........wwwwww..uu....uu......",
		"........uuuuuu..uuuuuuuu......",
		"........uuuuuu....uuuu........",
	],
	[
		"..............................",
		"..............................",
		"..........xx..................",
		"..........xx..................",
		".........uxww.................",
		".........uxxx.................",
		".........uxxx.................",
		"...xxxxxxuxxx.................",
		".YYxxxxxxuxxx.....uuuu........",
		".uu......uxxx...uuuuuuuu......",
		".uu......uxxx...uu....uu......",
		"..uu.....uxxx..uu......uu.....",
		"..uu.....uxxxxxxxxxxx..uu.....",
		"..uu.....uxxxxxxxxxxx..uu.....",
		".........uxxx..uu..xx..uu.....",
		"........wwwwww..uu.xx.uu......",
		"........uuuuuu..uuuxxuuu......",
		"........uuuuuu....uuuu........",
	],
	[
		"..............................",
		"..............................",
		"..........xx..................",
		"..........xx..................",
		".........uxww.................",
		".........uxxx.................",
		".........uxxx.................",
		"...xxxxxxuxxx.................",
		".YYxxxxxxuxxx.....uuuu........",
		".uu......uxxx...uuuuuuuu......",
		".uu......uxxx...uu....uu......",
		"..uu.....uxxx..uu......uu.....",
		"..uu.....uxxxxxxxx.YY..uu.....",
		"..uu.....uxxxxxxxx.YY..uu.....",
		".........uxxx..uu......uu.....",
		"........wwwwww..uu....uu......",
		"........uuuuuu..uuuuuuuu......",
		"........uuuuuu....uuuu........",
	],
	[
		"..............................",
		"..............................",
		"..........xx..................",
		"..........xx..................",
		".........uxww.................",
		".........uxxx.................",
		".........uxxx.................",
		"...xxxxxxuxxx.................",
		".YYxxxxxxuxxx.....uuuu........",
		".uu......uxxx...uuuxxuuu......",
		".uu......uxxx...uu.xx.uu......",
		"..uu.....uxxxxxxxxxxx..uu.....",
		"..uu.....uxxxxxxxxxxx..uu.....",
		"..uu.....uxxx..uu..YY..uu.....",
		".........uxxx..uu......uu.....",
		"........wwwwww..uu....uu......",
		"........uuuuuu..uuuuuuuu......",
		"........uuuuuu....uuuu........",
	],
]
const FISH_MACKEREL: Array[String] = [
	"...bbbbbbbbb...cc",
	".bbxbbbbbbbbbb.cc",
	"cccccccccccccccc.",
	".ddddddddddddd.cc",
	"...ddddddddd...cc",
]
const FISH_SEA_BREAM: Array[String] = [
	"....bbbbbb....c",
	"..bbbbbbbbb..cc",
	".bbxbbbbbbbb.cc",
	"cccccccccccccc.",
	"cccccccccccccc.",
	".dddccccccdd.cc",
	"..ddddddddd..cc",
	"....dddddd....c",
]
const FISH_SNAPPER: Array[String] = [
	".....YYYYYY........",
	"....bbbbbbbb.....cc",
	"..bbbbbbbbbbbb..ccc",
	".bbxbbbbbbbbbbb.cc.",
	"ccccccccccccccccc..",
	"ccccccccccccccccc..",
	".dddccccccccddd.cc.",
	"..dddddddddddd..ccc",
	"....dddddddd.....cc",
]
const FISH_MAHI: Array[String] = [
	"...bbbbbbbbbbbbbbbbbbb.....ccc.",
	".bbbbbbbbbbbbbbbb.........cccc.",
	".bbbbbbbbbbbbbbbbbb......ccccc.",
	".bbxbbbbbbbbbbbbbbbbb...ccccc..",
	".ccbbbbbbbbbbbbbbbbbbbb.cccc...",
	"cccccccccccccccccccccbbbcc.....",
	"cccccccccccccccccccccccccc.....",
	"cccccccccccccccccccccdddccdd...",
	".ddccccccccccccccdddddd.ccddd..",
	".dddddddddddddddddddd....cdddd.",
	".dddddddddddddddddd.......dddd.",
	"...dddddddddddddd..........ddd.",
]
const FISH_TUNA: Array[String] = [
	".......bbbbbbbbbbb..........cc.",
	"....bbbbbbbbbbbbbbbb.......cc..",
	"..bbbbbbbbbbbbbbbbbbbb....cc...",
	".bbxbbbcccccccccccbbbbbb.cc....",
	"ccccccccccccccccccccccccccc....",
	"ccccccccccccccccccccccccccc....",
	".dddccccccccccccccccdddd.cc....",
	"..dddddddddddddddddddd....cc...",
	"....dddddddddddddddd.......cc..",
	".......ddddddddddd..........cc.",
]
const FISH_WAHOO: Array[String] = [
	"...bbbbbbbbbbbbbbbbbbbbbbbbbbb....cc.",
	".bbxbbbbbbbbbbbbbbbbbbbbbbbbbbbb.cc..",
	"cccccccccccccccccccccccccccccccccc...",
	"cccccccccccccccccccccccccccccccccc...",
	".ddddddddddddddddddddddddddddddd.cc..",
	"...ddddddddddddddddddddddddddd....cc.",
]
const FISH_SWORDFISH: Array[String] = [
	"..................bbbb...................cc...",
	".................bbbbbbbbbbbb...........cc....",
	".............bbbbbbbbbbbbbbbbbbbb......cc.....",
	"...........bbbbbbbbbbbbbbbbbbbbbbbbb..cc......",
	"..........bbxccccccccccccccccccccccccccc......",
	"cccccccccccccccccccccccccccccccccccccccc......",
	"..........dddccccccccccccccccddddddd..cc......",
	"...........dddddddddddddddddddddd......cc.....",
	".............dddddddddddddddd...........cc....",
	".........................................cc...",
]
const FISH_MARLIN: Array[String] = [
	"..................bbbbb...........................cc..",
	".................bbbbbbbb........................cc...",
	"................bbbbbbbbbbbb....................ccc...",
	"...............bbbbbbbbbbbbbbbb.................cc....",
	"..............bbbbbbbbbbbbbbbbbbbb.............cc.....",
	".............bbbbbbbbbbbbbbbbbbbbbb...........cc......",
	"...........bbbbbbbbbbbbbbbbbbbbbbbbbbbb.......cc......",
	"..........bbxccccccccccccccccccccccccccbbbbccccc......",
	"cccccccccccccccccccccccccccccccccccccccccccccccc......",
	"..........ddddddddddddddddddddddddddddddddd...cc......",
	"...........dddddddddddddddddddddddd...........ccc.....",
	"...............................................ccc....",
	"................................................ccc...",
]
const FISH_GROUPER: Array[String] = [
	"..............hhhhhhhhhhhh....................",
	"..........hhhhhhhhhhhhhhhhhhhh................",
	".........hhhhhhhhhhhhhhhhhhh..............bb..",
	"......hhhhhhhhhhhhhhhhhhhhhhhhhh.........bbb..",
	"....hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh.....bbbb..",
	"..hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh....bbbbb..",
	".hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh..bbbbb..",
	"hhhhhhhxhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhbbbbb..",
	"hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhbbbbb..",
	"hhhhhhbbbbbbbbbbbbbbbbbbbbbbbbbbbbbhhhhbbbbb..",
	"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb..",
	"...bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb..",
	"...bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbccccbbbbb..",
	"bbccbbbbbbbbbbbbbbbbbbbbbbbbbbbbcccccccbbbbb..",
	"ccccccccccccccccccccccccccccccccccccc..bbbbb..",
	"ccccccccccccccccccccccccccccccccccc.....bbbb..",
	".cccccccccccccccccccccccccccccccccc......bbb..",
	"....cccccccccccccccccccccccccccc..........bb..",
	"......cccccccccccccccccccccc..................",
	"..............................................",
]
const FISH_OARFISH: Array[String] = [
	"..YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY..",
	"...bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...",
	".bbxbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbc",
	"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
	"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
	".ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddc",
	"...dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd...",
]
## The town is stored in two halves (line length); hjoin() puts them side by side.
const SCENERY_TOWN_L: Array[String] = [
	"....................................................................................",
	"...............................................hh...................................",
	"...............................................hh...................................",
	"..............................................WWWW..................................",
	"..............................................WWWW..................................",
	"..............................................WWWW.............................hh...",
	".............................................hhhhhh............................hh...",
	".............................................hhhhhh............................hh...",
	"..............................................hhhs.............................hh...",
	"..............................................hhhs............................hhhs..",
	"..............................................hhhs............................hhhs..",
	"..............................................hhhs............................hhhs..",
	"..............................................hhhs............................hhhs..",
	"..............................................hhhs............................hhhs..",
	"..............................................hhhs............................hhhs..",
	"..............................................hhhs............................hhhs..",
	"..............................................hhhs............................hhhs..",
	"..............................................hhhs.....................hh.....hhhs..",
	"................hh.....................hh.....hhhs.......hh...........hhhh....hhhs..",
	"......hh.......hhhh...................hhhh....hhhs......hhhh.........hhhhhh...hhhs..",
	".....hhhh.....hhhhhh.................hhhhhh...hhhs.....hhhhhh.......hhhhhhhh..hhhs..",
	"....hhhhhh...hhhhhhhh................hhhhhs...hhhs....hhhhhhhh.....hhhhhhhhhh.hhhs..",
	"...hhhhhhhh..hhhhhhhs................hhhhhs...hhhs...hhhhhhhhhh...hhhhhhhhhhhhhhhs..",
	"..hhhhhhhhhh.hhhhhhhs................hhhhhs...hhhs..hhhhhhhhhhhh..hhhhhhhhhhsshhhs..",
	"..hhhhhhhhhs.hhhhhhhs................hhhhhs...hhhs..hhhhhhhhhhhs..hhhhhhhhhhsshhhs..",
	"..hhhhhhhhhs.hhhhhhhshhhhhhhhhhhhhhhhhhhhhs...hhhs..hhhhhhhhhhhs..hhhhhhhhhhsshhhs..",
	"..hhhhhhhhhs.hhhhhhhs.hhhhhhhhhhhhss.hhhhhs...hhhs..hhhhhhhhhhhs..hhhhhhhhhhsshhhs.h",
	"..hhhhhhhhhs.hhhhhhhs.hhhhhhhhhhhhss.hhhhhs...hhhs..hhhhhhhhhhhs..hhhhhhhhhhsshhhs..",
	"..hhhhhhhhhs.hhhhhhhs.hhhhhhhhhhhhss.hhhhhs...hhhs..hhhhhhhhhhhs..hhhhhhhhhhsshhhs..",
	"..hhhhhhhhhs.hhhhhhhs.hhhhhhhhhhhhss.hhhhhs...hhhs..hhhhhhhhhhhs..hhhhhhhhhhsshhhs..",
]
const SCENERY_TOWN_R: Array[String] = [
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"........................h...........................................................",
	".......................hhh..........................................................",
	"......................hhhhh.........................................................",
	".....................hhhhhhh.....h..................................................",
	"....................hhhhhhhhh...hhh.................................................",
	"....................hhhhhhhhs..hhhhh................................................",
	"....................hhhhhhhhs.hhhhhhh...............................................",
	"....................hhhhhhhhs.hhhhhhs...............................................",
	"....................hhhhhhhhs.hhhhhhs........hhhhhhhhhhhhhhhhhh.....................",
	"hhhhhhhhhhhhhhhhhhh.hhhhhhhhs.hhhhhhs.........hhhhhhhhhhhhhhss......................",
	"hhhhhhhhhhhhhhhhss..hhhhhhhhs.hhhhhhs.........hhhhhhhhhhhhhhss.hhhhhhhhhhhh.........",
	"hhhhhhhhhhhhhhhhss..hhhhhhhhs.hhhhhhs.........hhhhhhhhhhhhhhss..hhhhhhhhhs..........",
	"hhhhhhhhhhhhhhhhss..hhhhhhhhs.hhhhhhs.........hhhhhhhhhhhhhhss..hhhhhhhhhs..........",
]
const SCENERY_PIER: Array[String] = [
	".............................................................uuu........",
	"..............................................................u.........",
	"..............................................................u.........",
	"..............................................................u.........",
	"....................uu......................uu................u.........",
	"....................uu......................uu................u.........",
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	"wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww",
	"wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww",
	"....uu..............uu..............uu..............uu..............uu..",
	"....uu..............uu..............uu..............uu..............uu..",
	"....bb..............bb..............bb..............bb..............bb..",
	"....bb..............bb..............bb..............bb..............bb..",
	"....bb..............bb..............bb..............bb..............bb..",
	"....bb..............bb..............bb..............bb..............bb..",
	"....bb..............bb..............bb..............bb..............bb..",
	"....bb..............bb..............bb..............bb..............bb..",
	"....bb..............bb..............bb..............bb..............bb..",
	"....bb..............bb..............bb..............bb..............bb..",
]

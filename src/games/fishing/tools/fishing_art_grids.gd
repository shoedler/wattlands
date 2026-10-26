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
	"n": FishingPalette.MID,
	"p": FishingPalette.DEEP,
}
## The fish grids' fin characters (fins, the pectoral, accent fins): a tired fish folds them.
const FIN_CHARS := "npY"
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
## A fish sprite's frames (FishingSprites.FISH_* indices): three swim frames (the tail block
## beats a row up and down, its tip two), the pulls at 15 and 30 degrees (columns moved whole
## rows toward the mouth, 1 per PULL_RUNS columns, the tail kicked a row; never rotated) and
## tired (fins folded, the tail sagging, no eye highlight). Every frame has the mouth on the
## sprite's anchor.
const FISH_POSES: Array[String] = ["swim1", "swim2", "swim3", "pull15", "pull30", "tired"]
const SWIM_FRAMES := 3
const PULL_RUNS: Array[int] = [4, 2]
## Frames per pose in boat_crew (the drivetrain is drawn by FishingBoatView, so one each).
const CREW_FRAMES := 1
## Crew poses after CREW's two: leaning into a sprint, sat back braking ([last row, dx] bands
## from the top; rows past the last band stay).
const CREW_POSES := 4
const CREW_LEAN_FWD: Array[Vector2i] = [Vector2i(3, 2), Vector2i(7, 1)]
const CREW_LEAN_BACK: Array[Vector2i] = [Vector2i(5, -1)]
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
		out,
		"boat_hull",
		hull_poses(),
		Vector2i.ZERO,
		"pedal boat hull: level, five bow-up and two braking poses"
	)
	_add(
		out,
		"boat_crew",
		crew_frames(),
		Vector2i.ZERO,
		"seated cyclist: drive, fish, lean in, sit back"
	)
	_add(out, "boat_winch", frames_of(WINCH), Vector2i(2, 2), "winch drum with wound line")
	_add(out, "boat_prop", frames_of(PROP), Vector2i(1, 2), "screw propeller")
	_add(out, "lure", frames_of(LURE), Vector2i(0, 1), "diving wobbler lure")
	_add(out, "gull", frames_of(GULL), Vector2i(3, 1), "gull, two wingbeats")
	_add(out, "fx_splash", frames_of(SPLASH), Vector2i(5, 6), "splash")
	_add(out, "fx_sparkle", frames_of(SPARKLE), Vector2i(2, 2), "catch sparkle")
	for id: String in FISH:
		var ff := fish_frames(id)
		_add(out, id, ff["frames"], ff["anchor"], "fish facing left: swim x3, pull 15/30, tired")
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


## The hull in every pose, in FishingRig.hull_frame() order: each column of the level grid
## moved by its band's whole pixels (FishingRig.tilt_dy), so the planes stay flat with clean
## 1 px steps between bands.
static func hull_poses() -> Array[Image]:
	var level := img(BOAT_HULL[0])
	var out: Array[Image] = []
	out.resize(FishingRig.POSE_MAX - FishingRig.POSE_MIN + 1)
	for pose in range(FishingRig.POSE_MIN, FishingRig.POSE_MAX + 1):
		out[FishingRig.hull_frame(pose)] = _sheared(level, pose)
	return out


static func _sheared(level: Image, pose: int) -> Image:
	var f := Image.create_empty(level.get_width(), level.get_height(), false, level.get_format())
	f.fill(Color(0, 0, 0, 0))
	for x in level.get_width():
		var dy := FishingRig.tilt_dy(pose, x)
		for y in level.get_height():
			var c := level.get_pixel(x, y)
			if c.a > 0.5 and y + dy >= 0 and y + dy < level.get_height():
				f.set_pixel(x, y + dy, c)
	return f


## The crew sheet: driving and fishing (CREW), then driving leaning forward (a sprint) and sat
## back (braking): the head and torso rows moved whole pixels (CREW_LEAN_FWD, CREW_LEAN_BACK:
## [last row, dx] from the top).
static func crew_frames() -> Array[Image]:
	var out := frames_of(CREW)
	for lean: Array in [CREW_LEAN_FWD, CREW_LEAN_BACK]:
		out.append(_leaned(img(CREW[0]), lean))
	return out


static func _leaned(base: Image, lean: Array) -> Image:
	var f := Image.create_empty(base.get_width(), base.get_height(), false, base.get_format())
	f.fill(Color(0, 0, 0, 0))
	for y in base.get_height():
		var dx := 0
		for band: Vector2i in lean:
			if y <= band.x:
				dx = band.y
				break
		for x in base.get_width():
			var c := base.get_pixel(x, y)
			if c.a > 0.5 and x + dx >= 0 and x + dx < base.get_width():
				f.set_pixel(x + dx, y, c)
	return f


static func frames_of(grids: Array) -> Array[Image]:
	var out: Array[Image] = []
	for g: Array in grids:
		out.append(img(g))
	return out


## The mouth row of a left-facing fish grid: the middle of its leftmost column's pixels.
static func mouth_row(rows: Array[String]) -> int:
	var lo := -1
	var hi := -1
	for y in rows.size():
		if rows[y].length() > 0 and rows[y][0] != ".":
			lo = y if lo < 0 else lo
			hi = y
	return (lo + hi) / 2 if lo >= 0 else rows.size() / 2


## Every frame of fish `id` (FISH_POSES) on one canvas size with the mouth on the same pixel:
## {"frames": Array[Image], "anchor": Vector2i (the mouth)}.
static func fish_frames(id: String) -> Dictionary:
	var rows := fish_grid(id)
	var poses: Array[Dictionary] = []
	var above := 0
	var below := 0
	var w := 1
	for r in rows:
		w = maxi(w, r.length())
	for kind in FISH_POSES:
		var p := fish_pose(id, kind)
		poses.append(p)
		var my := int(p["mouth"])
		for at: Vector2i in p["px"]:
			above = maxi(above, my - at.y)
			below = maxi(below, at.y - my)
	var frames: Array[Image] = []
	for p in poses:
		var f := Image.create_empty(w, above + below + 1, false, Image.FORMAT_RGBA8)
		f.fill(Color(0, 0, 0, 0))
		var dy := above - int(p["mouth"])
		var px: Dictionary = p["px"]
		for at: Vector2i in px:
			f.set_pixel(at.x, at.y + dy, LEGEND[px[at]])
		frames.append(f)
	return {"frames": frames, "anchor": Vector2i(0, above)}


## Fish `id` in pose `kind` (FISH_POSES): {"px": {Vector2i: grid character}, "mouth": row}.
static func fish_pose(id: String, kind: String) -> Dictionary:
	var rows := fish_grid(id)
	var w := 1
	for r in rows:
		w = maxi(w, r.length())
	var shape: Array = FISH_SHAPES.get(id, [w - 4, w - 2])
	var tail_x := int(shape[0])
	var tip_x := int(shape[1])
	var mouth := mouth_row(rows)
	var src := {}
	var body_top := rows.size()
	var body_bottom := -1
	for y in rows.size():
		for x in rows[y].length():
			var ch := rows[y][x]
			if LEGEND.has(ch):
				src[Vector2i(x, y)] = ch
				if not FIN_CHARS.contains(ch) and ch != "x" and ch != "W":
					body_top = mini(body_top, y)
					body_bottom = maxi(body_bottom, y)
	var dys: Array[int] = []
	dys.resize(w)
	var fold := false
	match kind:
		"swim1", "swim2", "swim3":
			var b := FISH_POSES.find(kind) - 1
			for x in w:
				dys[x] = 0 if x < tail_x else (b if x < tip_x else 2 * b)
		"pull15", "pull30":
			var run := PULL_RUNS[0 if kind == "pull15" else 1]
			for x in w:
				dys[x] = -((w - 1 - mini(x, tail_x)) / run) + (1 if x >= tail_x else 0)
		_:
			fold = true
			var mid := tail_x / 2
			for x in w:
				dys[x] = maxi(0, (mini(x, tail_x) - mid) / 6) + (1 if x >= tail_x else 0)
	var px := {}
	for at: Vector2i in src:
		var ch: String = src[at]
		if fold and FIN_CHARS.contains(ch) and (at.y < body_top or at.y > body_bottom):
			continue
		if fold and ch == "W":
			ch = "c"
		px[Vector2i(at.x, at.y + dys[at.x])] = ch
	return {"px": px, "mouth": mouth + dys[0]}


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
	blit(out, img(CREW[pose]), Vector2i(FishingRig.CREW_AT))
	for p in FishingRig.drivetrain(float(k) * TAU / 4.0):
		var at := Vector2i(FishingRig.CREW_AT) + Vector2i(p.x, p.y)
		out.set_pixelv(at, FishingRig.DRIVE_COLOURS[p.z])
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
	var ff := fish_frames(fish)
	var full: Image = (ff["frames"] as Array)[0]
	var used := full.get_used_rect()
	var fimg := full.get_region(used)
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
	var mouth := (
		fat + Vector2i(fimg.get_width() - 1, (ff["anchor"] as Vector2i).y - used.position.y)
	)
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


## The hull, level (hull_poses() derives the other poses from it).
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
## The crew without its drivetrain (FishingBoatView draws the flywheel ring, the crank and
## the leg at the exact crank angle): driving (hand on the tiller) and fishing (clutch aft).
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
		"....YY...uxxx.................",
		"....uu...uxxx.................",
		"....uu...uxxx.................",
		"...uu....uxxx.................",
		"...uu....uxxx.................",
		"...uu....uxxx.................",
		".........uxxx.................",
		"........wwwwww................",
		"........uuuuuu................",
		"........uuuuuu................",
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
		".YYxxxxxxuxxx.................",
		".uu......uxxx.................",
		".uu......uxxx.................",
		"..uu.....uxxx.................",
		"..uu.....uxxx.................",
		"..uu.....uxxx.................",
		".........uxxx.................",
		"........wwwwww................",
		"........uuuuuu................",
		"........uuuuuu................",
	],
]
## The fish (D2): a dark back plane over the flank and a light belly, fins as their own
## shapes (n fins, p the pectoral), the eye with a foam highlight; facing left, the mouth on
## column 0. FISH_SHAPES: [the first column of the tail block, the first column of its tip].
const FISH_MACKEREL: Array[String] = [
	"..........nn................",
	".........nnnn.......nn......",
	"......dddddddddddddnnnn.....",
	"...ddddddddddddddddddd....nn",
	".dddxWddddddddddddddddd..nn.",
	"ccccccccccccccccccccccccnn..",
	".bbbbbbpppbbbbbbbbbbbbb.nn..",
	"...bbbbbppbbbbbbbbbbbb...nn.",
	"......bbbbbbbbbbbbb.......nn",
	"............nnn.............",
]
const FISH_SEA_BREAM: Array[String] = [
	".......nnnnn.........",
	".....nnnnnnnnn.......",
	"....dddddddddd.......",
	"..dddddddddddddd..nnn",
	".ddxWddddddddddddnnn.",
	".ddddddddddddddddnn..",
	"cccccccccccccccccn...",
	"cccccccccccccccccnn..",
	".bbbbbpppbbbbbbbbnnn.",
	"..bbbbbppbbbbbbb..nnn",
	"....bbbbbbbbbb.......",
	"......nnnnnn.........",
	"........nnn..........",
]
const FISH_SNAPPER: Array[String] = [
	"........YYYYY.............",
	"......nnnnnnnnn...........",
	".....dddddddddddd.........",
	"...dddddddddddddddd.......",
	"..dddddddddddddddddd...nnn",
	".dddxWddddddddddddddd.nnn.",
	".ddddddddddddddddddddnnn..",
	"cccccccccccccccccccccnn...",
	"cccccccccccccccccccccnn...",
	".bbbbbbppppbbbbbbbbbbnnn..",
	"..bbbbbbpppbbbbbbbbb..nnn.",
	"...bbbbbbbbbbbbbbbb....nnn",
	".....bbbbbbbbbbbb.........",
	".......nnn..nnnn..........",
]
const FISH_MAHI: Array[String] = [
	"...nnnnnnnnnnnnnnnnnn...................",
	"..nnnnnnnnnnnnnnnnnnnnn.................",
	".dddddddddddddddddddddddnn..............",
	".dddddddddddddddddddddddddnn.........nnn",
	".dddxWddddddddddddddddddddddnn.....nnnn.",
	".ddddddddddddddddddddddddddddd...nnnnn..",
	"ccccccccccccccccccccccccccccccccnnnn....",
	"ccccccccccccccccccccccccccccccccnn......",
	"bbbbbbbbppppbbbbbbbbbbbbbbbbbbbbnnnn....",
	".bbbbbbbbpppbbbbbbbbbbbbbbbbbb...nnnnn..",
	".bbbbbbbbbbbbbbbbbbbbbbbbbbbnn.....nnnn.",
	".bbbbbbbbbbbbbbbbbbbbbbbbbnn.........nnn",
	"..bbbbbbbbbbbbbbbbbbbbbbnn..............",
	"........nnnnnnnnnnnnnn..................",
	"..........nnnnnnnnnn....................",
]
const FISH_TUNA: Array[String] = [
	".............nn.........................",
	"............nnnnn....................nn.",
	"..........ddddddddddddd.............nn..",
	"......dddddddddddddddddddddY.......nn...",
	"....ddddddddddddddddddddddddddY...nn....",
	"..ddddxWdddddddddddddddddddddddd.nn.....",
	".ccccccccccccccccccccccccccccccccnn.....",
	"cccccccccccccccccccccccccccccccccc......",
	".bbbbbbbbpppppbbbbbbbbbbbbbbbbbbbnn.....",
	"..bbbbbbbbbpppbbbbbbbbbbbbbbbbbb.nn.....",
	"....bbbbbbbbbbbbbbbbbbbbbbbbbbY...nn....",
	"......bbbbbbbbbbbbbbbbbbbbbY.......nn...",
	"..........bbbbbbbbbbbbb.............nn..",
	"..............nnnnn..................nn.",
	"................nn......................",
]
const FISH_WAHOO: Array[String] = [
	"................................................",
	"............nnnnnnnnnnnnnnnnnnn..............nnn",
	"......ddddddddddddddddddddddddddddd.........nnn.",
	"...ddddddddddddddddddddddddddddddddddd.....nnn..",
	".dddxWdddddddddddddddddddddddddddddddddd..nnn...",
	"cccccccccccccccccccccccccccccccccccccccccnnn....",
	".bbbbbbbppppbbbbbbbbbbbbbbbbbbbbbbbbbbbb..nnn...",
	"...bbbbbbpppbbbbbbbbbbbbbbbbbbbbbbbbbb.....nnn..",
	"......bbbbbbbbbbbbbbbbbbbbbbbbbbbbb.........nnn.",
	"....................nnnnnnn..................nnn",
]
const FISH_SWORDFISH: Array[String] = [
	"......................nnnn..............................nnn.",
	".....................nnnnnnn...........................nnn..",
	"....................nnnnnnnnnn........................nnn...",
	".................dddddddddddddddddddddddd............nnn....",
	"..............ddddddddddddddddddddddddddddddd......nnnn.....",
	".............ddddxWdddddddddddddddddddddddddddd..nnnn.......",
	"dddddddddddddcccccccccccccccccccccccccccccccccccnnn.........",
	".............bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb..nnnn.......",
	"..............bbbbbbppppbbbbbbbbbbbbbbbbbbbbb......nnnn.....",
	".................bbbbbpppbbbbbbbbbbbbbbbb............nnn....",
	"..............................nnnn....................nnn...",
	".......................................................nnn..",
	"........................................................nnn.",
]
const FISH_MARLIN: Array[String] = [
	"......................nnnnn...........................................",
	".....................nnnnnnnnnn.......................................",
	"....................nnnnnnnnnnnnnnn...............................nnn.",
	"...................nnnnnnnnnnnnnnnnnnnn..........................nnn..",
	"..................nnnnnnnnnnnnnnnnnnnnnnn......................nnnn...",
	"..................ddddddddddddddddddddddddddd................nnnn.....",
	"................ddddddddddddddddddddddddddddddddd..........nnnn.......",
	"...............dddddddddddddddddddddddddddddddddddd......nnnn.........",
	"..............ddddxWddddddddddddddddddddddddddddddddd..nnnn...........",
	"ddddddddddddddccccccccccccccccccccccccccccccccccccccccnnn.............",
	"..............bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb..nnnn...........",
	"...............bbbbbbbpppppbbbbbbbbbbbbbbbbbbbbbbbb......nnnn.........",
	".................bbbbbbbppppbbbbbbbbbbbbbbbbbbb............nnnn.......",
	"....................bbbbbbbbbbbbbbbbbbbbb....................nnnn.....",
	"....................................nnnnn......................nnnn...",
	".....................................nnn.........................nnn..",
	"..................................................................nnn.",
]
const FISH_GROUPER: Array[String] = [
	".................nnnnnnnnnnnnnnnnn........................",
	"..............nnnnnnnnnnnnnnnnnnnnnnn.....................",
	"..........ddddddddddddddddddddddddddddd...................",
	".......dddddddddddddddddddddddddddddddddd.................",
	".....dddddddddddddddddddddddddddddddddddddd...............",
	"...dddddddddddddddddddddddddddddddddddddddddd......nnnnn..",
	"..dddddddddddddddddddddddddddddddddddddddddddd....nnnnnnn.",
	".dddddddddddddddddddddddddddddddddddddddddddddd..nnnnnnnnn",
	".ccccccxWcccccccccccccccccccccccccccccccccccccccnnnnnnnnnn",
	".ccccccxxcccccccccccccccccccccccccccccccccccccccnnnnnnnnnn",
	".cccccccccccccccccccccccccccccccccccccccccccccccnnnnnnnnnn",
	"dddddcccccccccccccccccccccccccccccccccccccccccccnnnnnnnnnn",
	"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbnnnnnnnnnn",
	"bbbbbbbbbbbbpppppbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbnnnnnnnnnn",
	".bbbbbbbbbbbbppppbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbnnnnnnnnnn",
	".bbbbbbbbbbbbbpppbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb..nnnnnnnnn",
	"..bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb....nnnnnnn.",
	"...bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb......nnnnn..",
	".....bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...............",
	".......bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.................",
	"..........bbbbbbbbbbbbbbbbbbbbbbbbbbbb....................",
	"............nnnn........nnnnnnnnnnn.......................",
	".............nnn..........nnnnnnn.........................",
	"..............nn..........................................",
	"..........................................................",
]
const FISH_OARFISH: Array[String] = [
	"...YYYY.............................................................................",
	"....YYYYYYYYYnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn.....",
	"...ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd....",
	".ddxWddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd..",
	"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
	".bbbbbpppbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb..",
	"...bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb....",
	".......nnn..........................................................................",
]
const FISH_SHAPES := {
	"fish_mackerel": [23, 25],
	"fish_sea_bream": [17, 19],
	"fish_snapper": [21, 23],
	"fish_mahi": [32, 35],
	"fish_tuna": [33, 35],
	"fish_wahoo": [41, 44],
	"fish_swordfish": [48, 53],
	"fish_marlin": [54, 61],
	"fish_grouper": [48, 52],
	"fish_oarfish": [74, 80],
}
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

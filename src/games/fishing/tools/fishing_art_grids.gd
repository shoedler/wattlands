class_name FishingArtGrids
extends RefCounted
## Turbo Reel's hand-authored pixel art: every sprite as a palette-indexed text grid (one
## character per FishingPalette colour, LEGEND; '.' is transparent) plus the few frames derived
## in code (fish swim waves, flywheel spokes, the cards composed from other sprites).
## tools/fishing_write_sprites.gd writes build() to assets/fishing/sprites/<id>.png (frames side
## by side) and sprites.json; the view only loads the PNGs (FishingSprites). Boat parts are
## drawn to FishingRig's points.

const LEGEND := {
	"W": FishingPalette.CLOUD,
	"2": FishingPalette.SKY_2,
	"1": FishingPalette.SKY_1,
	"0": FishingPalette.SKY_0,
	"h": FishingPalette.HAZE_1,
	"H": FishingPalette.HAZE_2,
	"a": FishingPalette.SEA_1,
	"b": FishingPalette.SEA_2,
	"c": FishingPalette.SEA_3,
	"d": FishingPalette.SEA_4,
	"e": FishingPalette.SEA_5,
	"f": FishingPalette.SEA_6,
	"g": FishingPalette.SEA_7,
	"x": FishingPalette.VOID,
	"s": FishingPalette.SAND_1,
	"S": FishingPalette.SAND_2,
	"w": FishingPalette.WOOD_1,
	"v": FishingPalette.WOOD_2,
	"u": FishingPalette.WOOD_3,
	"q": FishingPalette.CREAM,
	"Y": FishingPalette.BRASS_1,
	"y": FishingPalette.BRASS_2,
	"n": FishingPalette.BRASS_3,
	"R": FishingPalette.KEY_LIGHT,
	"r": FishingPalette.KEY_DARK,
	"k": FishingPalette.SKIN_1,
	"K": FishingPalette.SKIN_2,
	"t": FishingPalette.STEEL,
	"N": FishingPalette.NAVY,
	"B": FishingPalette.BLUE,
	"G": FishingPalette.GREEN,
	"L": FishingPalette.GLOW,
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
## Swim frames per fish and how far the tail (or, for ribbons, the whole body) sways.
const SWIM_FRAMES := 4
const SWIM_AMP := {"fish_marlin": 2, "fish_oarfish": 2}
## Fish whose whole body ripples (a travelling wave) instead of a tail beat.
const RIBBON: Array[String] = ["fish_wahoo", "fish_oarfish"]
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

const FLYWHEEL_RING: Array[String] = [
	"...yYy...",
	".yY...yy.",
	".Y.....y.",
	"Y.......n",
	"y.......n",
	"y.......n",
	".y.....n.",
	".nn...nn.",
	"...nnn...",
]
const GEARS: Array = [
	[".y.y..", "yyYyYy", ".YuYnY", "yyyy.n"],
	["y.y...", ".yYyyY", "yYuYYn", ".y.y.n"],
]
const WINCH: Array[String] = ["nYYn", ".WW.", ".qq.", ".WW.", "nyyn"]
const PROP: Array = [
	[".Y.", ".y.", ".y.", "nun", ".n.", "...", "..."],
	["...", ".Y.", ".y.", "nun", ".n.", ".n.", "..."],
	["...", "...", ".Y.", "nun", ".y.", ".n.", ".n."],
	["...", ".Y.", ".y.", "nun", ".y.", ".n.", "..."],
]
const RIDER: Array[String] = [
	"..rRR..",
	".rRRRRr",
	".uukk..",
	".ukuk..",
	"..kk...",
	".RRRR..",
	".RRRR..",
	".rRRR..",
	".rRRR..",
	".rrRR..",
	".uuuu..",
]
## The diving wobbler: lip, painted body, a glint; two wobble frames.
const LURE: Array = [
	["..RYYy.", "WRxYYyn", ".W.nn.."],
	["..RYYn.", "WRxYyyn", "W..nn.."],
]
const GULL: Array = [
	["W...W", ".WtW.", "..t.."],
	[".....", "WWtWW", "..t.."],
]
const SPLASH: Array = [
	[
		"...........",
		"...........",
		"...........",
		"...W.W.....",
		"....WWW....",
		"..WWWWWWW..",
		".WaWWWWWaW.",
	],
	[
		"...........",
		"....W......",
		"..W...W.W..",
		"....W.W....",
		"...W...W...",
		"..aW...Wa..",
		".a.......a.",
	],
	[
		"...W.......",
		".......W...",
		"..W........",
		"........W..",
		"...........",
		"...........",
		"..a.....a..",
	],
]
const SPARKLE: Array = [
	["...Y...", "...Y...", "YYYWYYY", "...Y...", "...Y..."],
	["Y.....Y", ".Y...Y.", "...W...", ".Y...Y.", "Y.....Y"],
	["...y...", ".......", "y..Y..y", ".......", "...y..."],
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
			"WW.........",
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
			".WW........",
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
## Card size (the game's picker card and the Free Roam and workout cards).
const CARD := Vector2i(160, 90)


## Every sprite: {id: {"frames": Array[Image], "anchor": Vector2i, "desc": String}}.
static func build() -> Dictionary:
	var out := {}
	_add(out, "boat_hull", [img(BOAT_HULL)], Vector2i.ZERO, "pedal boat hull, brass long-tail")
	var fly: Array[Image] = []
	for k in 4:
		fly.append(flywheel(k))
	_add(out, "boat_flywheel", fly, Vector2i(4, 4), "brass flywheel, three spokes")
	_add(out, "boat_gears", frames_of(GEARS), Vector2i.ZERO, "gear train in the gearbox")
	var winch: Array[Image] = []
	for k in 2:
		winch.append(winch_frame(k))
	_add(out, "boat_winch", winch, Vector2i(2, 2), "winch drum with wound line")
	_add(out, "boat_prop", frames_of(PROP), Vector2i(1, 3), "exposed screw propeller")
	_add(out, "rider", [img(RIDER)], Vector2i.ZERO, "seated rider in the key reds")
	_add(out, "lure", frames_of(LURE), Vector2i(3, 1), "diving wobbler lure")
	_add(out, "gull", frames_of(GULL), Vector2i(2, 1), "gull, two wingbeats")
	_add(out, "fx_splash", frames_of(SPLASH), Vector2i(5, 6), "splash")
	_add(out, "fx_sparkle", frames_of(SPARKLE), Vector2i(3, 2), "catch sparkle")
	for id: String in FISH:
		var base := img(fish_grid(id))
		var amp := int(SWIM_AMP.get(id, 1))
		var frames: Array[Image] = []
		for k in SWIM_FRAMES:
			frames.append(swim(base, k, amp, RIBBON.has(id)))
		var a := Vector2i(0, frames[0].get_height() / 2)
		_add(out, id, frames, a, "fish facing left, mouth at the anchor")
	for id: String in ICONS:
		_add(out, id, frames_of(ICON_GRIDS[id]), Vector2i(5, 4), "action icon")
	_add(
		out,
		"scenery_town",
		[img(hjoin(SCENERY_TOWN_L, SCENERY_TOWN_R))],
		Vector2i(0, 33),
		"harbour town in the haze"
	)
	_add(out, "scenery_pier", [img(SCENERY_PIER)], Vector2i(0, 8), "wooden pier, deck on row 8")
	_add(out, "picker_card", [card(0)], Vector2i.ZERO, "the game's picker card")
	_add(out, "card_roam", [card(1)], Vector2i.ZERO, "Free Roam card")
	_add(out, "card_workout", [card(2)], Vector2i.ZERO, "workout card")
	return out


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


static func frames_of(grids: Array) -> Array[Image]:
	var out: Array[Image] = []
	for g: Array in grids:
		out.append(img(g))
	return out


## Flywheel frame k (0..3): the ring with three spokes turned k x 30 degrees.
static func flywheel(k: int) -> Image:
	var out := img(FLYWHEEL_RING)
	for s in 3:
		var a := deg_to_rad(float(k * 30 + s * 120 - 90))
		var tip := Vector2i(4 + roundi(cos(a) * 3.0), 4 + roundi(sin(a) * 3.0))
		plot_line(out, Vector2i(4, 4), tip, FishingPalette.BRASS_3)
	out.set_pixel(4, 4, FishingPalette.WOOD_3)
	return out


## Winch frame k (0..1): the wound line's light and shade rows swap as the drum turns.
static func winch_frame(k: int) -> Image:
	var out := img(WINCH)
	for y: int in [1, 2, 3]:
		var c := FishingPalette.CREAM if (y + k) % 2 == 1 else FishingPalette.CLOUD
		out.set_pixel(1, y, c)
		out.set_pixel(2, y, c)
	return out


## Swim frame k of a left-facing fish: columns shift up or down by a tail beat that grows toward
## the tail (or, for a ribbon, a wave travelling down the whole body). The frame gains `amp` rows
## top and bottom so nothing is clipped.
static func swim(base: Image, k: int, amp: int, ribbon: bool) -> Image:
	var w := base.get_width()
	var h := base.get_height()
	var out := Image.create_empty(w, h + 2 * amp, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var phase := TAU * float(k) / float(SWIM_FRAMES)
	for x in w:
		var u := float(x) / float(maxi(w - 1, 1))
		var off := 0.0
		if ribbon:
			off = sin(phase - u * TAU * 1.5) * (0.35 + 0.65 * u)
		else:
			off = sin(phase) * clampf((u - 0.55) / 0.45, 0.0, 1.0)
		var dy := roundi(off * float(amp))
		for y in h:
			var c := base.get_pixel(x, y)
			if c.a > 0.5:
				out.set_pixel(x, y + amp + dy, c)
	return out


## A 1 px line in `c`.
static func plot_line(target: Image, a: Vector2i, b: Vector2i, c: Color) -> void:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in n + 1:
		var t := float(i) / float(maxi(n, 1))
		var p := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		if Rect2i(Vector2i.ZERO, target.get_size()).has_point(p):
			target.set_pixel(p.x, p.y, c)


## `src` drawn onto `dst` at `at` (opaque pixels only).
static func blit(dst: Image, src: Image, at: Vector2i) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			var p := at + Vector2i(x, y)
			if c.a > 0.5 and Rect2i(Vector2i.ZERO, dst.get_size()).has_point(p):
				dst.set_pixel(p.x, p.y, c)


## The assembled boat (hull, parts, rider, legs, rod) as one image: `fishing` false drives
## (clutch forward, rod stowed, hand on the tiller), true fishes. Cards and previews use it.
static func boat(fishing: bool, k: int = 0) -> Image:
	var out := img(BOAT_HULL)
	blit(out, flywheel(k % 4), Vector2i(FishingRig.FLYWHEEL_AT))
	blit(out, img(GEARS[k % 2]), Vector2i(FishingRig.GEARS_AT))
	blit(out, winch_frame(k % 2 if fishing else 0), Vector2i(FishingRig.WINCH_AT))
	blit(out, img(PROP[0 if fishing else k % 4]), Vector2i(FishingRig.PROP_AT))
	var p := FishingRig.pedals(float(k) * PI / 4.0)
	_leg(out, FishingRig.leg(FishingRig.HIP, p[1]), FishingPalette.WOOD_2, FishingPalette.SKIN_2)
	blit(out, img(RIDER), Vector2i(FishingRig.RIDER_AT))
	_leg(out, FishingRig.leg(FishingRig.HIP, p[0]), FishingPalette.WOOD_3, FishingPalette.SKIN_1)
	var hand := FishingRig.BRAKE_KNOB if fishing else FishingRig.TILLER_GRIP
	var a := FishingRig.arm(hand)
	plot_line(out, Vector2i(a[0]), Vector2i(a[1]), FishingPalette.SKIN_1)
	plot_line(out, Vector2i(a[1]), Vector2i(a[2]), FishingPalette.SKIN_1)
	var tip := FishingRig.clutch_tip(1.0 if fishing else 0.0)
	plot_line(out, Vector2i(FishingRig.CLUTCH_PIVOT), Vector2i(tip), FishingPalette.WOOD_3)
	var rod := FishingRig.rod(1.0 if fishing else 0.0, 0.0, Vector2.DOWN)
	for i in rod.size() - 1:
		plot_line(out, Vector2i(rod[i]), Vector2i(rod[i + 1]), FishingPalette.WOOD_2)
	return out


static func _leg(out: Image, pts: PackedVector2Array, thigh: Color, shin: Color) -> void:
	plot_line(out, Vector2i(pts[0]), Vector2i(pts[1]), thigh)
	plot_line(out, Vector2i(pts[1]), Vector2i(pts[2]), shin)


## Card `kind` (0 the game's picker card, 1 Free Roam, 2 workout): flat sky and sea bands, the
## haze town, the boat and a fish, composed from the sprites above.
static func card(kind: int) -> Image:
	var out := Image.create_empty(CARD.x, CARD.y, false, Image.FORMAT_RGBA8)
	var surf := 46
	var bands: Array[Color] = [FishingPalette.SKY_0, FishingPalette.SKY_1, FishingPalette.SKY_2]
	for i in 3:
		out.fill_rect(Rect2i(0, i * surf / 3, CARD.x, surf / 3 + 1), bands[i])
	if kind != 2:
		blit(
			out,
			img(hjoin(SCENERY_TOWN_L, SCENERY_TOWN_R)),
			Vector2i(-40 if kind == 0 else -70, surf - 33)
		)
	for i in FishingPalette.SEA.size():
		var y0 := surf + roundi(pow(float(i) / 8.0, 1.4) * float(CARD.y - surf))
		out.fill_rect(Rect2i(0, y0, CARD.x, CARD.y - y0), FishingPalette.SEA[i])
	out.fill_rect(Rect2i(0, surf, CARD.x, 1), FishingPalette.CLOUD)
	var fish := "fish_marlin" if kind == 0 else ("fish_grouper" if kind == 1 else "fish_tuna")
	var fimg := swim(img(fish_grid(fish)), 1, 1, false)
	var fat := Vector2i(78, 62) if kind != 1 else Vector2i(96, 56)
	blit(out, fimg, fat)
	var b := boat(kind != 1, 1)
	var bat := Vector2i(10 if kind != 1 else 40, surf - FishingRig.WATERLINE)
	blit(out, b, bat)
	if kind != 1:
		var tip := Vector2i(FishingRig.rod(1.0, 0.0, Vector2.DOWN)[-1]) + bat
		plot_line(out, tip, fat + Vector2i(0, fimg.get_height() / 2), FishingPalette.CLOUD)
	else:
		for i in 22:
			if i % 4 != 3:
				out.set_pixel(bat.x + 4 - i, surf + (i / 8), FishingPalette.CLOUD)
	return out


const BOAT_HULL: Array[String] = [
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
	"..................................uu............................................................",
	".......................Y..........y.............................................................",
	".......................n..........y...uuuv......................................................",
	".............................n...y......n.......................................................",
	".............................n...y......n.......................................................",
	".........................nYyyyyyny......n.......................................................",
	".........................yuuuuuuny......n...................................................uu..",
	".........................yuuuuuuy...vu..n..............................................u..uuuu..",
	".....................nn..yuuuuuuy..v....n............................................uuuuuRRRR..",
	".....................u...yuuuuuunvv.....n.....n................................uuuuuuRRRRRWWW...",
	".........................nyyyyyyv.......n.....n........................uuuuuuuuRRRRRRWWWWWWWW...",
	".........................nu....u........n....nnn.............uuuuuuuuuuRRRRRRRRWWWWWWWWWWWWWW...",
	".......................nvuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuRRRRRRRRRRWWWWWWWWWWWWWWqWWWWWW....",
	".....................nnuvRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRWWWWWWWWWWWWWWWWWWqqqqqqWWWWWWW....",
	"....................n.uuvWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWqqqqqqqqWWWWWWWWWWWW.....",
	"..................nnuuu.vWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWqqqqqqqqqqWWWWWWWWWWWWWWWWWWWW.....",
	".................nuuu...vWqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqWWWWWWWWWWWWWWWWWWWWWWWWWWWWW......",
	"...............nnuu.....vWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW.......",
	"..............nuuu......vqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq.......",
	"............nuuu........vqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq.........",
	"..........nnuu...........eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee...........",
	".........nuuu............eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee..............",
	".........uu...............eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee..................",
	"................................................................................................",
	"................................................................................................",
	"................................................................................................",
	"................................................................................................",
	"................................................................................................",
	"................................................................................................",
]

const FISH_MACKEREL: Array[String] = [
	"...ededede.....",
	".edededededd..e",
	"dxtccccccccdeee",
	".1W111111111.ee",
	"...11WW11.....e",
]

const FISH_SEA_BREAM: Array[String] = [
	"....qqqqq.....",
	"..qqKqKqqq...q",
	".qq1q1q1q1qqqq",
	"qx111111111q.q",
	".11W1W1W111qq.",
	"..1WWWWW11..qq",
	"....1111......",
]

const FISH_SNAPPER: Array[String] = [
	".....rrrr.........",
	"...rrRRRRrrr......",
	"..rRRRRRRRRRrr..rr",
	".rRxRRRRRRRRRRrrrr",
	"rRRRRKRRRRRRRRRrr.",
	".KRkkkkkkkkRRRrrrr",
	"..kkkkkkkkkkkr..rr",
	"....kk..kkk.......",
]

const FISH_MAHI: Array[String] = [
	"....bbbbbbbbbbbbbbbb........",
	"..bGGGGGGGGGGGGGGGGGbb......",
	".GGGGGGGGGGGGGGGGGGGGGb...bb",
	"GGxGGGGGGGGGGGGGGGGGGGGb.bbG",
	"GGGGYGGYGGYGGYGGYGGGGGGGbbG.",
	"GGYYYYYYYYYYYYYYYYYYYGGGGGG.",
	".YYYYYYYYYYYYYYYYYYYYYG.bbGG",
	"..YYYYYYYYYYYYYYYYYYY....bbG",
	"....YYYY..YYYYYY..........bb",
]

const FISH_TUNA: Array[String] = [
	".........Y....................",
	".......NNYNNNNNN...........NN.",
	"....NNNNNNNNNNNNNNNNN.Y.Y.NNN.",
	"..NNNNNNNNNNNNNNNNNNNNNNNNNN..",
	".NxNNNNNNNNNNNNNNNNNNNNNNNNN..",
	"NNBBBBBBBBBBBBBBBBBBBBBBNNNN..",
	".WWWYYYYYYYYYYYYYYYBBBBNNNNN..",
	"..WWWWWWWWWWWWWWWW1111..NNN...",
	"....WWWWWWWWWWWWW1..Y.Y.NNNN..",
	".......WWWWWWW....Y.......NN..",
]

const FISH_WAHOO: Array[String] = [
	".......NN.....................NN..",
	"..NNNNNNNNNNNNNNNNNNNNNNNNNNN.NNN.",
	"NNNBNNBNNNBNNNBNNNBNNNBNNNBNNNNN..",
	"NxBBBNBBBNBBBNBBBNBBBNBBBNBBBNNN..",
	".WWWWWWWWWWWWWWWWWWWWWWWWWWWW.NNN.",
	"...WWWWWWW.....WWW..WW.W.W.W...NN.",
]

const FISH_SWORDFISH: Array[String] = [
	"....................ff........................",
	"...................ffff.......................",
	"..................fffff.......................",
	".................ffffff..................ff...",
	"...........ffffffffffffffffffff.........fff...",
	".........fffffffffffffffffffffffff....ffff....",
	"tttttttttfxffffffffffffffffffffffffffffff.....",
	".........fcccccccccccccccccccccccccccfffff....",
	"..........hhhhhhhhhhhhhhhhhhhhhhhhhh...fff....",
	"...........hhhhhhhhhhhhhhhhhhhhh.........ff...",
	".............hhhhhh..hh.....h.................",
]

const FISH_MARLIN: Array[String] = [
	"......................NN...................................",
	".....................NNNN..................................",
	"....................NNNNNN.................................",
	"..................NNNNNNNNNN...............................",
	"................NNNNNNNNNNNNNN.............................",
	"..............NNNNNNNNNNNNNNNNNNN.......................NN.",
	"............NNNNNNNNNNNNNNNNNNNNNNNN...................NNN.",
	"..........NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN.........NNNN..",
	"tttttttttNxNNBNNNBNNNBNNNBNNNBNNNBNNNBNNNNNNNNNNNNNNNNNN...",
	".........NNNNBNNNBNNNBNNNBNNNBNNNBNNNBNNNNNNNNNNNNNNNNN....",
	"..........BWWBWWWBWWWBWWWBWWWBWWWBWWWBWNNNN.......NNNNN....",
	"............WWWWWWWWWWWWWWWWWWWWWWWWWW..............NNNN...",
	"..............WWWWWNNWWWWWWWWWW..NN..................NNN...",
	"..................N..N............N....................NN..",
]

const FISH_GROUPER: Array[String] = [
	"..................uuu.u.uuu...................",
	".............uuvvvvvvvvvvvvvvuu...............",
	"..........uuvvvwvvvvvwvvvvvvvvvvu.............",
	".........uvvvvvvvvvvvvvvvvwvvvvvvvu.......uuu.",
	".......uvvvwvvvvvvwvvvvvvvvvvvvwvvvu....uuvvu.",
	"......uvvvvvvvvvvvvvvvvvvwvvvvvvvvvvu..uvvvvu.",
	".....uvvvvvwvvvvvvvvwvvvvvvvvvvwvvvvvuuvvvvvu.",
	"....uvvxvvvvvvvvwvvvvvvvvvwvvvvvvvvvvvvvvvvvu.",
	"...uvvvvvvvvwvvvvvvvvwvvvvvvvvwvvvvvvvvvvvvvu.",
	"..uvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvu.",
	".uvvvvvvwvvvvvvvvvwvvvvvvvwvvvvvvvvvvvvwvvvvu.",
	"uuuuuvvvvvvvvwvvvvvvvvvvvvvvvvvwvvvvvvvvvvvvu.",
	"uKKKuvvvvvvvvvvvvvvvvvwvvvvvvvvvvvvvvvvvvvvvu.",
	"uuuuwvvvvvvwvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvu.",
	".uwwwwvvvvvvvvvvvvvvwvvvvvvvvvvvvvvvvuuvvvvvu.",
	"..uwwwwwwvvvvvvvvvvvvvvvvvvvvwvvvvvvu..uvvvvu.",
	"...uwwwwwwwwwvvvvvvvvvvvvvvvvvvvvvvu....uuvvu.",
	".....uwwwwwwwwwwwwwwvvvvvvvvvvvvvvu.......uuu.",
	".......uuwwwwwwwwwwwwwwwwwwvvvvvuu............",
	"..........uuuwwwwwwwwwwwwwwwuuu...............",
	".............uuu..uuu.uuu.....................",
]

const FISH_OARFISH: Array[String] = [
	"..RRR.........................................................",
	".RRRRRR.R...R...R...R...R...R...R...R...R...R...R...R...R.....",
	"RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR..",
	".WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW..",
	"WxW11L1111L1111L1111L1111L1111L1111L1111L1111L1111L1111L1111R.",
	".1111111111111111111111111111111111111111111111111111111111RR.",
	"..R.......................................................RR..",
]

## The town is stored in two halves (line length); hjoin() puts them side by side.
const SCENERY_TOWN_L: Array[String] = [
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	"....................................................................................",
	".........................................HH.........................................",
	".........................................HH.........................................",
	".........................................HH.........................................",
	".........................................HH.........................................",
	".........................................HH.........................................",
	"........................................HHHH........................................",
	"........................................HHHH........................................",
	"........................................HHHH........................................",
	"........................................H00H........................................",
	"........................................HHHH........................................",
	"........................................HHHH............................HH..........",
	"........................................HHHH...........................HHHH.........",
	".........................HH.............HHHH..H............H..........HHHHHH........",
	".............H..........HHHH............HHHH.HHHhhhhhhhhhhHHHhhh......HHHHHH........",
	"....hhhhhhhhHHHhhhhhhhhhHHHH...HH.....HHHHHHHHHHHhhhhhhhhHHHHHhhhhhh..HHHHHH........",
	"hhhhhhHHhhhHHHHHhhhhHhhhHHHHhhHHHHhhhHHHHHHHHHHHHhhhhhhhHHHHHHHhhhHhhhHHHHHH..HH....",
	"hhhhhHHHHhhHHHHHhhhHHHhhH0HHhHHHHHHhHHHHHHHHHHHHHhhhHHhhHHHHHHHhhHHHhhHHHHHH.HHHH..H",
	"hhhhHHHHHHhHHHHHhhHHHHHhHHHHhHHHHHHHHHHHHHHHHHHHHhhHHHHhHHHHHHHhHHHHHhHHHHHH.HHHH.HH",
	"hhhhHHHHHHhH0HHHhHHHHHHHHHHHhHHHHHHHHHHHHHHHHHHHHhHHHHHHH0HHHHHhHHHHHhHHHHHHhHHHH.HH",
	"hhhhHHHHHHhHHHHHhHHHHHHHHHHHhHHHHHHHHHHHHHHHHHHHHhHHHHHHHHHHHHHhHHHHHhHHHHHHhH0HH.HH",
	"hhhhHHH0HHhHHHHHhHHHHHHHHHHHhHHHHHHHHHHHHHHHHHH0HhHHHHHHHHHHHHHhHHH0HhHHHHHHhHHHHhHH",
	"hhhhHHHHHHhHHHHHhH0H0HHHHHHHhHHHHHHHHHHHHHHHHHHHHhHHH0HHHHHHHHHhHHHHHhHHH0HHhHHHHhHH",
	"hhhhHHHHHHhHHHHHhHHHHHHHHHHHhHHHHHHHHHHHHHHHHHHHHhHHHHHHHHHHHHHhHHHHHhHHHHHHhHHHHhHH",
	"hhhhHHHHHHhHHHHHhHHHHHHHHHHHhHHHHHHHHHHHHHHHHHHHHhHHHHHHHHHHHHHhHHHHHhHHHHHHhHHHHhHH",
	"hhhhHHHHHHhHHHHHhHHHHHHHHHHHhHHHHHHHHHHHHHHHHHHHHhHHHHHHHHHHHHHhHHHHHhHHHHHHhHHHHhHH",
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
	"....................HH..............................................................",
	"............HHHHHHHHHHHHHHHHHHHHHHHHHHH.............................................",
	"....................HH..............H...............................................",
	"....................HH..............H...............................................",
	"....................HH..............H...............................................",
	"....................HH..............H................................H..............",
	"....................HH..............H...............................HWH.............",
	"....................HH..............H..............................HHHHH............",
	"....................HH..............H...............................HHH.............",
	"....................HH..............H...............................HHH.............",
	"....................HH.............HHH..............................hhh.............",
	"....................HH..............................................HHH.............",
	"........HH..........HH..............................................HHH.............",
	".H.....HHHH.........HH..............................................HHH.............",
	"HHH...HHHHHH........HH..............................................hhh.............",
	"HHHH..HHHHHH..H.....HH..............................................HHH.............",
	"HHHHH.HHHHHH.HHH....HH..............................................HHH.............",
	"HHHHH.HHHHHHHHHHHHH.HH................hh............................HHH.............",
	"HHHHH.HHHHHHHHHHHHH.HH..HHHHHHHHHHHHHHhh............................hhh.............",
	"HHH0H.HHHHHHHHHHHHH.HH.hHHHHHHHHHHHHHHhhhhhh........................HHH.............",
	"HHHHH.HHHHHHHHHHHHHhHHhhHH0HH0HH0HH0HHhhhhhhhhhh....................HHH.............",
	"HHHHHhHHHHHHHHHHHHHhHHhhHHHHHHHHHHHHHHhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhHHHhhhhhhhhhhhhh",
	"HHHHHhHHHHHHHHHHHHHhHHhhHHHHHHHHHHHHHHhhhhhhhhHHHHHHHHHHHHHHHHHHHHHHHHHHHHhhhhhhhhhh",
	"HHHHHhHHHHHHHHHHHHHhHHhhHHHHHHHHHHHHHHhhHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHhhhhhhhh",
]

const SCENERY_PIER: Array[String] = [
	"...........................................................uuY..........",
	"............................................................uu..........",
	"............................................................u...........",
	"............................................................u...........",
	"....................vvvw....................................u...........",
	"....uvvvvvvvvvvvuvvvvwvvvvvvuvvvvvvvvvvvuvvvvvvvvvvvuvvvvvvvuvvvuvvvvvv.",
	"....u...........u...uuuu....u......uu...u...........u.......u...u.......",
	"....u...........u...........u.....u..u..u...........u.......u...u.......",
	"wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww",
	"vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv",
	"uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu",
	"..uv.......uv.......uv.......uv.......uv.......uv.......uv.......uv.....",
	"..uv.......uv.......uv.......uv.......uv.......uv.......uv.......uv.....",
	"..uvvv.....uvvv.....uvvv.....uvvv.....uvvv.....uvvv.....uvvv.....uv.....",
	"..uv..vv...uv..vv...uv..vv...uv..vv...uv..vv...uv..vv...uv..vv...uv.....",
	"..uv....v..uv....v..uv....v..uv....v..uv....v..uv....v..uv....v..uv.....",
	"..uv.....vvuv.....vvuv.....vvuv.....vvuv.....vvuv.....vvuv.....vvuv.....",
	"..uv.......vv.......vv.......vv.......vv.......vv.......vv.......vv.....",
	"..uv.......uv.......uv.......uv.......uv.......uv.......uv.......uv.....",
	"..uv.......uv.......uv.......uv.......uv.......uv.......uv.......uv.....",
	"..uv.......uv.......uv.......uv.......uv.......uv.......uv.......uv.....",
	"..uv.......uv.......uv.......uv.......uv.......uv.......uv.......uv.....",
]

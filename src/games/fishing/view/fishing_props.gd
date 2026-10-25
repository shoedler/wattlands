class_name FishingProps
extends RefCounted
## The sea floor's props and set pieces, drawn by FishingFloor in art pixels: every shape built
## from flat planes in whole pixels (a lit top, a body, a darker side), its size, proportions and
## facing taken from a seed, so no two on a screen are the same stamp. Colours come from the
## water band's legend (FishingFloor.legend()): f floor, r rim (lit), d dark (side planes), w the
## water, ps/pb plant stem and blade (two and one steps darker than the water), b bone, c coral
## (sage on the reef, else the blade colour), s slate, o wood, a accent, x abyss.

## Each zone's (FishingWorld.ZONES) big pieces and small pieces, picked by seed per cluster.
const BIG: Array = [
	["mooring", "crates", "mooring", "anchor", "mooring", "tyre", "crates"],
	["grass", "boulder", "grass"],
	["brain", "fan", "branch", "fan", "brain"],
	["kelp", "ledge", "kelp"],
	["skeleton", "boulder", "ledge"],
	["basalt", "basalt", "boulder"],
]
const SMALL: Array = [
	["chain", "crate", "tyre", "crate"],
	["shell", "starfish", "ripples", "grass"],
	["anemone", "nub", "shell"],
	["kelp_short", "rock"],
	["rib", "rock"],
	["rock", "column"],
]

## Every kind draw() knows.
const KINDS: Array[String] = [
	"crates",
	"crate",
	"mooring",
	"anchor",
	"chain",
	"tyre",
	"grass",
	"boulder",
	"shell",
	"starfish",
	"ripples",
	"brain",
	"fan",
	"branch",
	"anemone",
	"nub",
	"kelp",
	"kelp_short",
	"ledge",
	"rock",
	"skeleton",
	"rib",
	"basalt",
	"column"
]
## The arch's outline: its height (px) per 4 px column and the opening's height under it.
const ARCH_TOP: Array[float] = [
	14.0, 22.0, 26.0, 30.0, 32.0, 34.0, 36.0, 36.0, 34.0, 36.0, 38.0, 36.0, 32.0, 28.0, 24.0, 16.0
]
const ARCH_HOLE: Array[float] = [
	0.0, 0.0, 0.0, 0.0, 0.0, 14.0, 20.0, 22.0, 22.0, 20.0, 18.0, 12.0, 0.0, 0.0, 0.0, 0.0
]


## Seeded 0..n-1 from `h` shifted by `bit`.
static func pick(h: int, bit: int, n: int) -> int:
	return (h >> bit) % maxi(n, 1)


## Draws prop `kind` standing on the floor row `top`, its left end at `x`, seeded by `h`, at time
## `t` (plants sway), in the band legend `lg`. Returns its width.
static func draw(
	c: CanvasItem, kind: String, x: float, top: float, lg: Dictionary, h: int, t: float
) -> float:
	match kind:
		"crates":
			return crates(c, x, top, lg, h)
		"crate":
			return crate(c, x, top, 6.0 + 2.0 * float(pick(h, 3, 3)), lg)
		"mooring":
			return mooring(c, x, top, lg, h)
		"anchor":
			return anchor(c, x, top, lg, h)
		"chain":
			return chain(c, x, top, lg, h)
		"tyre":
			return tyre(c, x, top, lg)
		"grass":
			return grass(c, x, top, lg, h, t)
		"boulder":
			return boulder(c, x, top, lg, h)
		"shell":
			return shell(c, x, top, lg, h)
		"starfish":
			return starfish(c, x, top, lg)
		"ripples":
			return ripples(c, x, top, lg, h)
		"brain":
			return brain(c, x, top, lg, h)
		"fan":
			return fan(c, x, top, lg, h)
		"branch":
			return branch(c, x, top, lg, h)
		"anemone":
			return anemone(c, x, top, lg, h)
		"nub":
			return brain(c, x, top, lg, h | 0x7, 8.0)
		"kelp":
			return kelp(c, x, top, lg, h, t, 2)
		"kelp_short":
			return kelp(c, x, top, lg, h, t, 1)
		"ledge":
			return ledge(c, x, top, lg, h)
		"rock":
			return rock(c, x, top, lg, h)
		"skeleton":
			return skeleton(c, x, top, lg, h)
		"rib":
			return rib(c, x, top, lg, h)
		"basalt":
			return basalt(c, x, top, lg, h, 3 + pick(h, 2, 3))
		"column":
			return basalt(c, x, top, lg, h, 1)
	return 0.0


## A box seen from the side: lit top rows, the face and a darker side on the right.
static func box(c: CanvasItem, x: float, bottom: float, w: float, h: float, lg: Dictionary) -> void:
	c.draw_rect(Rect2(x, bottom - h, w, h), lg["o"])
	c.draw_rect(Rect2(x + w - 2.0, bottom - h, 2.0, h), lg["s"])
	c.draw_rect(Rect2(x, bottom - h, w, 2.0), lg["r"])


static func crate(c: CanvasItem, x: float, top: float, w: float, lg: Dictionary) -> float:
	box(c, x, top, w, w - 2.0, lg)
	c.draw_rect(Rect2(x, top - floorf((w - 2.0) * 0.5) - 1.0, w - 2.0, 1.0), lg["s"])
	return w


## Two or three crates stacked off-centre.
static func crates(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var w0 := 12.0 + 2.0 * float(pick(h, 2, 3))
	crate(c, x, top, w0, lg)
	var w1 := 8.0 + 2.0 * float(pick(h, 5, 3))
	crate(c, x + w0, top, w1, lg)
	if pick(h, 8, 2) == 0:
		crate(c, x + 2.0 + float(pick(h, 9, 4)), top - (w0 - 2.0), w1, lg)
	return w0 + w1


## A concrete mooring block (three planes) with its ring and a chain rising off it.
static func mooring(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var w := 16.0 + 2.0 * float(pick(h, 3, 3))
	c.draw_rect(Rect2(x, top - 8.0, w, 8.0), lg["d"])
	c.draw_rect(Rect2(x + w - 3.0, top - 8.0, 3.0, 8.0), lg["s"])
	c.draw_rect(Rect2(x, top - 8.0, w, 2.0), lg["r"])
	var rx := x + floorf(w * 0.5) - 3.0
	c.draw_rect(Rect2(rx, top - 12.0, 6.0, 2.0), lg["s"])
	c.draw_rect(Rect2(rx, top - 12.0, 2.0, 4.0), lg["s"])
	c.draw_rect(Rect2(rx + 4.0, top - 12.0, 2.0, 4.0), lg["s"])
	var cy := top - 14.0
	for k in 3 + pick(h, 6, 3):
		c.draw_rect(Rect2(rx + 2.0 + float(k % 2) * 2.0, cy - 3.0, 2.0, 3.0), lg["s"])
		cy -= 4.0
	return w


## A big anchor lying on its crown: shank, stock, ring and two flukes, mirrored by seed.
static func anchor(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var rows: Array[String] = [
		".....sss.....",
		".....s.s.....",
		".....sss.....",
		"..sssssssss..",
		"......s......",
		"......s......",
		"......s......",
		"......s......",
		"......s......",
		"ss....s....ss",
		"sss...s...sss",
		".sss..s..sss.",
		"..sssssssss..",
		"....sssss....",
	]
	if pick(h, 4, 2) == 1:
		rows = [
			"......ss.....",
			".....s..s....",
			"......ss.....",
			"..ssssssssss.",
			"......ss.....",
			"......ss.....",
			"......ss.....",
			"......ss.....",
			"s.....ss.....",
			"ss....ss....s",
			".ss...ss...ss",
			"..sssssssss..",
			"...sssssssss.",
		]
	FishingFloor.stamp(c, rows, x, top - 1.0, lg)
	return 13.0


## A chain lying on the floor: solid 3 x 2 links with a 1 px gap, every other one raised.
static func chain(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var n := 4 + pick(h, 3, 4)
	for k in n:
		c.draw_rect(Rect2(x + float(k * 4), top - 2.0 - float(k % 2), 3.0, 2.0), lg["s"])
	return float(n * 4)


## An old tyre half sunk in the sand.
static func tyre(c: CanvasItem, x: float, top: float, lg: Dictionary) -> float:
	c.draw_rect(Rect2(x + 2.0, top - 6.0, 6.0, 2.0), lg["s"])
	c.draw_rect(Rect2(x, top - 4.0, 2.0, 4.0), lg["s"])
	c.draw_rect(Rect2(x + 8.0, top - 4.0, 2.0, 4.0), lg["s"])
	return 10.0


## A seagrass patch: three to five 2 px blades of seeded heights, swaying whole pixels.
static func grass(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int, t: float) -> float:
	var n := 3 + pick(h, 2, 3)
	for k in n:
		var tall := 8 + 3 * pick(h, 4 + k, 4)
		sway_stem(c, x + float(k * 3), top, tall, lg["ps"], h + k, t, 0)
	return float(n * 3)


## A swaying stem `tall` px from the floor at `top`, 2 px wide in 3-row segments, each leaning a
## whole pixel further with the sway; with `blade_every` > 0 a 2 x 3 blade off it every that many
## segments, on alternating sides, in the blade colour.
static func sway_stem(
	c: CanvasItem,
	x: float,
	top: float,
	tall: int,
	col: Color,
	h: int,
	t: float,
	blade_every: int,
	blade: Color = Color(0, 0, 0, 0)
) -> void:
	var segs := maxi(tall / 3, 1)
	var lean := sin(t * 1.1 + float(h % 17) * 0.37)
	for k in segs:
		var dx := roundf(lean * float(k) / float(segs) * 3.0)
		var y := top - float((k + 1) * 3)
		c.draw_rect(Rect2(x + dx, y, 2.0, 3.0), col)
		if blade_every > 0 and k > 0 and k % blade_every == 0:
			var left := (k / blade_every) % 2 == 0
			c.draw_rect(Rect2(x + dx + (-2.0 if left else 2.0), y, 2.0, 3.0), blade)


## A blocky boulder: two or three tiers stepping in, each with a lit top and a dark right side.
static func boulder(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var w := 14.0 + 2.0 * float(pick(h, 1, 9))
	var y := top
	var tiers := 2 + pick(h, 9, 2)
	for k in tiers:
		var th := 4.0 + 2.0 * float(pick(h, 11 + k, 2))
		var inset := 2.0 * float(k) + 2.0 * float(pick(h, 14 + k, 2) * k)
		var tw := w - 2.0 * inset
		if tw < 4.0:
			break
		c.draw_rect(Rect2(x + inset, y - th, tw, th), lg["f"])
		c.draw_rect(Rect2(x + inset + tw - 2.0, y - th, 2.0, th), lg["d"])
		c.draw_rect(Rect2(x + inset, y - th, tw, 1.0), lg["r"])
		y -= th
	return w


static func rock(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var w := 6.0 + 2.0 * float(pick(h, 2, 3))
	c.draw_rect(Rect2(x, top - 4.0, w, 4.0), lg["f"])
	c.draw_rect(Rect2(x + w - 2.0, top - 4.0, 2.0, 4.0), lg["d"])
	c.draw_rect(Rect2(x + 2.0, top - 6.0, w - 4.0, 2.0), lg["f"])
	c.draw_rect(Rect2(x + 2.0, top - 6.0, w - 4.0, 1.0), lg["r"])
	return w


static func shell(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var mirror := pick(h, 3, 2) == 1
	c.draw_rect(Rect2(x, top - 2.0, 4.0, 2.0), lg["r"])
	c.draw_rect(Rect2(x + (0.0 if mirror else 2.0), top - 3.0, 2.0, 1.0), lg["r"])
	c.draw_rect(Rect2(x + (3.0 if mirror else 0.0), top - 1.0, 1.0, 1.0), lg["d"])
	return 4.0


static func starfish(c: CanvasItem, x: float, top: float, lg: Dictionary) -> float:
	FishingFloor.stamp(c, ["..a..", ".aaa.", "aaaaa", ".a.a."], x, top - 1.0, lg)
	return 5.0


## Sand ripples: short lit dashes in two offset rows on the sand under the rim.
static func ripples(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var n := 3 + pick(h, 2, 3)
	for k in n:
		var w := 4.0 + 2.0 * float(pick(h, 4 + k, 2))
		c.draw_rect(Rect2(x + float(k * 8), top + 4.0 + float(k % 2) * 3.0, w, 1.0), lg["r"])
	return float(n * 8)


## A brain coral: a dome of tiers, lit on top, a groove ring, a dark underside; `size` 0 picks
## a seeded width (14..24 px).
static func brain(
	c: CanvasItem, x: float, top: float, lg: Dictionary, h: int, size: float = 0.0
) -> float:
	var w := size if size > 0.0 else 16.0 + 2.0 * float(pick(h, 2, 6))
	var rows := int(w * 0.7)
	for k in rows:
		var u := float(k) / float(rows)
		var inset := floorf((1.0 - sqrt(1.0 - (1.0 - u) * (1.0 - u))) * w * 0.5)
		var col: Color = lg["c"]
		if k < 2:
			col = lg["r"]
		elif k >= rows - 2:
			col = lg["d"]
		elif k == rows / 2:
			col = lg["pb"]
		c.draw_rect(Rect2(x + inset, top - float(rows - k), w - 2.0 * inset, 1.0), col)
	return w


## A sea fan: a flat fan widening up from a short dark stalk into a rounded top, its top rows
## lit and its lower part darker; seeded width and height, leaning left or right.
static func fan(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var w := 14.0 + 2.0 * float(pick(h, 2, 5))
	var tall := 16 + 2 * pick(h, 5, 7)
	var stalk := 3
	var cx := x + floorf(w * 0.5)
	c.draw_rect(Rect2(cx - 1.0, top - float(stalk), 2.0, float(stalk)), lg["d"])
	var body := tall - stalk
	var lean := 2.0 * float(pick(h, 8, 3) - 1)
	for k in body:
		var u := 1.0 - float(k) / float(body)
		var half := floorf(lerpf(1.0, w * 0.5, minf(u / 0.7, 1.0)))
		if u > 0.85:
			half = floorf(half * (1.0 - (u - 0.85) * 2.5))
		half = maxf(half, 1.0)
		var col: Color = lg["pb"]
		if k < 2:
			col = lg["r"]
		elif u < 0.35:
			col = lg["ps"]
		var y := top - float(stalk) - float(body - k)
		c.draw_rect(Rect2(cx - half + roundf(lean * u), y, 2.0 * half, 1.0), col)
	return w


## A branching coral: a 2 px trunk with blocky branches stepping up and out to lit tips.
static func branch(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var tall := 16 + 2 * pick(h, 2, 8)
	var cx := x + 8.0
	c.draw_rect(Rect2(cx, top - float(tall), 2.0, float(tall)), lg["ps"])
	var n := 3 + pick(h, 6, 2)
	for k in n:
		var at := top - float(4 + k * (tall - 4) / n)
		var left := (k + pick(h, 9, 2)) % 2 == 0
		var reach := 4.0 + 2.0 * float(pick(h, 10 + k, 3))
		var bx := cx - reach if left else cx + 2.0
		c.draw_rect(Rect2(bx, at, reach, 2.0), lg["ps"])
		var tip_x := bx if left else bx + reach - 2.0
		var up := 4.0 + 2.0 * float(pick(h, 13 + k, 3))
		c.draw_rect(Rect2(tip_x, at - up, 2.0, up), lg["ps"])
		c.draw_rect(Rect2(tip_x, at - up, 2.0, 2.0), lg["c"])
	c.draw_rect(Rect2(cx, top - float(tall), 2.0, 2.0), lg["c"])
	return 18.0


## An anemone clump: a few short tentacle tufts on a dark foot, a brass one now and then.
static func anemone(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var col: Color = lg["a"] if pick(h, 3, 4) == 0 else lg["c"]
	c.draw_rect(Rect2(x, top - 2.0, 8.0, 2.0), lg["d"])
	for k in 3:
		var tall := 3.0 + float(pick(h, 5 + k, 3))
		c.draw_rect(Rect2(x + float(k * 3), top - 2.0 - tall, 2.0, tall), col)
	return 8.0


## Kelp: `n` stems of seeded heights (in the dark stem colour), with 2 x 3 blades in the blade
## colour on alternating sides, swaying whole pixels.
static func kelp(
	c: CanvasItem, x: float, top: float, lg: Dictionary, h: int, t: float, n: int
) -> float:
	for k in n:
		var tall := (36 if n > 1 else 14) + 12 * pick(h, 3 + 2 * k, 5)
		sway_stem(c, x + float(k * 8), top, tall, lg["ps"], h + 5 * k, t, 2, lg["pb"])
	return float(n * 8)


## A rocky ledge: a long low slab with a stepped end, lit top, dark front edge.
static func ledge(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var w := 20.0 + 4.0 * float(pick(h, 2, 5))
	c.draw_rect(Rect2(x, top - 4.0, w, 4.0), lg["f"])
	c.draw_rect(Rect2(x + 4.0, top - 8.0, w - 10.0, 4.0), lg["f"])
	c.draw_rect(Rect2(x + 4.0, top - 8.0, w - 10.0, 1.0), lg["r"])
	c.draw_rect(Rect2(x, top - 4.0, 4.0, 1.0), lg["r"])
	c.draw_rect(Rect2(x + w - 6.0, top - 8.0, 2.0, 4.0), lg["d"])
	c.draw_rect(Rect2(x + w - 2.0, top - 4.0, 2.0, 4.0), lg["d"])
	return w


## A whale skeleton (40..60 px): skull block with its eye socket, a spine and ribs falling off
## in height toward the tail, in the bone colour with a lit top row; mirrored by seed.
static func skeleton(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var length := 40.0 + 4.0 * float(pick(h, 2, 6))
	var mirror := pick(h, 6, 2) == 1
	var px := func(u: float, w: float) -> float: return x + (length - u - w if mirror else u)
	c.draw_rect(Rect2(px.call(0.0, 12.0), top - 9.0, 12.0, 9.0), lg["b"])
	c.draw_rect(Rect2(px.call(0.0, 12.0), top - 9.0, 12.0, 1.0), lg["r"])
	c.draw_rect(Rect2(px.call(3.0, 3.0), top - 6.0, 3.0, 2.0), lg["d"])
	c.draw_rect(Rect2(px.call(12.0, length - 12.0), top - 3.0, length - 12.0, 2.0), lg["b"])
	var ribs := int((length - 18.0) / 6.0)
	for k in ribs:
		var rh := roundf(14.0 * (1.0 - float(k) / float(ribs + 1)))
		var u := 16.0 + 6.0 * float(k)
		c.draw_rect(Rect2(px.call(u, 2.0), top - 3.0 - rh, 2.0, rh), lg["b"])
		c.draw_rect(Rect2(px.call(u - 2.0, 4.0), top - 5.0 - rh, 4.0, 2.0), lg["b"])
		c.draw_rect(Rect2(px.call(u - 4.0, 2.0), top - 3.0 - rh, 2.0, 2.0), lg["b"])
	return length


static func rib(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int) -> float:
	var rh := 6.0 + 2.0 * float(pick(h, 2, 3))
	c.draw_rect(Rect2(x, top - rh, 2.0, rh), lg["b"])
	c.draw_rect(Rect2(x + 2.0, top - rh, 3.0, 2.0), lg["b"])
	return 5.0


## Basalt: `n` columns 6..10 px wide of seeded heights, each with a lit top and a dark side.
static func basalt(c: CanvasItem, x: float, top: float, lg: Dictionary, h: int, n: int) -> float:
	var at := x
	for k in n:
		var w := 6.0 + 2.0 * float(pick(h, 3 + 2 * k, 3))
		var tall := 8.0 + 4.0 * float(pick(h, 5 + 3 * k, 5))
		column(c, at, top, w, tall, lg)
		at += w
	return at - x


static func column(
	c: CanvasItem, x: float, bottom: float, w: float, tall: float, lg: Dictionary
) -> void:
	c.draw_rect(Rect2(x, bottom - tall, w, tall), lg["f"])
	c.draw_rect(Rect2(x + w - 2.0, bottom - tall, 2.0, tall), lg["d"])
	c.draw_rect(Rect2(x, bottom - tall, w, 2.0), lg["r"])


## The old wreck lying level, half sunk into the floor at `top`: a long hull with a stepped bow
## and a broken stern, a deckhouse with dark windows, two snapped masts, a gash showing water.
static func wreck(c: CanvasItem, cx: float, top: float, lg: Dictionary) -> void:
	var x := cx - 56.0
	var deck := top - 18.0
	c.draw_rect(Rect2(x, deck, 100.0, 24.0), lg["f"])
	for k in 4:
		var kf := float(k)
		c.draw_rect(
			Rect2(x + 100.0 + 2.0 * kf, deck + 2.0 + 4.0 * kf, 2.0, 22.0 - 4.0 * kf), lg["f"]
		)
	c.draw_rect(Rect2(x - 4.0, deck + 6.0, 4.0, 18.0), lg["f"])
	c.draw_rect(Rect2(x, deck, 100.0, 2.0), lg["r"])
	c.draw_rect(Rect2(x, deck + 10.0, 108.0, 2.0), lg["d"])
	c.draw_rect(Rect2(x + 58.0, deck - 12.0, 24.0, 12.0), lg["f"])
	c.draw_rect(Rect2(x + 79.0, deck - 12.0, 3.0, 12.0), lg["d"])
	c.draw_rect(Rect2(x + 58.0, deck - 12.0, 24.0, 2.0), lg["r"])
	for k in 3:
		c.draw_rect(Rect2(x + 61.0 + 6.0 * float(k), deck - 7.0, 4.0, 3.0), lg["w"])
	c.draw_rect(Rect2(x + 24.0, deck - 30.0, 3.0, 30.0), lg["d"])
	c.draw_rect(Rect2(x + 21.0, deck - 24.0, 9.0, 2.0), lg["d"])
	c.draw_rect(Rect2(x + 88.0, deck - 16.0, 3.0, 16.0), lg["d"])
	c.draw_rect(Rect2(x + 34.0, deck + 4.0, 10.0, 6.0), lg["w"])
	c.draw_rect(Rect2(x + 38.0, deck + 10.0, 4.0, 4.0), lg["w"])
	for k in 5:
		c.draw_rect(Rect2(x + 8.0 + 9.0 * float(k), deck + 4.0, 2.0, 2.0), lg["w"])


## The great reef arch on the floor at `top`: a rock mass with a stepped, irregular outline and
## an opening under it, lit on its top, dark inside the opening and on its right flank, coral
## heads crowning it.
static func arch(c: CanvasItem, cx: float, top: float, lg: Dictionary) -> void:
	var x := cx - 32.0
	for col in 16:
		var u := float(col * 4)
		var height := ARCH_TOP[col]
		c.draw_rect(Rect2(x + u, top - height, 4.0, height), lg["f"])
		c.draw_rect(Rect2(x + u, top - height, 4.0, 2.0), lg["r"])
		var hole := ARCH_HOLE[col]
		if hole > 0.0:
			c.draw_rect(Rect2(x + u, top - hole, 4.0, hole), lg["w"])
			c.draw_rect(Rect2(x + u, top - hole - 2.0, 4.0, 2.0), lg["d"])
	c.draw_rect(Rect2(x + 12.0, top - ARCH_HOLE[4], 2.0, ARCH_HOLE[4]), lg["d"])
	c.draw_rect(Rect2(x + 62.0, top - ARCH_TOP[15], 2.0, ARCH_TOP[15]), lg["d"])
	fan(c, x + 2.0, top - ARCH_TOP[1] + 1.0, lg, 0x1B3)
	brain(c, x + 26.0, top - ARCH_TOP[7] + 1.0, lg, 0x2C5)
	branch(c, x + 44.0, top - ARCH_TOP[12] + 1.0, lg, 0x3D7)
	anemone(c, x + 36.0, top - ARCH_TOP[9] + 1.0, lg, 0x0)


## The whale's bones landmark on the shelf: a big skeleton.
static func bones(c: CanvasItem, cx: float, top: float, lg: Dictionary) -> void:
	skeleton(c, cx - 30.0, top, lg, 0x5A5A)
	skeleton(c, cx + 34.0, top, lg, 0x0A3D)


## The harbour lighthouse on its breakwater, the surface on row `surf`: slate blocks with a
## wood top straddling the surface, a sage tower stepping in as it rises with two brass bands, a
## slate gallery, the foam lamp and a slate roof.
static func lighthouse(c: CanvasItem, cx: float, surf: float) -> void:
	c.draw_rect(Rect2(cx - 22.0, surf - 3.0, 44.0, 6.0), FishingPalette.SLATE)
	c.draw_rect(Rect2(cx - 22.0, surf - 3.0, 44.0, 1.0), FishingPalette.WOOD)
	for k in 3:
		c.draw_rect(Rect2(cx - 18.0 + 14.0 * float(k), surf - 1.0, 2.0, 2.0), FishingPalette.WOOD)
	var y := surf - 3.0
	for k in 3:
		var w := 10.0 - 2.0 * float(k)
		c.draw_rect(Rect2(cx - w * 0.5, y - 10.0, w, 10.0), FishingPalette.SAGE)
		if k < 2:
			c.draw_rect(Rect2(cx - w * 0.5, y - 7.0, w, 3.0), FishingPalette.ACCENT)
		y -= 10.0
	c.draw_rect(Rect2(cx - 6.0, y - 2.0, 12.0, 2.0), FishingPalette.SLATE)
	c.draw_rect(Rect2(cx - 2.0, y - 6.0, 4.0, 4.0), FishingPalette.FOAM)
	c.draw_rect(Rect2(cx - 3.0, y - 6.0, 1.0, 4.0), FishingPalette.SLATE)
	c.draw_rect(Rect2(cx + 2.0, y - 6.0, 1.0, 4.0), FishingPalette.SLATE)
	c.draw_rect(Rect2(cx - 4.0, y - 8.0, 8.0, 2.0), FishingPalette.SLATE)
	c.draw_rect(Rect2(cx - 2.0, y - 10.0, 4.0, 2.0), FishingPalette.SLATE)

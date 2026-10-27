class_name TankDepotDraw
extends RefCounted
## The depot the tank rolls out of (docs/games/tank.md 3.5; the depot segment of a mission), drawn by
## the world layer behind the tank in the warm-lamp language of the tank itself: a yard repeating
## every BLOCK_PX world px along the road's far edge, each block a corrugated hangar with a lit
## doorway (crates and a mechanic inside), a gantry crane with a slung crate, fuel drums (one on its
## side), a barrier post with its red and white arm raised over a sandbag wall and a crewman waving
## the tank through, a hooded lamp post and a stack of planked crates. No text. The light layer lights
## the doorways and the lamps (lights()).

## One yard block (rules px) and where its pieces stand in it.
const BLOCK_PX := 560.0
const AT_HANGAR := 0.0
const AT_GANTRY := 150.0
const AT_DRUMS := 225.0
const AT_BARRIER := 290.0
const AT_LAMP := 380.0
const AT_CRATES := 450.0
## The hangar (art px).
const HANGAR := Vector2(150, 62)
const DOOR := Vector2(40, 38)

const IRON := Color(0.11, 0.105, 0.095)
const RIB := Color(0.17, 0.16, 0.145)
const MOON := Color(0.27, 0.3, 0.29)
const DARK := Color(0.045, 0.04, 0.035)
const INSIDE := Color(0.34, 0.22, 0.11)
const INSIDE_DK := Color(0.16, 0.1, 0.05)
const DRUM := Color(0.15, 0.15, 0.11)
const DRUM_HI := Color(0.27, 0.26, 0.19)
const ARM_RED := Color(0.55, 0.14, 0.09)
const ARM_WHITE := Color(0.66, 0.63, 0.56)
const BAG := Color(0.27, 0.25, 0.19)
const BAG_DK := Color(0.12, 0.11, 0.08)
const PLANK := Color(0.24, 0.17, 0.1)
const PLANK_DK := Color(0.11, 0.075, 0.045)
const LAMP := Color(1.0, 0.68, 0.3)


## The yard blocks on screen: their world x (rules px).
static func blocks(v: TankView) -> Array[float]:
	var out: Array[float] = []
	var first := floorf((v.cam_x - BLOCK_PX) / BLOCK_PX)
	var last := ceilf((v.cam_x + v.canvas.x / TankView.S) / BLOCK_PX)
	for c in range(int(first), int(last) + 1):
		out.append(float(c) * BLOCK_PX)
	return out


static func draw(ci: CanvasItem, v: TankView) -> void:
	var g := TankView.GROUND - 5.0
	for b in blocks(v):
		_hangar(ci, v, roundf(v.sx(b + AT_HANGAR)), g)
		_gantry(ci, roundf(v.sx(b + AT_GANTRY)), g)
		_drums(ci, roundf(v.sx(b + AT_DRUMS)), g)
		_barrier(ci, v, roundf(v.sx(b + AT_BARRIER)), g)
		_lamp_post(ci, roundf(v.sx(b + AT_LAMP)), g)
		_crates(ci, roundf(v.sx(b + AT_CRATES)), g)


## The depot's lights this frame (stage px): [{p, kind}] with kind "lamp" (a hooded lamp) or "door"
## (a hangar's lit doorway, p its middle).
static func lights(v: TankView) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var g := TankView.GROUND - 5.0
	for b in blocks(v):
		var hx := roundf(v.sx(b + AT_HANGAR))
		out.append({"p": Vector2(hx + HANGAR.x * 0.5, g - DOOR.y * 0.5), "kind": "door"})
		out.append({"p": Vector2(hx + HANGAR.x * 0.5, g - DOOR.y - 5.0), "kind": "lamp"})
		out.append({"p": Vector2(roundf(v.sx(b + AT_LAMP)) + 1.0, g - 43.0), "kind": "lamp"})
		out.append({"p": Vector2(roundf(v.sx(b + AT_BARRIER)) + 1.0, g - 25.0), "kind": "lamp"})
	return out


## A corrugated half-round hangar: ribbed iron with a moonlit crest, a lit doorway with crates and a
## mechanic inside, a hooded lamp over the door.
static func _hangar(ci: CanvasItem, v: TankView, x: float, g: float) -> void:
	var w := int(HANGAR.x)
	var half := HANGAR.x * 0.5
	for i in w:
		var u := (float(i) + 0.5 - half) / half
		var hgt := roundf(HANGAR.y * sqrt(maxf(1.0 - u * u, 0.0)))
		if hgt < 1.0:
			continue
		var col := RIB if i % 4 == 0 else IRON
		ci.draw_rect(Rect2(Vector2(x + i, g - hgt), Vector2(1, hgt)), col)
		ci.draw_rect(Rect2(Vector2(x + i, g - hgt), Vector2(1, 1)), MOON if u < 0.4 else RIB)
	# The end wall's doorway, lit from inside.
	var d := Rect2(Vector2(x + half - DOOR.x * 0.5, g - DOOR.y), DOOR)
	ci.draw_rect(d.grow(2), DARK)
	for row in int(DOOR.y):
		var k := float(row) / DOOR.y
		ci.draw_rect(
			Rect2(d.position + Vector2(0, row), Vector2(DOOR.x, 1)), INSIDE_DK.lerp(INSIDE, k)
		)
	ci.draw_rect(Rect2(d.position + Vector2(4, DOOR.y - 12), Vector2(10, 12)), PLANK_DK)
	ci.draw_rect(Rect2(d.position + Vector2(6, DOOR.y - 20), Vector2(7, 8)), PLANK_DK)
	ci.draw_rect(Rect2(d.position + Vector2(DOOR.x - 12, DOOR.y - 8), Vector2(9, 8)), PLANK_DK)
	var crew := {
		"pose": "engineer",
		"at": Vector2(d.position.x + 22.0, g),
		"flip": false,
		"frame": int(v.time * 2.0) % 3,
		"mod": Color(0.45, 0.32, 0.2),
	}
	TankCrew.draw_actor(ci, v.kit, crew, Vector2.ZERO)
	# The lamp's hood over the door.
	ci.draw_rect(Rect2(Vector2(x + half - 5.0, g - DOOR.y - 7.0), Vector2(11, 2)), DARK)
	ci.draw_rect(Rect2(Vector2(x + half - 2.0, g - DOOR.y - 5.0), Vector2(5, 1)), LAMP)


## A gantry crane: two lattice legs, a beam with a moonlit top, a trolley and a crate on a chain.
static func _gantry(ci: CanvasItem, x: float, g: float) -> void:
	var top := g - 58.0
	for lx: float in [x, x + 64.0]:
		ci.draw_rect(Rect2(Vector2(lx, top), Vector2(2, g - top)), IRON)
		ci.draw_rect(Rect2(Vector2(lx + 7.0, top), Vector2(2, g - top)), IRON)
		var y := top + 3.0
		while y < g - 6.0:
			ci.draw_line(Vector2(lx + 1.0, y), Vector2(lx + 8.0, y + 7.0), RIB, 1.0)
			ci.draw_line(Vector2(lx + 8.0, y), Vector2(lx + 1.0, y + 7.0), RIB, 1.0)
			y += 7.0
	ci.draw_rect(Rect2(Vector2(x - 4.0, top - 4.0), Vector2(81, 4)), IRON)
	ci.draw_rect(Rect2(Vector2(x - 4.0, top - 4.0), Vector2(81, 1)), MOON)
	ci.draw_rect(Rect2(Vector2(x + 38.0, top), Vector2(6, 3)), RIB)
	ci.draw_rect(Rect2(Vector2(x + 40.0, top + 3.0), Vector2(1, 24)), RIB)
	_planked(ci, Rect2(Vector2(x + 35.0, top + 27.0), Vector2(12, 9)))


## Fuel drums, banded, one on its side.
static func _drums(ci: CanvasItem, x: float, g: float) -> void:
	for k in 3:
		var dx := x + float(k) * 7.0
		var dh := 10.0 if k != 1 else 11.0
		ci.draw_rect(Rect2(Vector2(dx, g - dh), Vector2(6, dh)), DRUM)
		ci.draw_rect(Rect2(Vector2(dx, g - dh), Vector2(1, dh)), DRUM_HI)
		ci.draw_rect(Rect2(Vector2(dx, g - dh), Vector2(6, 1)), DRUM_HI)
		for by: float in [0.3, 0.7]:
			ci.draw_rect(Rect2(Vector2(dx, roundf(g - dh * by)), Vector2(6, 1)), DARK)
	var lx := x + 22.0
	ci.draw_rect(Rect2(Vector2(lx, g - 6.0), Vector2(10, 6)), DRUM)
	ci.draw_rect(Rect2(Vector2(lx, g - 6.0), Vector2(10, 1)), DRUM_HI)
	for bx: float in [3.0, 7.0]:
		ci.draw_rect(Rect2(Vector2(lx + bx, g - 6.0), Vector2(1, 6)), DARK)
	ci.draw_rect(Rect2(Vector2(lx + 10.0, g - 6.0), Vector2(1, 6)), DRUM_HI.darkened(0.3))


## The gate: a barrier post with its red and white arm raised (painted stripes, no text) and a
## counterweight, a sandbag wall at its foot, a crewman waving the tank through.
static func _barrier(ci: CanvasItem, v: TankView, x: float, g: float) -> void:
	ci.draw_rect(Rect2(Vector2(x, g - 24.0), Vector2(3, 24)), IRON)
	ci.draw_rect(Rect2(Vector2(x, g - 24.0), Vector2(1, 24)), RIB)
	var pivot := Vector2(x + 1.0, g - 22.0)
	var d := Vector2.from_angle(deg_to_rad(-62.0))
	for i in 9:
		var a := pivot + d * float(i) * 5.0
		var b := pivot + d * float(i + 1) * 5.0
		ci.draw_line(a, b, ARM_RED if i % 2 == 0 else ARM_WHITE, 2.0)
	ci.draw_rect(Rect2((pivot - d * 6.0 - Vector2(2, 2)).round(), Vector2(4, 4)), DARK)
	ci.draw_rect(Rect2(Vector2(x - 1.0, g - 26.0), Vector2(5, 2)), DARK)
	for row in 3:
		var y := g - 4.0 - float(row) * 4.0
		var bx := x - 18.0 + float(row % 2) * 3.0
		while bx < x - 2.0 - float(row) * 2.0:
			ci.draw_rect(Rect2(Vector2(bx, y), Vector2(6, 4)), BAG)
			ci.draw_rect(Rect2(Vector2(bx, y), Vector2(6, 1)), BAG.lightened(0.15))
			ci.draw_rect(Rect2(Vector2(bx + 5.0, y), Vector2(1, 4)), BAG_DK)
			bx += 7.0
	var crew := {
		"pose": "spotter",
		"at": Vector2(x + 12.0, g),
		"flip": true,
		"frame": int(v.time * 3.0) % 3,
		"mod": Color(0.55, 0.5, 0.45),
	}
	TankCrew.draw_actor(ci, v.kit, crew, Vector2.ZERO)


static func _lamp_post(ci: CanvasItem, x: float, g: float) -> void:
	ci.draw_rect(Rect2(Vector2(x, g - 44.0), Vector2(2, 44)), IRON)
	ci.draw_rect(Rect2(Vector2(x - 4.0, g - 47.0), Vector2(10, 3)), DARK)
	ci.draw_rect(Rect2(Vector2(x - 2.0, g - 44.0), Vector2(6, 1)), LAMP)


static func _crates(ci: CanvasItem, x: float, g: float) -> void:
	_planked(ci, Rect2(Vector2(x, g - 12.0), Vector2(15, 12)))
	_planked(ci, Rect2(Vector2(x + 15.0, g - 10.0), Vector2(12, 10)))
	_planked(ci, Rect2(Vector2(x + 4.0, g - 21.0), Vector2(11, 9)))


## A planked crate: boards with dark gaps, a lit top edge, dark corner posts.
static func _planked(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, PLANK)
	var y := r.position.y + 3.0
	while y < r.end.y - 1.0:
		ci.draw_rect(Rect2(Vector2(r.position.x, y), Vector2(r.size.x, 1)), PLANK_DK)
		y += 3.0
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), PLANK.lightened(0.25))
	ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), PLANK_DK)
	ci.draw_rect(Rect2(Vector2(r.end.x - 1.0, r.position.y), Vector2(1, r.size.y)), PLANK_DK)

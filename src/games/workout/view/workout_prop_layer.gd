class_name WorkoutPropLayer
extends Node2D
## Props on a parallax plane, in true colour and tinted by the time of day. Buckets along the plane
## pick a kind by hash, so peers agree with no state, nothing tiles and the props can animate; the
## near plane adds chimney smoke on the strip's own houses (kit.props.smoke.chimneys), and the mid
## plane the seeded spots (WorkoutSpots).

var kit: WorkoutKit = null
var factor: float = 0.0
var bucket_px: int = 260
## Kinds by hash; "" is empty ground.
var table: Array[String] = []
var seed_value: int = 0
var chimneys: bool = false
var _scroll: int = 0
var _canvas_w: float = 960.0
var _env_t: float = 0.0
var _rotor: int = 0
var _row: int = 0
var _spots: Array[Dictionary] = []
var _plan_t: float = 0.0


func setup(
	p_kit: WorkoutKit, p_factor: float, p_bucket: int, p_table: Array[String], p_seed: int
) -> WorkoutPropLayer:
	kit = p_kit
	factor = p_factor
	bucket_px = p_bucket
	table = p_table
	seed_value = p_seed
	return self


## A mixed hash: a bare multiply leaves the low bits cycling every 8 buckets, a visible repeat.
static func bucket_hash(k: int, seed_val: int) -> int:
	var h := ((k * 2654435761) ^ seed_val) & 0x7fffffff
	h ^= h >> 15
	h = (h * 2246822519) & 0x7fffffff
	h ^= h >> 13
	return h


## What stands in the buckets the screen covers: [{kind, x (world px on the plane), k, h}].
func entries(view_x0: float, view_x1: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if table.is_empty():
		return out
	var margin := 60.0
	var lo := floori((view_x0 - margin) / float(bucket_px)) - 1
	var hi := floori((view_x1 + margin) / float(bucket_px)) + 1
	for k in range(lo, hi):
		var h := bucket_hash(k, seed_value)
		var kind := table[h % table.size()]
		if kind != "":
			out.append({"kind": kind, "x": k * bucket_px + (h >> 8) % bucket_px, "k": k, "h": h})
	return out


func set_view(
	world_x: float, canvas_w: float, env_t: float, rotor: int, row: int, plan_t: float
) -> void:
	_scroll = roundi(world_x * factor)
	_canvas_w = canvas_w
	_env_t = env_t
	_rotor = rotor
	_row = row
	_plan_t = plan_t
	queue_redraw()


func set_spots(spots: Array[Dictionary]) -> void:
	_spots = spots


func _draw() -> void:
	if kit == null:
		return
	for e in entries(float(_scroll), float(_scroll) + _canvas_w):
		match str(e["kind"]):
			"cattle":
				_cattle(e)
			"windpump":
				_windpump(e)
	if chimneys:
		_smoke()
	for s in WorkoutSpots.active(_spots, _plan_t):
		_spot(s)


func _cattle(e: Dictionary) -> void:
	var p: Dictionary = kit.props["cattle"]
	var c := WorkoutKit.vec(p["cell"])
	var h := int(e["h"])
	var coat := (h >> 4) % int(p.get("colors", 1))
	# Grazing, each on its own beat of the environment clock.
	var frame := floori(_env_t / 2.3 + float(h % 7)) % int(p["frames"])
	var pos := Vector2i(int(e["x"]) - _scroll, int(p["base_y"]) - c.y - (h >> 12) % 10)
	draw_texture_rect_region(
		kit.texture(p["path"]), Rect2(pos, c), Rect2(Vector2i(frame * c.x, coat * c.y), c)
	)


func _windpump(e: Dictionary) -> void:
	var p: Dictionary = kit.props["windpump"]
	var tower: Array = p["tower"]
	var rotor: Array = p["rotor"]
	var tex := kit.texture(p["path"])
	var size := Vector2i(int(tower[2]), int(tower[3]))
	var pos := Vector2i(int(e["x"]) - _scroll, int(p["base_y"]) - size.y)
	draw_texture_rect_region(tex, Rect2(pos, size), Rect2(Vector2i.ZERO, size))
	var rs := Vector2i(int(rotor[2]), int(rotor[3]))
	var hub := pos + WorkoutKit.vec(p["hub"]) - rs / 2
	var frame := _rotor % int(rotor[4])
	draw_texture_rect_region(
		tex, Rect2(hub, rs), Rect2(Vector2i(int(rotor[0]) + frame * rs.x, int(rotor[1])), rs)
	)


## Smoke on the near strip's chimneys, wrapped and scrolled with the strip (same factor, same
## rounding as ParallaxStrip), its origin pixel on the chimney's top pixel.
func _smoke() -> void:
	var p: Dictionary = kit.props["smoke"]
	var strip := kit.plane(str(p["plane"]))
	var tile_w := kit.texture(strip["path"]).get_width()
	var c := WorkoutKit.vec(p["cell"])
	var origin := WorkoutKit.vec(p["origin"])
	var tex := kit.texture(p["path"])
	var index := 0
	for spot: Array in p["chimneys"]:
		var x := posmod(int(spot[0]) - _scroll, tile_w) - tile_w
		var y := int(strip["y"]) + int(spot[1]) - origin.y
		var frame := floori(_env_t * 7.0 + float(index) * 2.0) % int(p["frames"])
		while float(x - origin.x) < _canvas_w:
			draw_texture_rect_region(
				tex, Rect2(Vector2i(x - origin.x, y), c), Rect2(Vector2i(frame * c.x, 0), c)
			)
			x += tile_w
		index += 1


func _spot(s: Dictionary) -> void:
	var x := roundi(float(s["x0"]) + float(s["vx"]) * (_plan_t - float(s["t0"])))
	match str(s["kind"]):
		"flock":
			_flock(s, x)
		"tractor":
			_tractor(x)
		"balloon":
			var p: Dictionary = kit.props["balloon"]
			if _row >= int(p["tod_min_row"]):
				draw_texture(kit.texture(p["path"]), Vector2(x, roundi(float(s["y"]))))


## A loose V, each bird flapping on its own beat.
func _flock(s: Dictionary, x: int) -> void:
	var p: Dictionary = kit.props["flock"]
	var c := WorkoutKit.vec(p["cell"])
	var tex := kit.texture(p["path"])
	var n := int(s["n"])
	var y := roundi(float(s["y"]))
	for i in n:
		var wing := absi(i - floori(float(n) / 2.0))
		var jitter := bucket_hash(i, int(float(s["t0"]))) % 3
		var side := 1 if i % 2 == 0 else -1
		var at := Vector2i(x - wing * 8 + jitter, y + wing * 4 * side + jitter)
		var frame := floori(_env_t * 5.0 + float(i) * 0.7) % int(p["frames"])
		draw_texture_rect_region(tex, Rect2(at, c), Rect2(Vector2i(frame * c.x, 0), c))


func _tractor(x: int) -> void:
	var p: Dictionary = kit.props["tractor"]
	var c := WorkoutKit.vec(p["cell"])
	var frame := floori(_env_t * 6.0) % int(p["frames"])
	var y := int(p["base_y"]) - c.y
	draw_texture_rect_region(
		kit.texture(p["path"]), Rect2(Vector2i(x, y), c), Rect2(Vector2i(frame * c.x, 0), c)
	)
	var dust: Array = kit.data["fx"]["dust"]
	var ds := Vector2i(int(dust[2]), int(dust[3]))
	var df := floori(_env_t * 4.0) % int(dust[4])
	draw_texture_rect_region(
		kit.texture(kit.data["fx"]["path"]),
		Rect2(Vector2i(x - ds.x, y + c.y - ds.y), ds),
		Rect2(Vector2i(int(dust[0]) + df * ds.x, int(dust[1])), ds)
	)

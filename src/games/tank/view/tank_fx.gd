class_name TankFx
extends RefCounted
## The view's particles (docs/games/tank.md 3.5), pooled with caps: smoke (the diesel's exhaust,
## gun smoke, burning wrecks, steam plumes and the smoke screen), muzzle flashes, explosions, sparks,
## brass casings, tracers and dust. Positions are stage px (the canvas without its vertical offset).
## A particle carries `carry` of the world's scroll (0 rides with the tank, 1 stays on the ground).
## Cosmetic randomness comes only from `rng`, seeded from ctx.seed; nothing here feeds the rules.

const MAX_SMOKE := 180
const MAX_FLASHES := 32
const MAX_BOOMS := 24
const MAX_SPARKS := 160
const MAX_CASINGS := 48
const MAX_TRACERS := 48
const MAX_LEAVES := 64
const MAX_WISPS := 90
## A falling leaf: how fast it settles, how wide and how fast it sways.
const LEAF_FALL := 11.0
const LEAF_SWAY := 7.0
const LEAF_SWAY_HZ := 1.3
const GRAVITY := 160.0

var rng := RandomNumberGenerator.new()
## {pos, vel, age, life, r0, r1, a, c, carry}
var smoke: Array[Dictionary] = []
## {pos, r, age, life, color, star, dir}
var flashes: Array[Dictionary] = []
## {pos, r, age, life}
var booms: Array[Dictionary] = []
## {pos, vel, age, life, c, carry, g}
var sparks: Array[Dictionary] = []
## {pos, vel, age, life, ground, carry}
var casings: Array[Dictionary] = []
## {a, b, age, life, c}: a streak running from a to b over its life.
var tracers: Array[Dictionary] = []
## {pos, vel, age, life, len, h, a, c}: a wisp of exhaust streaming off a running vehicle: a thin hard dash that
## stretches and thins; a run of them is a streak, where soft puffs would be a row of dots.
var wisps: Array[Dictionary] = []
## {pos, vel, age, life, c, phase}: a leaf thrown from a bush, fluttering down: a hard pixel or two, no soft blob.
var leaves: Array[Dictionary] = []
## A flash lighting the scene (0..1), where and in what colour.
var wash: float = 0.0
var wash_pos: Vector2 = Vector2.ZERO
var wash_color: Color = Color(1.0, 0.75, 0.45)


func seed_rng(seed_value: int) -> void:
	rng.seed = seed_value
	rng.state = 0


func count() -> int:
	return (
		smoke.size()
		+ flashes.size()
		+ booms.size()
		+ sparks.size()
		+ casings.size()
		+ tracers.size()
		+ leaves.size()
		+ wisps.size()
	)


func clear() -> void:
	smoke.clear()
	flashes.clear()
	booms.clear()
	sparks.clear()
	casings.clear()
	tracers.clear()
	leaves.clear()
	wisps.clear()
	wash = 0.0


# --- Emitters -----------------------------------------------------------------------------------------


## A smoke or steam puff growing from radius radii.x to radii.y over its life.
func puff(
	pos: Vector2,
	vel: Vector2,
	life: float,
	radii: Vector2,
	alpha: float,
	col: Color,
	carry: float = 0.3
) -> void:
	if smoke.size() >= MAX_SMOKE:
		smoke.pop_front()
	smoke.append(
		{
			"pos": pos,
			"vel": vel,
			"age": 0.0,
			"life": life,
			"r0": radii.x,
			"r1": radii.y,
			"a": alpha,
			"c": col,
			"carry": carry
		}
	)


## A flash; with a `dir` it is a muzzle star pointing that way.
func flash(pos: Vector2, r: float, life: float, col: Color, dir: Vector2 = Vector2.ZERO) -> void:
	if flashes.size() >= MAX_FLASHES:
		flashes.pop_front()
	flashes.append(
		{
			"pos": pos,
			"r": r,
			"age": 0.0,
			"life": life,
			"color": col,
			"star": dir != Vector2.ZERO,
			"dir": dir
		}
	)


## Lights the scene for a few frames (a muzzle flash, an explosion).
func light_scene(pos: Vector2, k: float, col: Color) -> void:
	if k >= wash:
		wash = clampf(k, 0.0, 1.0)
		wash_pos = pos
		wash_color = col


func boom(pos: Vector2, r: float, smoke_n: int = 6) -> void:
	if booms.size() >= MAX_BOOMS:
		booms.pop_front()
	booms.append({"pos": pos, "r": r, "age": 0.0, "life": 0.7})
	for i in smoke_n:
		var j := rng.randf()
		puff(
			pos + Vector2(i * 3 - 8, -i),
			Vector2(-4.0 + i * 2.0 + j * 3.0, -12.0 - i * 2.0),
			2.5 + j,
			Vector2(6.0, 26.0),
			0.5,
			Color(0.16, 0.15, 0.14),
			1.0
		)
	spark_burst(pos, int(r * 0.4), Color(1.0, 0.7, 0.3), 70.0, 1.0)


func spark_burst(pos: Vector2, n: int, col: Color, speed: float, carry: float = 1.0) -> void:
	for i in n:
		if sparks.size() >= MAX_SPARKS:
			sparks.pop_front()
		var a := rng.randf_range(-PI * 0.95, -PI * 0.05)
		var v := Vector2(cos(a), sin(a)) * speed * rng.randf_range(0.4, 1.0)
		sparks.append(
			{
				"pos": pos,
				"vel": v,
				"age": 0.0,
				"life": rng.randf_range(0.25, 0.6),
				"c": col,
				"carry": carry,
				"g": GRAVITY
			}
		)


## A spent brass case thrown from `pos`, tumbling to the ground at stage y `ground`.
func casing(pos: Vector2, ground: float) -> void:
	if casings.size() >= MAX_CASINGS:
		casings.pop_front()
	casings.append(
		{
			"pos": pos,
			"vel": Vector2(rng.randf_range(-30.0, -10.0), rng.randf_range(-45.0, -20.0)),
			"age": 0.0,
			"life": 1.4,
			"ground": ground,
			"carry": 0.0
		}
	)


## A wisp from `pos` at `vel`, up to `length` px long.
func wisp(pos: Vector2, vel: Vector2, life: float, length: float, a: float, col: Color) -> void:
	if wisps.size() >= MAX_WISPS:
		wisps.pop_front()
	wisps.append(
		{
			"pos": pos,
			"vel": vel,
			"age": 0.0,
			"life": life,
			"len": length,
			"h": 2.0 if rng.randf() < 0.35 else 1.0,
			"a": a,
			"c": col
		}
	)


## A leaf thrown from `pos` at `vel`, fluttering down for `life` s.
func leaf(pos: Vector2, vel: Vector2, life: float, col: Color) -> void:
	if leaves.size() >= MAX_LEAVES:
		leaves.pop_front()
	leaves.append(
		{"pos": pos, "vel": vel, "age": 0.0, "life": life, "c": col, "phase": rng.randf() * TAU}
	)


func tracer(a: Vector2, b: Vector2, col: Color, life: float) -> void:
	if tracers.size() >= MAX_TRACERS:
		tracers.pop_front()
	tracers.append({"a": a, "b": b, "age": 0.0, "life": life, "c": col})


# --- Step and draw ---------------------------------------------------------------------------------------


## Advances every particle by `dt`; the world scrolled `scroll` art px left this frame.
func step(dt: float, scroll: float) -> void:
	wash = maxf(wash - dt * 7.0, 0.0)
	var keep: Array[Dictionary] = []
	for p in smoke:
		p["age"] = float(p["age"]) + dt
		var v: Vector2 = p["vel"]
		p["pos"] = (p["pos"] as Vector2) + v * dt - Vector2(scroll * float(p["carry"]), 0)
		p["vel"] = v * (1.0 - 0.25 * dt) + Vector2(0, 2.0 * dt)
		if float(p["age"]) < float(p["life"]):
			keep.append(p)
	smoke = keep
	flashes = _aged(flashes, dt)
	booms = _aged(booms, dt)
	var keep2: Array[Dictionary] = []
	for s in sparks:
		s["age"] = float(s["age"]) + dt
		var v2: Vector2 = s["vel"]
		s["pos"] = (s["pos"] as Vector2) + v2 * dt - Vector2(scroll * float(s["carry"]), 0)
		s["vel"] = v2 + Vector2(0, float(s["g"]) * dt)
		if float(s["age"]) < float(s["life"]):
			keep2.append(s)
	sparks = keep2
	var keep3: Array[Dictionary] = []
	for c in casings:
		c["age"] = float(c["age"]) + dt
		var p3: Vector2 = c["pos"]
		var v3: Vector2 = c["vel"]
		if p3.y < float(c["ground"]):
			v3 += Vector2(0, GRAVITY * 1.4 * dt)
			p3 += v3 * dt
			if p3.y >= float(c["ground"]):
				c["carry"] = 1.0
				p3.y = float(c["ground"])
		p3.x -= scroll * float(c["carry"])
		c["pos"] = p3
		c["vel"] = v3
		if float(c["age"]) < float(c["life"]):
			keep3.append(c)
	casings = keep3
	tracers = _aged(tracers, dt)
	var keep4: Array[Dictionary] = []
	for l in leaves:
		l["age"] = float(l["age"]) + dt
		var v4: Vector2 = l["vel"]
		v4 = v4 * (1.0 - 1.6 * dt) + Vector2(0, LEAF_FALL * 2.0 * dt)
		l["vel"] = v4
		l["pos"] = (l["pos"] as Vector2) + v4 * dt - Vector2(scroll, 0)
		if float(l["age"]) < float(l["life"]):
			keep4.append(l)
	leaves = keep4
	var keep5: Array[Dictionary] = []
	for w in wisps:
		w["age"] = float(w["age"]) + dt
		var v5: Vector2 = w["vel"]
		v5 = v5 * (1.0 - 0.9 * dt) + Vector2(0, -3.0 * dt)
		w["vel"] = v5
		w["pos"] = (w["pos"] as Vector2) + v5 * dt - Vector2(scroll * 0.45, 0)
		if float(w["age"]) < float(w["life"]):
			keep5.append(w)
	wisps = keep5


static func _aged(list: Array[Dictionary], dt: float) -> Array[Dictionary]:
	var keep: Array[Dictionary] = []
	for f in list:
		f["age"] = float(f["age"]) + dt
		if float(f["age"]) < float(f["life"]):
			keep.append(f)
	return keep


## Smoke and steam (normal blend, under the foreground).
func draw_smoke(ci: CanvasItem) -> void:
	for p in smoke:
		var k := float(p["age"]) / float(p["life"])
		var r := lerpf(float(p["r0"]), float(p["r1"]), k)
		var a := float(p["a"]) * (1.0 - k) * minf(float(p["age"]) * 4.0, 1.0)
		var c: Color = p["c"]
		TankDraw.soft_at(ci, p["pos"], r, Color(c.r, c.g, c.b, a))
	for w in wisps:
		var kw := float(w["age"]) / float(w["life"])
		var col: Color = w["c"]
		col.a = float(w["a"]) * (1.0 - kw) * minf(float(w["age"]) * 12.0, 1.0)
		var size := Vector2(roundf(lerpf(3.0, float(w["len"]), kw)), float(w["h"]))
		ci.draw_rect(Rect2((w["pos"] as Vector2).floor(), size), col)


## Brass casings (normal blend).
func draw_solid(ci: CanvasItem) -> void:
	for c in casings:
		var k := 1.0 - float(c["age"]) / float(c["life"])
		ci.draw_rect(
			Rect2((c["pos"] as Vector2).floor(), Vector2(2, 1)), Color(0.85, 0.62, 0.28, k)
		)


## The leaves (normal blend): behind the near threats and the tank, so none lies on their plates.
func draw_leaves(ci: CanvasItem) -> void:
	for l in leaves:
		var age := float(l["age"])
		var ph := float(l["phase"]) + age * LEAF_SWAY_HZ * TAU
		var p: Vector2 = (l["pos"] as Vector2) + Vector2(sin(ph) * LEAF_SWAY, 0.0)
		var col: Color = l["c"]
		col.a = clampf((float(l["life"]) - age) * 2.0, 0.0, 1.0)
		var flat := fposmod(ph, TAU) < PI
		ci.draw_rect(Rect2(p.floor(), Vector2(2, 1) if flat else Vector2(1, 1)), col)


## Flashes, explosions, sparks and tracers (the additive layer).
func draw_light(ci: CanvasItem) -> void:
	for f in flashes:
		var k2 := 1.0 - float(f["age"]) / float(f["life"])
		var c2: Color = f["color"]
		var p: Vector2 = f["pos"]
		var r: float = f["r"]
		TankDraw.glow_at(ci, p, r * (0.6 + 0.4 * k2), Color(c2.r, c2.g, c2.b, 0.9 * k2))
		TankDraw.glow_at(ci, p, r * 0.3, Color(1, 1, 0.9, k2))
		if bool(f["star"]):
			var d: Vector2 = f["dir"]
			ci.draw_line(p, p + d * r * 1.1 * k2, Color(1, 0.9, 0.6, k2), 2.0)
			var o := d.orthogonal() * 6.0 * k2
			ci.draw_line(p - o, p + o, Color(1, 0.8, 0.5, k2 * 0.8), 1.0)
	for b in booms:
		var k3 := 1.0 - float(b["age"]) / float(b["life"])
		var br: float = b["r"]
		TankDraw.glow_at(ci, b["pos"], br * (1.2 - 0.5 * k3), Color(1.0, 0.5, 0.15, 0.8 * k3))
		TankDraw.glow_at(ci, b["pos"], br * 0.4, Color(1.0, 0.9, 0.6, k3))
	for s in sparks:
		var k4 := 1.0 - float(s["age"]) / float(s["life"])
		var c4: Color = s["c"]
		ci.draw_rect(Rect2((s["pos"] as Vector2).floor(), Vector2.ONE), Color(c4.r, c4.g, c4.b, k4))
	for t in tracers:
		var u := float(t["age"]) / float(t["life"])
		var a: Vector2 = t["a"]
		var b2: Vector2 = t["b"]
		var head := a.lerp(b2, u)
		var tail := a.lerp(b2, maxf(u - 0.18, 0.0))
		var c5: Color = t["c"]
		ci.draw_line(tail, head, Color(c5.r, c5.g, c5.b, 0.5), 1.0)
		TankDraw.px(ci, head, Color(1.0, 0.95, 0.8, 0.95))
		TankDraw.glow_at(ci, head, 3.0, Color(c5.r, c5.g, c5.b, 0.5))

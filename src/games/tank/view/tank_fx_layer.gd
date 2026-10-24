class_name TankFxLayer
extends Node2D
## Draws the live TankParticles of one blend mode (two layers: alpha and additive) in one canvas
## item, so the particles cost two draw calls however many are alive. Soft textures come from
## TankProcTex; the explosion uses the generated sprite once a real PNG exists.

## Puffs in a smoke ring.
const RING_PUFFS := 7

## The billowed puffs (built once): shaded for smoke, near white for steam.
static var _billow_tex: Dictionary = {}

## The particle store (owned by TankFx).
var particles: TankParticles = null
## True for the additive layer (lights, sparks, fire); false for smoke and solids.
var additive: bool = false
## Depth-of-field look for particles on other planes: toward the haze colour.
var haze: Color = TankPalette.HAZE

var _puff: Texture2D = null
var _billow: Texture2D = null
var _billow_white: Texture2D = null
var _glow: Texture2D = null
var _fire: Texture2D = null
var _boom_large: Texture2D = null
var _boom_small: Texture2D = null
var _muzzle: Texture2D = null
var _muzzle_real: bool = false


func _init(p_additive: bool = false) -> void:
	additive = p_additive
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
	_puff = TankProcTex.puff()
	_billow = billow(0.5)
	_billow_white = billow(0.82)
	_glow = TankProcTex.glow()
	_fire = TankProcTex.fireball()
	_boom_large = (
		TankSprites.tex("explosion_large") if TankSprites.has_real("explosion_large") else _fire
	)
	_muzzle_real = TankSprites.has_real("muzzle_flash")
	_muzzle = TankSprites.tex("muzzle_flash") if _muzzle_real else _glow
	_boom_small = (
		TankSprites.tex("explosion_small") if TankSprites.has_real("explosion_small") else _fire
	)


func _draw() -> void:
	if particles == null:
		return
	var p := particles
	for i in p.count:
		var k := p.kind[i]
		if TankParticles.ADDITIVE.has(k) != additive:
			continue
		_draw_one(p, i, k)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_one(p: TankParticles, i: int, k: int) -> void:
	var t := p.age(i)
	var base: Color = p.color[i]
	var grow := t
	if k == TankParticles.Kind.EXPLOSION or k == TankParticles.Kind.EXHAUST:
		grow = 1.0 - (1.0 - t) * (1.0 - t)
	var size := lerpf(p.size0[i], p.size1[i], grow)
	var a := base.a * _fade(k, t, p, i)
	var col := Color(base.r, base.g, base.b, a)
	var pl := p.plane[i]
	if pl == TankParticles.PLANE_BACK:
		col = col.lerp(Color(haze.r, haze.g, haze.b, col.a * 0.8), 0.45)
		size *= 1.25
	elif pl == TankParticles.PLANE_FRONT:
		col = Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, col.a * 0.6)
		size *= 1.5
	if a <= 0.004 or size <= 0.2:
		return
	var at := p.pos[i]
	match k:
		TankParticles.Kind.DUST:
			draw_texture_rect(
				_puff, Rect2(at - Vector2(size, size) * 0.5, Vector2(size, size)), false, col
			)
		TankParticles.Kind.SMOKE, TankParticles.Kind.STEAM:
			# Smoke and steam billow (lumpy clouds, never smooth balls), mirrored on odd slots so
			# the lumps of neighbouring puffs differ.
			var w := size if i % 2 == 0 else -size
			draw_texture_rect(
				_billow_white, Rect2(at - Vector2(w, size) * 0.5, Vector2(w, size)), false, col
			)
		TankParticles.Kind.EXHAUST:
			_draw_exhaust(at, size, col, t, p.rot[i])
		TankParticles.Kind.HEAT:
			var s := Vector2(size, size * 0.35)
			draw_texture_rect(_puff, Rect2(at - s * 0.5, s), false, col)
		TankParticles.Kind.DIRT:
			var s := maxf(1.0, roundf(size))
			draw_rect(Rect2(at.floor(), Vector2(s, s)), col)
		TankParticles.Kind.BRASS:
			draw_set_transform(at, p.rot[i], Vector2.ONE)
			# A casing: a brass body with a dark base rim, and one glint pixel as it tumbles.
			draw_rect(Rect2(-2.0, -1.0, 4.0, 2.0), col)
			draw_rect(
				Rect2(-2.0, -1.0, 1.0, 2.0), Color(col.r * 0.55, col.g * 0.5, col.b * 0.45, col.a)
			)
			if sin(p.life[i] * 23.0 + float(i)) > 0.55:
				draw_rect(Rect2(0.0, -1.0, 1.0, 1.0), Color(1.0, 0.95, 0.84, 0.95 * col.a))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		TankParticles.Kind.RING:
			_draw_ring(at, size, col, t, p.vel[i], p.rot[i])
		TankParticles.Kind.SPARK:
			var v := p.vel[i]
			var tail := at - v.normalized() * clampf(v.length() * 0.035, 1.5, 6.0)
			draw_line(tail, at, col, 1.0)
		TankParticles.Kind.EMBER:
			var s := maxf(1.0, roundf(size))
			draw_rect(Rect2(at.floor(), Vector2(s, s)), col)
		TankParticles.Kind.FIRE:
			draw_texture_rect(
				_fire, Rect2(at - Vector2(size, size) * 0.5, Vector2(size, size)), false, col
			)
		TankParticles.Kind.EXPLOSION:
			var tex := _boom_large if p.size1[i] > 40.0 else _boom_small
			var s := Vector2(size, size)
			draw_texture_rect(tex, Rect2(at - s * 0.5, s), false, col)
		TankParticles.Kind.FLASH:
			var s := Vector2(size, size)
			draw_texture_rect(_glow, Rect2(at - s * 0.5, s), false, col)
		TankParticles.Kind.MUZZLE:
			# The flash sprite points along the barrel (rotation = the barrel's direction): the
			# generated sprite when there is one, else a long soft glow.
			var half := Vector2(size, size * (0.625 if _muzzle_real else 0.45)) * 0.5
			draw_set_transform(
				at + Vector2.from_angle(p.rot[i]) * size * 0.35, p.rot[i], Vector2.ONE
			)
			draw_texture_rect(_muzzle, Rect2(-half, half * 2.0), false, col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A diesel puff: one billowed lump, darker on top and paler underneath (lit from below; warmed by
## the engine room's light while it is young). One smooth gradient, no separate highlight, so no
## puff shows a light outline (a ring) or spots.
func _draw_exhaust(at: Vector2, size: float, col: Color, t: float, turn: float) -> void:
	var c := col
	if t < 0.35:
		c = c.lerp(Color(TankPalette.AMBER, c.a), 0.25 * (1.0 - t / 0.35))
	var s := Vector2(size, size)
	draw_set_transform(at, turn, Vector2.ONE)
	draw_texture_rect(_billow, Rect2(-s * 0.5, s), false, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The muzzle's smoke ring, side on: soft puffs on a squashed ellipse, each with its own jittered
## angle, radius, size and strength (from the particle's seed `seed`) round a soft core, so it is a
## ragged roll and never a drawn "O". From a fifth of its life it closes up and swells into a cloud
## (the ring shrinks while its puffs grow and drift apart), so no late frame shows a "C" either.
func _draw_ring(at: Vector2, size: float, col: Color, t: float, v: Vector2, seed: float) -> void:
	var rr := maxf(size * 0.5, 1.5)
	var axis := Vector2.from_angle(v.angle() if v.length() > 1.0 else 0.0)
	var up := Vector2(-axis.y, axis.x)
	var br := clampf((t - 0.2) / 0.6, 0.0, 1.0)
	for n in RING_PUFFS:
		var h1 := _hash(seed, n)
		var h2 := _hash(seed + 3.1, n)
		var h3 := _hash(seed + 7.7, n)
		var u := TAU * (float(n) + h1 * 0.7) / float(RING_PUFFS)
		var rad := rr * (0.6 + 0.45 * h2) * (1.0 - 0.6 * br)
		var drift := Vector2(h2 - 0.45, -0.3 - h3) * br * rr * 0.5
		var c := at + axis * cos(u) * rad * 0.5 + up * sin(u) * rad + drift
		var ps := (rr * (1.2 + 0.5 * h3) + 3.0) * (1.0 + 0.5 * br)
		var pa := col.a * (0.4 + 0.4 * h1) * (1.0 - br * 0.5 * h2)
		draw_texture_rect(
			_puff,
			Rect2(c - Vector2(ps, ps) * 0.5, Vector2(ps, ps)),
			false,
			Color(col.r, col.g, col.b, pa)
		)
	# A soft core keeps the middle from ever reading as a hole, and fills in as it breaks up.
	var cs := rr * 1.3 + 3.0
	draw_texture_rect(
		_puff,
		Rect2(at - Vector2(cs, cs) * 0.5, Vector2(cs, cs)),
		false,
		Color(col.r, col.g, col.b, col.a * (0.3 + 0.4 * br))
	)


## A soft billowed puff, 32 x 32: one big round body with five smaller, uneven soft bulges (a
## cumulus outline with a dense middle, no stripes, rings or regular lobes), so a puff reads as a
## lump and not as a flat round dot, shaded by one smooth vertical ramp from `top` (the top's
## brightness) to 1 underneath (lit from below). Built on first use and shared.
static func billow(top: float) -> Texture2D:
	if _billow_tex.has(top):
		return _billow_tex[top]
	var lobes: Array[Vector3] = [
		Vector3(0.0, 0.06, 0.6),
		Vector3(-0.44, 0.14, 0.34),
		Vector3(0.42, 0.1, 0.38),
		Vector3(-0.2, -0.36, 0.38),
		Vector3(0.24, -0.3, 0.33),
		Vector3(0.5, -0.12, 0.24),
	]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var p := Vector2((float(x) + 0.5) / 16.0 - 1.0, (float(y) + 0.5) / 16.0 - 1.0)
			var a := 0.0
			for l in lobes:
				var k := clampf((l.z - p.distance_to(Vector2(l.x, l.y))) / 0.36 + 0.5, 0.0, 1.0)
				a = maxf(a, k * k * (3.0 - 2.0 * k))
			var v := lerpf(top, 1.0, smoothstep(-0.7, 0.75, p.y))
			img.set_pixel(x, y, Color(v, v, v, a))
	var tex := ImageTexture.create_from_image(img)
	_billow_tex[top] = tex
	return tex


## A repeatable pseudo-random 0 .. 1 from a particle's seed and a puff index (no RNG per frame).
static func _hash(seed: float, n: int) -> float:
	return fposmod(sin(seed * 12.9898 + float(n) * 78.233) * 43758.5453, 1.0)


## The alpha factor of particle `i` of kind `k` at progress `t`.
static func _fade(k: int, t: float, p: TankParticles, i: int) -> float:
	match k:
		TankParticles.Kind.SMOKE, TankParticles.Kind.DUST:
			return minf(t / 0.12, 1.0) * pow(1.0 - t, 1.2)
		TankParticles.Kind.EXHAUST:
			return minf(t / 0.06, 1.0) * pow(1.0 - t, 0.9)
		TankParticles.Kind.RING:
			return pow(1.0 - t, 1.3)
		TankParticles.Kind.STEAM:
			return minf(t / 0.08, 1.0) * pow(1.0 - t, 0.85)
		TankParticles.Kind.HEAT:
			return sin(t * PI)
		TankParticles.Kind.DIRT:
			return 1.0 if t < 0.8 else (1.0 - t) / 0.2
		TankParticles.Kind.BRASS:
			return 1.0 if t < 0.85 else (1.0 - t) / 0.15
		TankParticles.Kind.EMBER:
			return (1.0 - t) * (0.65 + 0.35 * sin(p.life[i] * 31.0 + float(i) * 1.7))
		TankParticles.Kind.FIRE:
			return pow(1.0 - t, 1.5)
		TankParticles.Kind.EXPLOSION, TankParticles.Kind.FLASH, TankParticles.Kind.MUZZLE:
			return pow(1.0 - t, 2.0)
	return 1.0 - t

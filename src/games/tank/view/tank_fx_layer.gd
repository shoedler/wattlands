class_name TankFxLayer
extends Node2D
## Draws the live TankParticles of one blend mode (two layers: alpha and additive) in one canvas
## item, so the particles cost two draw calls however many are alive. Soft textures come from
## TankProcTex; the explosion uses the generated sprite once a real PNG exists.

## The particle store (owned by TankFx).
var particles: TankParticles = null
## True for the additive layer (lights, sparks, fire); false for smoke and solids.
var additive: bool = false
## Depth-of-field look for particles on other planes: toward the haze colour.
var haze: Color = TankPalette.HAZE

var _puff: Texture2D = null
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
	var grow := 1.0 - (1.0 - t) * (1.0 - t) if k == TankParticles.Kind.EXPLOSION else t
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
		TankParticles.Kind.SMOKE, TankParticles.Kind.DUST, TankParticles.Kind.STEAM:
			draw_texture_rect(
				_puff, Rect2(at - Vector2(size, size) * 0.5, Vector2(size, size)), false, col
			)
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
			# A rolling torus of smoke, not an outline: soft puffs around an upright ellipse (seen from
			# the side, the ring blown along the barrel), thick while young, thinning as it grows, so it
			# never reads as a drawn "0".
			var rr := maxf(size * 0.5, 1.5)
			var puff := clampf(9.0 - size * 0.08, 4.0, 8.0)
			var v := p.vel[i]
			var ang := v.angle() if v.length() > 1.0 else 0.0
			var axis := Vector2.from_angle(ang)
			var up := Vector2(-axis.y, axis.x)
			var pc := Color(col.r, col.g, col.b, col.a * 0.55)
			for n in 12:
				var u := TAU * float(n) / 12.0
				var c := at + axis * cos(u) * rr * 0.45 + up * sin(u) * rr
				draw_texture_rect(
					_puff, Rect2(c - Vector2(puff, puff) * 0.5, Vector2(puff, puff)), false, pc
				)
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


## The alpha factor of particle `i` of kind `k` at progress `t`.
static func _fade(k: int, t: float, p: TankParticles, i: int) -> float:
	match k:
		TankParticles.Kind.SMOKE, TankParticles.Kind.DUST:
			return minf(t / 0.12, 1.0) * pow(1.0 - t, 1.2)
		TankParticles.Kind.STEAM:
			return minf(t / 0.1, 1.0) * (1.0 - t)
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

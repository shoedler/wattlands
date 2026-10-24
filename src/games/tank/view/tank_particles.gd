class_name TankParticles
extends RefCounted
## The view's own pooled particles (brief 3, "Particles"): structure-of-arrays storage with a hard
## cap (CAP, about 400 live), swap-remove on death, no node and no texture per particle. Smoke,
## sparks, brass, dirt, steam, fire and explosions all live here; TankFxLayer draws them (two
## CanvasItems, one alpha-blended and one additive). Cosmetic only: it never touches the rules and
## draws its randomness from the view's RNG (passed in by the emitters in TankFx).

enum Kind {
	SMOKE,
	DUST,
	STEAM,
	HEAT,
	DIRT,
	BRASS,
	RING,
	SPARK,
	EMBER,
	FIRE,
	EXPLOSION,
	FLASH,
	MUZZLE,
	EXHAUST,
}

## Hard cap on live particles.
const CAP := 400
## Kinds drawn additively (lights); the rest are alpha-blended.
const ADDITIVE: Array[int] = [
	Kind.SPARK, Kind.EMBER, Kind.FIRE, Kind.EXPLOSION, Kind.FLASH, Kind.MUZZLE
]
## Kinds that may be dropped when the pool is full (the rest evict the oldest particle).
const DROPPABLE: Array[int] = [
	Kind.SMOKE, Kind.DUST, Kind.STEAM, Kind.HEAT, Kind.DIRT, Kind.EMBER, Kind.EXHAUST
]
## Depth planes: 0 on the tank's plane (sharp), 1 behind it (soft and hazy), -1 in front of it.
const PLANE_BACK := 1
const PLANE_FRONT := -1
## On the hull: inside an engine room, carried along with the tank (the camera follows the hull, so
## these never scroll). Drawn like plane 0.
const PLANE_HULL := 2
## Camera scroll factor per plane (see ParallaxStrip factors).
const PLANE_SCROLL := {0: 1.0, 1: 0.5, -1: 1.3, 2: 0.0}

## The live particles (indexes 0 .. count - 1).
var count: int = 0
## The cap in force (lowered by TankFx when the frame time rises).
var cap: int = CAP
var pos: PackedVector2Array = PackedVector2Array()
var vel: PackedVector2Array = PackedVector2Array()
var life: PackedFloat32Array = PackedFloat32Array()
var ttl: PackedFloat32Array = PackedFloat32Array()
var size0: PackedFloat32Array = PackedFloat32Array()
var size1: PackedFloat32Array = PackedFloat32Array()
var rot: PackedFloat32Array = PackedFloat32Array()
var spin: PackedFloat32Array = PackedFloat32Array()
var grav: PackedFloat32Array = PackedFloat32Array()
var drag: PackedFloat32Array = PackedFloat32Array()
var kind: PackedInt32Array = PackedInt32Array()
var plane: PackedInt32Array = PackedInt32Array()
var color: PackedColorArray = PackedColorArray()
## The lowest a particle may go (layer y; INF for none): a spark struck off the deck dies when it
## falls back past the armour it came off, so it never streaks down into the rooms under it.
var floor_y: PackedFloat32Array = PackedFloat32Array()
## Spawns dropped because the pool was full (tests).
var dropped: int = 0
## Spawns ever accepted (tests).
var spawned: int = 0

var _evict_from: int = 0
var _last: int = -1


func _init() -> void:
	pos.resize(CAP)
	vel.resize(CAP)
	life.resize(CAP)
	ttl.resize(CAP)
	size0.resize(CAP)
	size1.resize(CAP)
	rot.resize(CAP)
	spin.resize(CAP)
	grav.resize(CAP)
	drag.resize(CAP)
	kind.resize(CAP)
	plane.resize(CAP)
	color.resize(CAP)
	floor_y.resize(CAP)


func clear() -> void:
	count = 0


## Adds a particle; returns false when it was dropped (full pool, droppable kind). A non-droppable
## spawn into a full pool replaces the particle with the least life left.
func spawn(
	p_kind: int,
	p_pos: Vector2,
	p_vel: Vector2,
	p_ttl: float,
	p_size0: float,
	p_size1: float,
	p_color: Color,
	p_grav: float = 0.0,
	p_drag: float = 0.0,
	p_plane: int = 0
) -> bool:
	var i := count
	if count >= mini(cap, CAP):
		if DROPPABLE.has(p_kind):
			dropped += 1
			return false
		i = _least_life()
		if i < 0:
			dropped += 1
			return false
	else:
		count += 1
	pos[i] = p_pos
	vel[i] = p_vel
	life[i] = p_ttl
	ttl[i] = maxf(p_ttl, 0.001)
	size0[i] = p_size0
	size1[i] = p_size1
	rot[i] = 0.0
	spin[i] = 0.0
	grav[i] = p_grav
	drag[i] = p_drag
	kind[i] = p_kind
	plane[i] = p_plane
	color[i] = p_color
	floor_y[i] = INF
	_last = i
	spawned += 1
	return true


## Sets the rotation and spin (rad, rad/s) of the particle spawned last (casings tumble).
func tumble(p_rot: float, p_spin: float) -> void:
	if _last >= 0 and _last < count:
		rot[_last] = p_rot
		spin[_last] = p_spin


## Sets the floor (layer y) of the particle spawned last: it dies when it falls below it.
func set_floor(y: float) -> void:
	if _last >= 0 and _last < count:
		floor_y[_last] = y


## Advances every particle by `dt` seconds and removes the dead. `scroll_px` is how far the camera
## moved right this step: particles in the world (plane 0) slide left by it, those on the far plane
## by half and those in front by 1.3 x, like the planes' parallax; those on the hull stay put.
func step(dt: float, ground_y: float, scroll_px: float = 0.0) -> void:
	var i := 0
	while i < count:
		life[i] -= dt
		if life[i] <= 0.0:
			_remove(i)
			continue
		var v := vel[i]
		v.y += grav[i] * dt
		if drag[i] > 0.0:
			v *= maxf(0.0, 1.0 - drag[i] * dt)
		var p := pos[i] + v * dt
		if scroll_px != 0.0:
			p.x -= scroll_px * PLANE_SCROLL.get(plane[i], 1.0)
		if p.y > floor_y[i]:
			_remove(i)
			continue
		var k := kind[i]
		if (k == Kind.BRASS or k == Kind.DIRT or k == Kind.EMBER) and p.y > ground_y:
			p.y = ground_y
			if k == Kind.DIRT or absf(v.y) < 12.0:
				v = Vector2.ZERO
				spin[i] = 0.0
			else:
				v = Vector2(v.x * 0.55, -v.y * 0.35)
				spin[i] *= 0.5
		vel[i] = v
		pos[i] = p
		rot[i] += spin[i] * dt
		i += 1


## Progress 0 (born) .. 1 (dead) of particle `i`.
func age(i: int) -> float:
	return clampf(1.0 - life[i] / ttl[i], 0.0, 1.0)


## True when particle `i` is drawn on the additive layer. Cold sparks (a spark whose colour is bluer
## than red: the dynamo's) are blended instead: added over a room lit amber by a rider's lamp, a
## blue-white stroke clips to cream and reads as a warm spark, so they keep their own colour.
func is_additive(i: int) -> bool:
	var k := kind[i]
	if k == Kind.SPARK:
		return color[i].b <= color[i].r
	return ADDITIVE.has(k)


## How many live particles are of `p_kind` (tests).
func count_kind(p_kind: int) -> int:
	var n := 0
	for i in count:
		if kind[i] == p_kind:
			n += 1
	return n


func _remove(i: int) -> void:
	var last := count - 1
	if i != last:
		pos[i] = pos[last]
		vel[i] = vel[last]
		life[i] = life[last]
		ttl[i] = ttl[last]
		size0[i] = size0[last]
		size1[i] = size1[last]
		rot[i] = rot[last]
		spin[i] = spin[last]
		grav[i] = grav[last]
		drag[i] = drag[last]
		kind[i] = kind[last]
		plane[i] = plane[last]
		color[i] = color[last]
		floor_y[i] = floor_y[last]
	count -= 1


## The particle with the least life left, scanning from a rotating start so ties (a pool full of
## particles of the same age) evict in turn instead of always the first.
func _least_life() -> int:
	var best := -1
	var best_frac := INF
	for n in count:
		var i := (_evict_from + n) % count
		var frac := life[i] / ttl[i]
		if frac < best_frac:
			best_frac = frac
			best = i
	_evict_from = (best + 1) % maxi(count, 1)
	return best

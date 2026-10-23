class_name FishingEffects
extends Node2D
## One lane's effects layer (brief 3.5 layer 8): splash, spray, catch flash and trophy badge
## sprites from a small pool, each ending in a DitherDissolve over the second half of its life
## (brief 3.3 "effects end in a dither dissolve"). spawn() reuses the oldest sprite when the pool
## is full, so nothing is allocated after the pool is built.

const POOL := 10
## Seconds each effect lives, and how far it rises (art px over its life).
const LIFE := {"splash": 0.6, "spray": 0.9, "catch_flash": 1.0, "trophy_badge": 2.2}
const RISE := {"splash": 0.0, "spray": 3.0, "catch_flash": 0.0, "trophy_badge": 8.0}

var _sprites: Array[Sprite2D] = []
var _mats: Array[ShaderMaterial] = []
var _age: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _rise: PackedFloat32Array = PackedFloat32Array()
var _start: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	name = "Effects"
	_age.resize(POOL)
	_life.resize(POOL)
	_rise.resize(POOL)
	_start.resize(POOL)
	for i in POOL:
		var s := Sprite2D.new()
		s.name = "Fx%d" % i
		s.visible = false
		_mats.append(DitherDissolve.apply(s, 0.0, 1))
		_sprites.append(s)
		add_child(s)


## Shows sprite `id` centred at `pos` (lane px) for its life.
func spawn(id: String, pos: Vector2) -> void:
	var k := -1
	var oldest := -1.0
	for i in POOL:
		if not _sprites[i].visible:
			k = i
			break
		if _age[i] > oldest:
			oldest = _age[i]
			k = i
	var s := _sprites[k]
	s.texture = FishingSprites.texture(id)
	s.position = pos.round()
	s.visible = true
	_age[k] = 0.0
	_life[k] = float(LIFE.get(id, 0.8))
	_rise[k] = float(RISE.get(id, 0.0))
	_start[k] = s.position
	DitherDissolve.set_amount(_mats[k], 0.0)


func tick(dt: float) -> void:
	for i in POOL:
		var s := _sprites[i]
		if not s.visible:
			continue
		_age[i] += dt
		var u := _age[i] / maxf(_life[i], 0.01)
		if u >= 1.0:
			s.visible = false
			continue
		DitherDissolve.set_amount(_mats[i], clampf((u - 0.5) * 2.0, 0.0, 1.0))
		s.position = (_start[i] - Vector2(0, _rise[i] * u)).round()


## Effects showing now (tests).
func active() -> int:
	var n := 0
	for s in _sprites:
		if s.visible:
			n += 1
	return n


## The sprite ids showing now (tests).
func active_ids() -> Array[String]:
	var out: Array[String] = []
	for s in _sprites:
		if s.visible and s.texture != null:
			for id: String in LIFE:
				if s.texture == FishingSprites.texture(id):
					out.append(id)
	return out

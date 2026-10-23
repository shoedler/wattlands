class_name FishingEffects
extends Node2D
## The effects layer: splashes and catch sparkles from a small pool of frame-animated sprites
## (fx_splash, fx_sparkle), each played once through its frames. spawn() reuses the oldest when
## the pool is full, so nothing is allocated after the pool is built. Positions are view px.

const POOL := 12
const FPS := 9.0

var _sprites: Array[Sprite2D] = []
var _ids: Array[String] = []
var _age: PackedFloat32Array = PackedFloat32Array()
## World x (m) each effect is pinned to, so it stays put while the camera moves.
var _x_m: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	name = "Effects"
	_age.resize(POOL)
	_x_m.resize(POOL)
	for i in POOL:
		var s := Sprite2D.new()
		s.name = "Fx%d" % i
		s.visible = false
		s.centered = false
		_sprites.append(s)
		_ids.append("")
		add_child(s)


## Plays sprite `id` with its anchor at world x `x_m`, view row `y`.
func spawn(id: String, x_m: float, y: float) -> void:
	var k := 0
	var oldest := -1.0
	for i in POOL:
		if not _sprites[i].visible:
			k = i
			break
		if _age[i] > oldest:
			oldest = _age[i]
			k = i
	_ids[k] = id
	_age[k] = 0.0
	_x_m[k] = x_m
	var s := _sprites[k]
	s.visible = true
	s.texture = FishingSprites.frame(id, 0)
	s.offset = -Vector2(FishingSprites.anchor(id))
	s.position.y = roundf(y)


## Advances every effect and places it for camera `cam_m`.
func tick(dt: float, cam_m: float) -> void:
	for i in POOL:
		var s := _sprites[i]
		if not s.visible:
			continue
		_age[i] += dt
		var f := floori(_age[i] * FPS)
		if f >= FishingSprites.count(_ids[i]):
			s.visible = false
			continue
		s.texture = FishingSprites.frame(_ids[i], f)
		s.position.x = roundf(FishingScenery.screen_x(_x_m[i], cam_m))


## The sprite ids showing now (tests).
func active_ids() -> Array[String]:
	var out: Array[String] = []
	for i in POOL:
		if _sprites[i].visible:
			out.append(_ids[i])
	return out

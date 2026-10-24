class_name TankTurretView
extends Node2D
## The main turret (brief 2.4 Gun, brief 3): the turret sprite on the ring, a code-drawn barrel on
## the trunnion at the gun's elevation, recoil along the barrel and the traverse flip. The node sits
## on the turret ring in the hull frame and mirrors with scale.x, so a traverse turns the turret
## "through" the side view: the facing eases from one side to the other over the traverse time.
## Geometry comes from rigs.json through the same numbers TankGeometry reads.

const BARREL_W := 3.0
const ELEV_RATE_DEG_S := 45.0
const RECOIL_PX := 4.5
const RECOIL_DECAY := 9.0

var tank: String = ""
var ring: Vector2 = Vector2.ZERO
var trunnion: Vector2 = Vector2.ZERO
var barrel_px: float = 40.0
var sprite: Sprite2D = null
var barrel: TankPainter = null
## The visual facing -1 .. 1 (scale.x): +1 right, -1 left, between during a traverse.
var dir: float = 1.0
## The elevation shown (degrees) and the recoil (px back along the barrel).
var elev: float = 0.0
var recoil: float = 0.0
var _trav_target: float = 1.0
var _was_traversing: bool = false


## Builds the turret from rigs.json `tanks.<id>.turret`.
func assemble(p_tank: String, turret_def: Dictionary) -> void:
	name = "Turret"
	tank = p_tank
	ring = TankRigs.vec(turret_def.get("ring"))
	trunnion = TankRigs.vec(turret_def.get("trunnion"))
	barrel_px = float(turret_def.get("barrel_px", 40))
	position = ring
	barrel = TankPainter.new()
	barrel.name = "Barrel"
	barrel.position = trunnion - ring
	barrel.painter = _paint_barrel
	add_child(barrel)
	var r := TankRigs.rect(turret_def.get("rect"))
	sprite = Sprite2D.new()
	sprite.name = "Hull"
	sprite.texture = TankSprites.tex(TankSprites.turret_id(p_tank))
	sprite.centered = false
	sprite.position = r.position - ring
	add_child(sprite)


## One frame: eases the facing and the elevation toward the state's.
func update(facing: int, elev_deg: float, traverse_s: float, dt: float) -> void:
	var f := float(facing)
	if traverse_s > 0.0:
		if not _was_traversing:
			# A traverse starts: the facing flag may already be the new side, or flip at the end.
			_trav_target = f if signf(dir) != f else -f
		_was_traversing = true
		var left := maxf(traverse_s, dt)
		dir = move_toward(dir, _trav_target, absf(_trav_target - dir) / left * dt)
	else:
		_was_traversing = false
		_trav_target = f
		dir = move_toward(dir, f, 8.0 * dt)
	scale.x = dir if absf(dir) > 0.04 else 0.04 * signf(dir if dir != 0.0 else 1.0)
	elev = move_toward(elev, elev_deg, ELEV_RATE_DEG_S * dt)
	recoil *= exp(-RECOIL_DECAY * dt)
	if recoil < 0.05:
		recoil = 0.0
	barrel.queue_redraw()


## The shot: the barrel kicks back.
func kick(strength: float = 1.0) -> void:
	recoil = RECOIL_PX * clampf(strength, 0.3, 1.6)


## True while the turret is turning (the facing is between its two sides).
func is_turning() -> bool:
	return absf(dir) < 0.98


## The muzzle in the hull frame for the shown facing side and elevation (the sign of dir).
func muzzle_hull() -> Vector2:
	var a := deg_to_rad(elev)
	var local := trunnion - ring + Vector2(cos(a), -sin(a)) * barrel_px
	return ring + Vector2(local.x * scale.x, local.y)


## The main gun: a 3 px tube (a 1 px lit top in STEEL_BRIGHT, a steel middle, a 1 px dark underside)
## along the elevation, a recoil sleeve at the breech and a plain cylindrical muzzle brake (a 4 x 5
## block with a dark baffle slot), drawn on the barrel's own axis so it stays a clean tube at any
## elevation (no chevron at the tip).
func _paint_barrel(item: Node2D) -> void:
	var a := deg_to_rad(elev)
	item.draw_set_transform(Vector2.ZERO, -a, Vector2.ONE)
	var x0 := -recoil
	var x1 := barrel_px - recoil
	var length := x1 - x0
	# Whole-pixel rows (the trunnion sits on a pixel corner): -2..1 is three rows.
	item.draw_rect(Rect2(x0, -2.0, length, 3.0), TankPalette.STEEL)
	item.draw_rect(Rect2(x0, -2.0, length, 1.0), TankPalette.STEEL_BRIGHT)
	item.draw_rect(Rect2(x0, 0.0, length, 1.0), TankPalette.IRON_DARK)
	# The recoil sleeve.
	item.draw_rect(Rect2(x0, -3.0, 10.0, 5.0), TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(x0, -3.0, 10.0, 1.0), TankPalette.STEEL_LIGHT)
	item.draw_rect(Rect2(x0, 1.0, 10.0, 1.0), TankPalette.COAL)
	# The muzzle brake.
	item.draw_rect(Rect2(x1 - 4.0, -3.0, 4.0, 5.0), TankPalette.IRON)
	item.draw_rect(Rect2(x1 - 4.0, -3.0, 4.0, 1.0), TankPalette.STEEL_LIGHT)
	item.draw_rect(Rect2(x1 - 4.0, 1.0, 4.0, 1.0), TankPalette.COAL)
	item.draw_rect(Rect2(x1 - 2.0, -2.0, 1.0, 3.0), TankPalette.SOOT)
	item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

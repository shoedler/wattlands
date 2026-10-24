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


func _paint_barrel(item: Node2D) -> void:
	var a := deg_to_rad(elev)
	var d := Vector2(cos(a), -sin(a))
	var n := Vector2(-d.y, d.x)
	var base := -d * recoil
	var tip := d * (barrel_px - recoil)
	# Barrel body, a lighter top edge and a muzzle brake.
	item.draw_line(base, tip, TankPalette.STEEL_DARK, BARREL_W)
	item.draw_line(base - n, tip - n, TankPalette.STEEL, 1.0)
	item.draw_line(tip - d * 5.0, tip, TankPalette.STEEL, BARREL_W + 2.0)
	item.draw_line(tip - d * 5.0 - n * 2.5, tip - n * 2.5, TankPalette.STEEL_LIGHT, 1.0)
	# Recoil sleeve at the breech end.
	item.draw_line(base, base + d * 9.0, TankPalette.STEEL, BARREL_W + 2.0)

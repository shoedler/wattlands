class_name TankSecondaryView
extends Node2D
## One of the Citadel's two secondary turrets (fore right, aft left): a small turret sprite on the
## roof with a code-drawn barrel to the muzzle in rigs.json, kicking back when it fires.

const RECOIL_PX := 2.0
const RECOIL_DECAY := 12.0

var facing: int = 1
var rect: Rect2 = Rect2()
var muzzle: Vector2 = Vector2.ZERO
var recoil: float = 0.0
var barrel: TankPainter = null
var sprite: Sprite2D = null


## Builds one entry of rigs.json `tanks.citadel.secondaries`.
func assemble(sec_def: Dictionary) -> void:
	name = "Secondary_" + str(sec_def.get("id", ""))
	facing = int(sec_def.get("facing", 1))
	rect = TankRigs.rect(sec_def.get("rect"))
	muzzle = TankRigs.vec(sec_def.get("muzzle"))
	position = rect.position
	barrel = TankPainter.new()
	barrel.name = "Barrel"
	barrel.painter = _paint_barrel
	add_child(barrel)
	sprite = Sprite2D.new()
	sprite.name = "Hull"
	sprite.texture = TankSprites.tex("turret_secondary")
	sprite.centered = false
	sprite.flip_h = facing < 0
	add_child(sprite)


func kick() -> void:
	recoil = RECOIL_PX


func update(dt: float) -> void:
	if recoil > 0.0:
		recoil *= exp(-RECOIL_DECAY * dt)
		if recoil < 0.05:
			recoil = 0.0
		barrel.queue_redraw()


## The muzzle in the hull frame.
func muzzle_hull() -> Vector2:
	return muzzle - Vector2(recoil * float(facing), 0.0)


## A 2 px barrel (a lit top row in STEEL_BRIGHT, a dark underside) and a plain 3 x 4 muzzle block.
func _paint_barrel(item: Node2D) -> void:
	var to := muzzle - rect.position - Vector2(recoil * float(facing), 0.0)
	to.y = roundf(to.y)
	var from := Vector2(rect.size.x - 6.0 if facing > 0 else 6.0, to.y)
	var x0 := minf(from.x, to.x)
	var length := absf(to.x - from.x)
	item.draw_rect(Rect2(x0, from.y - 1.0, length, 1.0), TankPalette.STEEL_BRIGHT)
	item.draw_rect(Rect2(x0, from.y, length, 1.0), TankPalette.STEEL_DARK)
	var bx := to.x - (3.0 if facing > 0 else 0.0)
	item.draw_rect(Rect2(bx, from.y - 2.0, 3.0, 4.0), TankPalette.IRON)
	item.draw_rect(Rect2(bx, from.y - 2.0, 3.0, 1.0), TankPalette.STEEL_LIGHT)

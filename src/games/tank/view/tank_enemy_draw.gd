class_name TankEnemyDraw
extends RefCounted
## v4: draws one enemy from the kit (SPEC_TANK 5.4). Stub until builder A: a filled grey-green box of
## the kind's size with a darker turret and a gun line.
## pose: {travel: float, turret_sx: float (1 to the kind's front, -1 back), elev_deg: float, recoil: float,
##        dim: float, haze: float, flash: float, ground: Callable (x -> stage y) or null, wrecked: bool,
##        bogies_wrecked: Array[bool], flip: bool, time: float}

const HULL := Color(0.3, 0.35, 0.31)
const TURRET := Color(0.22, 0.26, 0.23)
const GUN := Color(0.14, 0.16, 0.14)
const WRECK := Color(0.11, 0.08, 0.06)
const HAZE := Color(0.27, 0.31, 0.36)
const SLIT := Color(0.5, 0.88, 0.82)
const FLASH := Color(1.0, 1.0, 0.9)
## The turret's share of the sprite.
const TURRET_W := 0.36
const TURRET_H := 0.36
const GUN_Y := 0.2


static func draw(
	ci: CanvasItem, kit: TankEnemyKit, kind: String, foot: Vector2, pose: Dictionary
) -> void:
	var size: Vector2 = kit.kind(kind)["size"]
	var box := Rect2(foot - Vector2(size.x * 0.5, size.y), size)
	var top_h := size.y * TURRET_H
	var hull := Rect2(box.position + Vector2(0.0, top_h), Vector2(size.x, size.y - top_h))
	var wrecked := bool(pose.get("wrecked", false))
	ci.draw_rect(hull, _tone(WRECK if wrecked else HULL, pose))
	var tw := size.x * TURRET_W
	var turret := Rect2(foot.x - tw * 0.5, box.position.y, tw, top_h)
	ci.draw_rect(turret, _tone(WRECK if wrecked else TURRET, pose))
	if not wrecked:
		ci.draw_line(
			_trunnion(foot, size),
			muzzle(kit, kind, foot, pose),
			_tone(GUN, pose),
			maxf(size.y * 0.05, 1.0)
		)


## Additive slit and lamp glows.
static func draw_light(
	ci: CanvasItem, kit: TankEnemyKit, kind: String, foot: Vector2, pose: Dictionary
) -> void:
	if bool(pose.get("wrecked", false)):
		return
	var size: Vector2 = kit.kind(kind)["size"]
	var y := foot.y - size.y * (1.0 - TURRET_H * 0.5)
	ci.draw_rect(Rect2(foot.x - 2.0, y, 4.0, 1.0), SLIT * (1.0 - float(pose.get("dim", 0.0))))


## Where a shot leaves the gun, on the stage.
static func muzzle(kit: TankEnemyKit, kind: String, foot: Vector2, pose: Dictionary) -> Vector2:
	var row := kit.kind(kind)
	var size: Vector2 = row["size"]
	var sx := float(row["faces"]) * float(pose.get("turret_sx", 1.0))
	if bool(pose.get("flip", false)):
		sx = -sx
	var length := size.x * 0.5 - float(pose.get("recoil", 0.0))
	var rad := deg_to_rad(float(pose.get("elev_deg", 0.0)))
	return _trunnion(foot, size) + Vector2(sx * cos(rad), -sin(rad)) * length


static func _trunnion(foot: Vector2, size: Vector2) -> Vector2:
	return foot - Vector2(0.0, size.y * (1.0 - GUN_Y))


static func _tone(c: Color, pose: Dictionary) -> Color:
	var out := c.darkened(clampf(float(pose.get("dim", 0.0)), 0.0, 1.0))
	out = out.lerp(HAZE, clampf(float(pose.get("haze", 0.0)), 0.0, 1.0))
	return out.lerp(FLASH, clampf(float(pose.get("flash", 0.0)), 0.0, 1.0))

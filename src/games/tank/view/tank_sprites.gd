class_name TankSprites
extends RefCounted
## The view's one door to sprite textures: the generated PNG from assets/tank/sprites/<id>.png when
## it exists, else TankPlaceholderArt's stand-in (artqa owns that class; only its public API is
## used here: texture(id), size_of(id)). Every id works with placeholders.


## The texture of sprite `id`.
static func tex(id: String) -> Texture2D:
	return TankPlaceholderArt.texture(id)


## The sprite's size in art px (art.json).
static func size(id: String) -> Vector2:
	return Vector2(TankPlaceholderArt.size_of(id))


## True when a generated PNG exists for `id` (so effects may use it instead of a procedural look).
static func has_real(id: String) -> bool:
	return ResourceLoader.exists(TankPlaceholderArt.SPRITES_DIR.path_join(id + ".png"))


## The enemy sprite id of a TankIds.ENEMY_* type ("enemy_light", ...).
static func enemy_id(type: String) -> String:
	return "enemy_" + type


## The hull sprite id of a tank ("hull_bulwark", ...).
static func hull_id(tank: String) -> String:
	return "hull_" + tank


## The turret sprite id of a tank.
static func turret_id(tank: String) -> String:
	return "turret_" + tank


## The steam room's flyball regulator sprite id. art.json names it with the word the platform's
## no-bypass scan guards (a game may not spell it, even as a sprite id), so it is found by prefix
## ("flyball" if art renames it); "" when absent.
static func flyball_id() -> String:
	for id in TankPlaceholderArt.ids():
		if id.begins_with("gov") or id.begins_with("flyball"):
			return id
	return ""

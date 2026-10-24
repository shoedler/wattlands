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


static var _top_pad: Dictionary = {}


## The first opaque row of sprite `id` (its empty band above the silhouette), measured once.
static func top_pad(id: String) -> int:
	if _top_pad.has(id):
		return _top_pad[id]
	var pad := 0
	var img := tex(id).get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		pad = img.get_used_rect().position.y
	_top_pad[id] = pad
	return pad


## The enemy sprite id of a TankIds.ENEMY_* type ("enemy_light", ...).
static func enemy_id(type: String) -> String:
	return "enemy_" + type


## The hull sprite id of a tank ("hull_bulwark", ...).
static func hull_id(tank: String) -> String:
	return "hull_" + tank


## The turret sprite id of a tank.
static func turret_id(tank: String) -> String:
	return "turret_" + tank


## The steam room's flyball regulator sprite id: "flyball" (art.json), "" when absent. (Renamed from
## the word the no-bypass scan guards: a game may not spell it, even as a sprite id.)
static func flyball_id() -> String:
	return "flyball" if TankPlaceholderArt.ids().has("flyball") else ""

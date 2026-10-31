class_name TankViewHud
extends TankViewWorld
## TankView's HUD layer: the geometry the HUD reads through TankHudGeom.

# --- The HUD's geometry (TankHudGeom; canvas art px, 0,0 the canvas' top left) ----------------------


func hud_world_x(world_x_px: float) -> float:
	return _hud_x(sx(world_x_px))


func hud_mirrored() -> bool:
	return mirrored


## The road line under the tank (the flat line; the relief moves it a few px).
func hud_ground_y() -> float:
	return GROUND + y_off


## A tank point as drawn now: "barrel_pivot" (the trunnion), "muzzle" (at the elevation and recoil),
## "rear" (the road under the hull's rear end), "turret_pivot", "headlight", "exhaust",
## "bow_gun_upper_pivot" / "_muzzle", "bow_gun_lower_pivot" / "_muzzle", "searchlight_turret_lens",
## "searchlight_rear_lens".
func hud_tank_point(name: String) -> Vector2:
	var p := Vector2.ZERO
	match name:
		"barrel_pivot", "trunnion":
			p = barrel_pivot()
		"muzzle":
			p = muzzle()
		"rear":
			p = Vector2(at_sprite(Vector2(ART_REAR, rig.ground)).x, GROUND)
		"turret_pivot":
			p = at_sprite(Vector2(rig.turret_pivot_x, rig.turret_rect.end.y))
		"headlight":
			p = at_sprite(rig.detail("headlight")["at"])
		"exhaust":
			p = at_sprite(rig.exhaust)
		"bow_gun_upper_pivot":
			p = at_sprite(rig.bow[0]["pivot"])
		"bow_gun_upper_muzzle":
			p = bow_muzzle(0)
		"bow_gun_lower_pivot":
			p = at_sprite(rig.bow[1]["pivot"])
		"bow_gun_lower_muzzle":
			p = bow_muzzle(1)
		"searchlight_turret_lens":
			p = at_sprite(TankRig.lens_of(rig.detail("searchlight")))
		"searchlight_rear_lens":
			p = at_sprite(TankRig.lens_of(rig.detail("searchlight_rear")))
		_:
			p = at_sprite(Vector2(rig.size.x * 0.5, rig.ground))
	return Vector2(_hud_x(p.x), p.y + y_off)


## The bow guns' muzzles on the canvas.
func hud_bow_muzzles() -> Array[Vector2]:
	return [hud_tank_point("bow_gun_upper_muzzle"), hud_tank_point("bow_gun_lower_muzzle")]


## The barrel's length (art px, trunnion to the muzzle).
func hud_barrel_length() -> float:
	return rig.gun_len + 1.0


## The barrel always faces the way the tank drives.
func hud_barrel_dir() -> float:
	return -1.0 if mirrored else 1.0


## The tank's body on the canvas as drawn now, which the world tags keep out of: the hitbox's turret
## and its hull joined with the track run, each the bounds of the rect as rotated,
## rounded out to whole art px.
func hud_tank_rects() -> Array[Rect2]:
	var off := Vector2(0, y_off)
	var hull := rig.hit_rect("hull").merge(rig.hit_rect("track_run"))
	var out: Array[Rect2] = []
	out.append(_bounds(xf, rig.hit_rect("turret")))
	out.append(_bounds(xf, hull))
	for i in out.size():
		var h := _hud_rect(out[i])
		var a := (h.position + off).floor()
		out[i] = Rect2(a, (h.end + off).ceil() - a)
	return out


static func _bounds(t: Transform2D, r: Rect2) -> Rect2:
	var a := t * r.position
	var out := Rect2(a, Vector2.ZERO)
	for c: Vector2 in [Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		out = out.expand(t * c)
	return out


## An enemy's sprite on the canvas: in the far panel (canvas px already) or on the near stage.
func hud_enemy_rect(id: int) -> Rect2:
	if far_rects.has(id):
		return far_rects[id]
	if not enemy_rects.has(id):
		return Rect2()
	var r: Rect2 = _hud_rect(enemy_rects[id])
	return Rect2(r.position + Vector2(0, y_off), r.size)


## Where a far enemy's gun ends on the canvas; Vector2.ZERO when it is not drawn in the far panel.
func hud_enemy_muzzle(id: int) -> Vector2:
	if far == null or not far.feet.has(id) or game == null or game.state == null:
		return Vector2.ZERO
	var e := game.state.enemy(id)
	return far.canvas_point(far.muzzle_of(e), far_panel_x()) if e != null else Vector2.ZERO


func hud_boss_rect() -> Rect2:
	if game == null or game.state == null or far == null or not boss_visible(game.state):
		return Rect2()
	return far.canvas_rect(far.boss_box, far_panel_x())


func hud_boss_muzzle() -> Vector2:
	if hud_boss_rect().size == Vector2.ZERO:
		return Vector2.ZERO
	return far.canvas_point(far.boss_muzzle(game.state), far_panel_x())

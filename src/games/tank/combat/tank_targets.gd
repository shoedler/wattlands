class_name TankTargets
extends RefCounted
## The things the main gun can hit this tick, and the geometry that places them (brief 2.4;
## owner: rules). Rebuilt once a tick after the enemies and the Behemoth moved, in a fixed order:
## enemies by id, the boss parts rear to front, obstacles by id.

## The hull sprite's bottom sits this far above the ground line (rigs.json screen.skirt_gap_px).
const SKIRT_GAP := 10
## The obstacles' hit box heights when content has none (tanks.json props.<type>.h).
const DEFAULT_PROP_H := 24


## The hull sprite's top-left in world art px.
static func hull_origin(state: TankState) -> Vector2:
	return Vector2(state.hull.x_px, TankConst.GROUND_Y - SKIRT_GAP - state.hull.hull_h)


## An enemy's hit box in world art px (the dug-in's is only its turret above the concrete).
static func enemy_rect(state: TankState, aux: TankAux, e: TankEnemyState) -> Rect2:
	var top := float(TankConst.GROUND_Y - e.h)
	var def := state.content.enemy_def(TankIds.enemy_of(e.code))
	if str(def.get("hitbox", "")) == "turret":
		var hb := aux.geo.enemy_hitbox(str(def.get("sprite", "enemy_dugin")))
		if hb.size.x > 0.0:
			return Rect2(e.x_px + hb.position.x, top + hb.position.y, hb.size.x, hb.size.y)
	return Rect2(e.x_px, top, e.w, e.h)


## The Behemoth's top-left in world art px: its bogies stand on the ground line.
static func boss_origin(state: TankState, aux: TankAux) -> Vector2:
	var bottom := 0.0
	for i in 3:
		var r := aux.geo.boss_part_rect(i)
		bottom = maxf(bottom, r.end.y)
	return Vector2(state.boss.x_px, TankConst.GROUND_Y - bottom)


## Boss part `index`'s hit box in world art px.
static func boss_rect(state: TankState, aux: TankAux, index: int) -> Rect2:
	var r := aux.geo.boss_part_rect(index)
	var o := boss_origin(state, aux)
	return Rect2(o + r.position, r.size)


## An obstacle's hit box in world art px.
static func obstacle_rect(state: TankState, o: TankObstacleState) -> Rect2:
	var h := state.content.num(
		"tanks", "props.%s.h" % TankIds.obstacle_of(o.code), float(DEFAULT_PROP_H)
	)
	return Rect2(o.x_px, TankConst.GROUND_Y - h, o.w, h)


## The tier of an enemy for the auto-aim (TankTarget.TIER_*).
static func enemy_tier(e: TankEnemyState) -> int:
	match TankIds.enemy_of(e.code):
		TankIds.ENEMY_DUGIN:
			return TankTarget.TIER_DUGIN
		TankIds.ENEMY_HEAVY:
			return TankTarget.TIER_HEAVY
		TankIds.ENEMY_DESTROYER:
			return TankTarget.TIER_TELEGRAPH if e.telegraph_s > 0.0 else TankTarget.TIER_MEDIUM
		TankIds.ENEMY_MEDIUM:
			return TankTarget.TIER_MEDIUM
	return TankTarget.TIER_LIGHT


## Rebuilds aux.targets and the two flags the stations read (some target stands on screen; some
## enemy does).
static func build(state: TankState, aux: TankAux) -> void:
	aux.targets.clear()
	aux.any_target = false
	aux.enemy_in_range = false
	var cam := state.camera_x()
	for e in state.enemies:
		var t := TankTarget.new()
		t.id = e.id
		t.kind = TankTarget.KIND_ENEMY
		t.tier = enemy_tier(e)
		t.rect = enemy_rect(state, aux, e)
		t.vel = Vector2(float(aux.enemy_vx.get(e.id, 0.0)), 0.0)
		t.enemy = e
		aux.targets.append(t)
		if on_screen(t.rect, cam):
			aux.enemy_in_range = true
			aux.any_target = true
	var b := state.boss
	if b.phase == TankIds.BOSS_PHASE_1 or b.phase == TankIds.BOSS_PHASE_2:
		for i in TankBossState.PART_COUNT:
			var hp := b.turret_hp if i == TankBossState.TURRET_PART else b.bogie_hp[i]
			if hp <= 0.0 or (i == TankBossState.TURRET_PART and b.phase != TankIds.BOSS_PHASE_2):
				continue
			var t := TankTarget.new()
			t.id = TankBossState.part_id(i)
			t.kind = TankTarget.KIND_BOSS
			t.part = i
			t.tier = (
				TankTarget.TIER_HEAVY if i == TankBossState.TURRET_PART else TankTarget.TIER_DUGIN
			)
			t.rect = boss_rect(state, aux, i)
			aux.targets.append(t)
			aux.enemy_in_range = true
			aux.any_target = true
	for o in state.obstacles:
		if o.cleared:
			continue
		var type := TankIds.obstacle_of(o.code)
		if type == TankIds.OBST_TANK_TRAPS:
			continue
		var t := TankTarget.new()
		t.id = o.id
		t.kind = TankTarget.KIND_OBSTACLE
		t.obstacle = o
		t.rect = obstacle_rect(state, o)
		t.drill = type == TankIds.OBST_DRILL_WRECK
		t.tier = TankTarget.TIER_DRILL if t.drill else TankTarget.TIER_OBSTACLE
		aux.targets.append(t)
		if not t.drill and on_screen(t.rect, cam):
			aux.any_target = true


## Whether a box is at least partly on the 640-wide screen.
static func on_screen(r: Rect2, camera_x: float) -> bool:
	return r.end.x > camera_x and r.position.x < camera_x + float(TankConst.SCREEN_W)


## Whether the gun may engage `t`: on screen, except for the Behemoth's parts (the rear bogie of a
## 320 px hull can stand past the right edge and still be in range).
static func engageable(t: TankTarget, camera_x: float) -> bool:
	return t.kind == TankTarget.KIND_BOSS or on_screen(t.rect, camera_x)


## The target with entity id `id` (boss parts negative), or null.
static func by_id(aux: TankAux, id: int) -> TankTarget:
	for t in aux.targets:
		if t.id == id:
			return t
	return null

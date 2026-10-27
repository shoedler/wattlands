class_name TankAutopilot
extends RefCounted
## Autopilot (brief 2.5): the game choices a bot, an Autopilot human, a human still on the
## fallback or a reserve station makes. Owner: module.
##
## The defaults already play every station with no input (the diesel drives on watts and digs in,
## auto-aim aims and fires, the boiler latches a heavy shell at 100%, the auto-lever runs the
## Bulwark); intents() adds only the gunner's two extra jobs:
##   - rear traverses (for rear enemies the main gun can reach; it cannot reach a rear light, which
##     breaks off after its linger_s): the main turret faces right or left, and a traverse flips it. It flips when
##     nothing is in range on the side it faces and something is on the other side, and flips
##     back to the front once the rear is clear (no flip while the current side still has a
##     target, so a mixed fight never makes it flip-flop); asked for twice a second at most;
##   - obstacle shots: with no enemy in range anywhere, the turret facing front and the gun
##     loaded, a wire or wreck barricade that blocks the road is targeted (a target cycle, at most
##     once a second) and shot once the gun points at it.
##   - free roam (brief 2.10): the driver (the diesel or the Bulwark) turns the tank round once it
##     has stood valley.json turn.autopilot_wait_s (3 s) at the turning place ahead.
## It never latches (no early latch), never moves the Bulwark's lever by hand, never sprints (so it
## never evades) or Overpressures and never changes effort (BRIEF 3.5): the steam engine and the
## arc generator get nothing (the bow guns fire on their own), the diesel only its free-roam turn.
## Every intent it returns is tagged "auto": 1 (TankIntents.auto) so it never ends a human's
## fallback; the module filters them
## through the same ownership and 5-a-second rules as a rider's own.

## An enemy counts as in range while any of it is this far inside the screen's edges.
const EDGE_MARGIN_PX := 4.0
## A target cycle toward a blocking obstacle at most once in this many ticks.
const RETARGET_TICKS := 20
## A traverse or a shot is asked for at most once in this many ticks (2 a second), so a request
## the rules decline (a lever elsewhere, a breech still closing) never eats the 5-a-second budget.
const ASK_EVERY_TICKS := 10
## The aim tolerance used when the content does not give gun.aim_tol_deg.
const DEFAULT_AIM_TOL_DEG := 0.5
## Obstacle types the Autopilot clears: they stop the tank. Tank traps are shoved aside by the
## dozer blade and the depot's drill wrecks belong to the scripted drills.
const SHOT_OBSTACLES: Array[String] = [TankIds.OBST_WIRE, TankIds.OBST_WRECK]


## This tick's Autopilot intents for the rider `peer` (wire form, before normalize()).
static func intents(state: TankState, peer: int) -> Array:
	if state == null:
		return []
	var rider := state.rider(peer)
	if rider == null:
		return []
	var turn := roam_turn(state, rider)
	if not turn.is_empty():
		return turn
	if not is_gunner(rider.engine):
		return []
	if state.in_cooldown() or state.seg.seg == TankIds.SEG_NONE:
		return []
	if state.all_afk or state.hull.breakdown:
		return []
	var flip := _traverse(state)
	if not flip.is_empty():
		return flip if state.tick % ASK_EVERY_TICKS == 0 else []
	return _obstacle_shot(state)


## Free roam: the driver's turn at the turning place ahead, once the tank has stood there
## turn.autopilot_wait_s (asked twice a second at most, while a turn may start).
static func roam_turn(state: TankState, rider: TankRiderState) -> Array:
	var r := state.roam
	if not r.active or r.at_end == 0 or state.all_afk:
		return []
	if rider.engine != TankIds.ENGINE_DIESEL and rider.engine != TankIds.ENGINE_BULWARK:
		return []
	var wait := 3.0
	if state.content != null:
		wait = state.content.num("valley", "turn.autopilot_wait_s", 3.0)
	if r.end_s < wait - 1e-6 or not TankRoam.can_turn(state):
		return []
	if state.tick % ASK_EVERY_TICKS != 0:
		return []
	return [TankIntents.auto(TankIds.INTENT_TURN)]


## True for the engines that work the main gun: the dynamo and the Bulwark's gearbox diesel.
static func is_gunner(engine: String) -> bool:
	return engine == TankIds.ENGINE_DYNAMO or engine == TankIds.ENGINE_BULWARK


## {ahead, behind}: the live enemies in range on each side (the Behemoth counts ahead while a
## part of it stands). Rear lights are out of the main gun's reach: not counted.
static func enemies_in_range(state: TankState) -> Dictionary:
	var cam := state.camera_x()
	var lo := cam + EDGE_MARGIN_PX
	var hi := cam + float(TankConst.SCREEN_W) - EDGE_MARGIN_PX
	var ahead := 0
	var behind := 0
	for e in state.enemies:
		if e.mode == TankIds.EM_DEAD or e.hp <= 0.0:
			continue
		if e.x_px + maxf(float(e.w), 1.0) < lo or e.x_px > hi:
			continue
		if e.side < 0:
			# The main gun cannot reach a rear light (24 px show over the hull's rear; ADR G1
			# rules engines 11): a traverse for it only burns bank and pauses the auto-aim.
			if TankIds.enemy_of(e.code) != TankIds.ENEMY_LIGHT:
				behind += 1
		else:
			ahead += 1
	if (
		(state.boss.phase == TankIds.BOSS_PHASE_1 or state.boss.phase == TankIds.BOSS_PHASE_2)
		and state.boss.x_px < hi
	):
		ahead += 1
	return {"ahead": ahead, "behind": behind}


static func _traverse(state: TankState) -> Array:
	var hull := state.hull
	if hull.traverse_s > 0.0:
		return []
	var seen := enemies_in_range(state)
	var facing_n := int(seen["ahead"] if hull.facing == TankIds.FACE_RIGHT else seen["behind"])
	var other_n := int(seen["behind"] if hull.facing == TankIds.FACE_RIGHT else seen["ahead"])
	if facing_n > 0:
		return []
	if other_n > 0 or hull.facing == TankIds.FACE_LEFT:
		return [TankIntents.auto(TankIds.INTENT_TRAVERSE)]
	return []


static func _obstacle_shot(state: TankState) -> Array:
	var hull := state.hull
	if hull.facing != TankIds.FACE_RIGHT or hull.traverse_s > 0.0:
		return []
	var seen := enemies_in_range(state)
	if int(seen["ahead"]) + int(seen["behind"]) > 0:
		return []
	var ob := _blocking_obstacle(state)
	if ob == null:
		return []
	if hull.target_id != ob.id:
		if state.tick % RETARGET_TICKS == 0:
			return [{"k": TankIds.INTENT_TARGET, "d": TankIds.TARGET_NEXT, "auto": 1}]
		return []
	var tol := DEFAULT_AIM_TOL_DEG
	if state.content != null:
		tol = state.content.num("tanks", "gun.aim_tol_deg", DEFAULT_AIM_TOL_DEG)
	if (
		hull.loaded != TankIds.SHELL_NONE
		and hull.breech_s <= 0.0
		and state.tick % ASK_EVERY_TICKS == 0
	):
		if absf(hull.elev_deg - hull.elev_target_deg) <= tol:
			return [TankIntents.auto(TankIds.INTENT_FIRE)]
	return []


## The nearest uncleared wire or wreck ahead of the hull that is on screen, or null.
static func _blocking_obstacle(state: TankState) -> TankObstacleState:
	var front := state.hull.x_px + float(state.hull.hull_w)
	var hi := state.camera_x() + float(TankConst.SCREEN_W)
	var best: TankObstacleState = null
	for ob in state.obstacles:
		if ob.cleared or not SHOT_OBSTACLES.has(TankIds.obstacle_of(ob.code)):
			continue
		if ob.x_px + float(ob.w) < front or ob.x_px > hi:
			continue
		if best == null or ob.x_px < best.x_px:
			best = ob
	return best

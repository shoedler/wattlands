class_name TankAutopilot
extends RefCounted
## Autopilot (brief 2.5): the game choices a bot, an Autopilot human, a human still on the
## fallback or a reserve station makes. Owner: module.
##
## The defaults already play every seat with no input (Drive drives on watts and digs in, auto-aim
## chambers, lays and fires, the Loader stows a heavy shell at 100%, the bow guns fire on cadence);
## intents() adds automatic seating (v3) and the gunner's two extra jobs:
##   - automatic seating (v3 brief "Seat choice and switching"): a rider the Autopilot plays (a bot,
##     an Autopilot human, a human on the fallback; never one on reserve) asks for a seat once its
##     minimum stay is over (TankSeats.auto_stay_s), at most once a second. Solo, the solo loop
##     (seat_wanted_solo): Drive while no target is in range; the Loader when a target comes and
##     the rack is not full, until it is full; the Gun while the rack holds shells and a target is
##     in range; the Secondaries when only light targets (and barricades) are within the bow guns'
##     range. Crews of 2-4 (seat_wanted_crew): the Autopilot's riders fill the most needed seats
##     (seat_needs: by the situation, ties in TankIds.SEATS order Drive, Gun, Loader, Lights,
##     Secondaries) around the riders who play their own seat. 0.3.1: no seat lock; every stay
##     is at least 30 s solo and 60 s in a crew (TankSeats.auto_stay_s), so nothing thrashes;
##   - rear traverses (for rear enemies the main gun can reach; it cannot reach a rear light, which
## breaks off after its linger_s): the main turret faces right or left, and a traverse flips it. It
## flips when
##     nothing is in range on the side it faces and something is on the other side, and flips
##     back to the front once the rear is clear (no flip while the current side still has a
##     target, so a mixed fight never makes it flip-flop); asked for twice a second at most;
##   - obstacle shots: with no enemy in range anywhere, the turret facing front and the gun
##     loaded, a wire or wreck barricade that blocks the road is targeted (a target cycle, at most
##     once a second) and shot once the gun points at it.
##   - free roam (brief 2.10): the Drive rider turns the tank round once it
##     has stood valley.json turn.autopilot_wait_s (3 s) at the turning place ahead.
## It never latches (no early latch), never sprints (so it never evades) or Overpressures and never
## changes effort (BRIEF 3.5): a seat move replans the rider's effort for the new seat from the
## mission's own tables (TankSeatPlan), the same plans a rider picking the seat gets. The Loader,
## Lights and Secondaries get nothing else, Drive only its free-roam turn.
## Every intent it returns is tagged "auto": 1 (TankIntents.auto) so it never ends a human's
## fallback; the module filters them
## through the same ownership and 5-a-second rules as a rider's own.

## An enemy counts as in range while any of it is this far inside the screen's edges.
const EDGE_MARGIN_PX := 4.0
## A target cycle toward a blocking obstacle at most once in this many ticks.
const RETARGET_TICKS := 20
## A traverse or a shot is asked for at most once in this many ticks (2 a second), so a request
## the rules decline (a breech still closing) never eats the 5-a-second budget.
const ASK_EVERY_TICKS := 10
## The aim tolerance used when the content does not give gun.aim_tol_deg.
const DEFAULT_AIM_TOL_DEG := 0.5
## Obstacle types the Autopilot clears: they stop the tank. Tank traps are shoved aside by the
## dozer blade and the depot's drill wrecks belong to the scripted drills.
const SHOT_OBSTACLES: Array[String] = [TankIds.OBST_WIRE, TankIds.OBST_WRECK]
## A seat is asked for at most once in this many ticks (1 a second).
const SEAT_EVERY_TICKS := 20
## A crew rider moves only to a seat this much more needed than its own (no dithering).
## The solo loop goes from Drive straight to the Gun with this many shells (rack and chamber).
const SOLO_GUN_FIRST := 2
const SEAT_MARGIN := 0.5


## This tick's Autopilot intents for the rider `peer` (wire form, before normalize()).
static func intents(state: TankState, peer: int) -> Array:
	if state == null:
		return []
	var rider := state.rider(peer)
	if rider == null:
		return []
	var seat := seat_intent(state, rider)
	if not seat.is_empty():
		return [seat]
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
	if rider.engine != TankIds.ENGINE_DIESEL:
		return []
	var wait := 3.0
	if state.content != null:
		wait = state.content.num("valley", "turn.autopilot_wait_s", 3.0)
	if r.end_s < wait - 1e-6 or not TankRoam.can_turn(state):
		return []
	if state.tick % ASK_EVERY_TICKS != 0:
		return []
	return [TankIntents.auto(TankIds.INTENT_TURN)]


## True for the engine that works the main gun: the dynamo (the Gun seat).
static func is_gunner(engine: String) -> bool:
	return engine == TankIds.ENGINE_DYNAMO


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


# --- Automatic seating (v3) ------------------------------------------------------------------------


## The rider's automatic seat move this tick: {"k": "seat", "to": seat, "auto": 1}, or {} (on
## reserve, in the cool-down, inside its minimum stay (TankSeats.auto_stay_s: no seat lock since
## 0.3.1, but no thrashing either), a fight move its trainer could not follow at once or that
## would switch its trainer's mode in a warm-up segment, or happy where it sits).
static func seat_intent(state: TankState, rider: TankRiderState) -> Dictionary:
	if rider.afk or not rider.connected:
		return {}
	if state.tick % SEAT_EVERY_TICKS != 0 or state.in_cooldown() or state.all_afk:
		return {}
	if state.seg.seg == TankIds.SEG_NONE:
		return {}
	if TankSeats.stay_s(state, rider.peer) < TankSeats.auto_stay_s(state) - 1e-6:
		return {}
	var ri: TankRiderInput = TankAux.of(state).seat_input.get(rider.peer)
	# In a checkpoint, or once the segment's objective is done ("Regroup" until it ends), the rider
	# takes the seat the next fight segment wants (its trainer follows there). In a fight, only a move
	# its trainer follows at once (TankSeats.follows_now): a switch it would wait for buys nothing.
	var sit := situation(state)
	var seg := state.seg.seg
	# The solo rider's last minute before a checkpoint goes to the next segment's seat (it starts
	# the Advance driving), unless the Gun has shells to fire at a target now.
	var last_minute := (
		state.riders.size() == 1
		and ri != null
		and TankSeats.checkpoint_next(ri)
		and ri.phase_remaining_s < TankSeats.auto_stay_s(state) + 1.0
		and seat_wanted_solo(state, rider, sit) != TankIds.ENGINE_DYNAMO
	)
	var at_end := (
		(state.seg.objective_done and state.seg.open_ended)
		or last_minute
		or state.seg.seg == TankIds.SEG_CHECKPOINT
	)
	if state.riders.size() > 1 and not _crew_may_move(state, at_end):
		return {}
	if at_end:
		seg = next_fight_segment(state)
		sit = expected(state, seg)
	var want := (
		seat_wanted_solo(state, rider, sit, seg)
		if state.riders.size() == 1
		else seat_wanted_crew(state, rider, sit, seg)
	)
	if want == "" or want == rider.engine:
		return {}
	var st := state.station(want)
	if st == null or not st.is_empty():
		return {}
	if not at_end and not TankSeats.follows_now(state, rider.peer, want):
		return {}
	if not at_end and _switches_in_warmup(state, ri, want):
		return {}
	var out := TankIntents.seat(want, TankIds.VIA_AUTO)
	out["auto"] = 1
	return out


## True when moving to `engine` would switch the rider's trainer ERG <-> SIM inside a warm-up
## segment (the depot, the drill's skirmish): the automatic seating keeps the trainer's mode through
## a warm-up (the drill allows a rider one switch: its checkpoint). A human may still move.
static func _switches_in_warmup(state: TankState, ri: TankRiderInput, engine: String) -> bool:
	if ri == null or not ri.in_warmup():
		return false
	var mode := str(TankAux.of(state).trainer_mode.get(ri.peer, ri.phase_mode))
	return TankSeats.seat_mode(state, engine) != mode


## A crew's automatic riders hold their seats through a segment's opening (0.3.1, the v3 timing the
## crews are tuned on): never in a checkpoint, not in a segment's first AUTO_STAY_S, and in a fight
## not before the segment's own min_s (`at_end`: planning the next segment once the objective is
## done).
static func _crew_may_move(state: TankState, at_end: bool) -> bool:
	if state.seg.seg == TankIds.SEG_CHECKPOINT:
		return false
	if state.seg.elapsed_s < TankConst.AUTO_STAY_S - 1e-6:
		return false
	return at_end or (state.seg.open_ended and state.seg.elapsed_s >= state.seg.min_s - 1e-6)


## The solo loop (brief v3 "Automatic seating"), from the seat the rider is on, for a segment of
## type `seg` (default the current one). "In range" is the gun's reach now: the solo rider never
## mans the Lights, so the headlight's range. Timing (v3 solo balance): in an Advance the rider
## leaves Drive for one stay at most (one stay is all an Advance's time bound leaves beside the
## drive to the halt line); after it, or when the Advance began on another seat, it drives on
## to the halt line.
static func seat_wanted_solo(
	state: TankState, rider: TankRiderState, sit: Dictionary = {}, seg: String = ""
) -> String:
	if sit.is_empty():
		sit = situation(state)
	if seg == "":
		seg = state.seg.seg
	var here := seg == state.seg.seg
	if here and seg == TankIds.SEG_ADVANCE and _advance_stay_spent(state, rider):
		return TankIds.ENGINE_DIESEL
	if not bool(sit["near"]):
		return TankIds.ENGINE_DIESEL
	if bool(sit["only_light"]):
		return TankIds.ENGINE_FEED
	var rack := int(sit["rack"])
	var shells := int(sit["shells"])
	match rider.engine:
		TankIds.ENGINE_STEAM:
			return TankIds.ENGINE_STEAM if rack < TankConst.RACK_MAX else TankIds.ENGINE_DYNAMO
		TankIds.ENGINE_DYNAMO:
			return TankIds.ENGINE_DYNAMO if shells > 0 else TankIds.ENGINE_STEAM
	# From Drive (or the Secondaries): a rack with SOLO_GUN_FIRST shells or more goes to the Gun at
	# once (a 60 s stay on the Loader would only top it up), else the Loader fills it first.
	if shells >= SOLO_GUN_FIRST or rack >= TankConst.RACK_MAX:
		return TankIds.ENGINE_DYNAMO
	return TankIds.ENGINE_STEAM


## True when rider `rider` sat somewhere other than Drive in the current Advance: it sits there now,
## or it did earlier in this segment (TankAux.off_drive_seg).
static func _advance_stay_spent(state: TankState, rider: TankRiderState) -> bool:
	if rider.engine != TankIds.ENGINE_DIESEL:
		return true
	return int(TankAux.of(state).off_drive_seg.get(rider.peer, -1)) == state.seg.segment_index


## A crew rider the Autopilot seats: the seats the Autopilot's riders should hold are the most
## needed ones (seat_needs) that no self-playing rider holds, as many as it has riders; one outside
## them moves to the most needed of them that is empty, when that is SEAT_MARGIN more needed than
## its own seat.
static func seat_wanted_crew(
	state: TankState, rider: TankRiderState, sit: Dictionary = {}, seg: String = ""
) -> String:
	var needs := seat_needs(state, sit, seg)
	var free: Array[String] = []
	var autos := 0
	for r in state.riders:
		if r.fallback or r.autopilot or r.is_bot:
			autos += 1
	for engine in TankIds.SEATS:
		var st := state.station(engine)
		if st == null:
			continue
		var holder := state.rider_at(st.slot) if st.slot >= 0 else null
		if holder == null or holder.fallback or holder.autopilot or holder.is_bot:
			free.append(engine)
	var ranked := rank_seats(free, needs)
	var wanted := ranked.slice(0, autos)
	if wanted.has(rider.engine):
		return rider.engine
	var own := float(needs.get(rider.engine, 0.0))
	for engine: String in wanted:
		var st := state.station(engine)
		if st != null and st.is_empty() and float(needs[engine]) >= own + SEAT_MARGIN:
			return engine
	return rider.engine


## `seats` most needed first (ties in TankIds.SEATS order).
static func rank_seats(seats: Array[String], needs: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for engine in TankIds.SEATS:
		if not seats.has(engine):
			continue
		var at := out.size()
		for i in out.size():
			if float(needs[engine]) > float(needs[out[i]]) + 1e-9:
				at = i
				break
		out.insert(at, engine)
	return out


## How much each seat is needed now (seat id -> a score, higher first): Drive to move on (5) on a
## road segment until its objective is done, fight or not (the enemies keep station with the tank),
## or to dig in at a gun line (3.2: kept manned there, so the next Advance starts with a driver;
## a crew's stay leaves no time to move one there between the segments); the Gun in a fight with
## shells to fire or a Loader working (4.5 with a target the auto-aim can lay on now, 2 without: a
## light tank inside the gun's depression limit, or one past the headlight in the dark); the Loader
## (4 in a fight, 3 on the road) while the rack has room, 3 in a fight with the rack full (the fight
## will need it: only the Secondaries' 3.5 or more take its rider); the Lights (3.4) in a fight while the gun
## can fire (lit, it reaches the whole field with half the dark dispersion) or an enemy stands
## beyond the headlight; the Secondaries with a target in the bow guns' range (3.5, a rider on the
## Lights stays: 3.5 is not 0.5 more; 4.6 when the main gun has nothing to lay on).
static func seat_needs(state: TankState, sit: Dictionary = {}, seg: String = "") -> Dictionary:
	if sit.is_empty():
		sit = situation(state)
	if seg == "":
		seg = state.seg.seg
	var fight := bool(sit["targets"])
	var road := [TankIds.SEG_ADVANCE, TankIds.SEG_SKIRMISH, TankIds.SEG_ROAM, TankIds.SEG_DEPOT]
	var drive := 0.5
	if seg == TankIds.SEG_GUN_LINE:
		drive = 3.2
	elif road.has(seg) and not state.seg.objective_done:
		drive = 5.0
	var loader := state.station(TankIds.ENGINE_STEAM)
	var loading := loader != null and not loader.is_empty()
	var gun := 0.3
	if fight and (int(sit["shells"]) > 0 or loading):
		gun = 4.5 if bool(sit["gun"]) else 2.0
	elif fight:
		gun = 1.0
	var feed := 0.1
	if bool(sit["bow"]):
		feed = 3.5 if bool(sit["gun"]) else 4.6
	var steam := 0.2
	if int(sit["rack"]) < TankConst.RACK_MAX:
		steam = 4.0 if fight else 3.0
	elif fight:
		steam = 3.0
	var arc := 0.1
	if bool(sit["far"]) or (fight and (int(sit["shells"]) > 0 or loading)):
		arc = 3.4
	elif fight:
		arc = 1.0
	return {
		TankIds.ENGINE_DIESEL: drive,
		TankIds.ENGINE_DYNAMO: gun,
		TankIds.ENGINE_STEAM: steam,
		TankIds.ENGINE_ARC: arc,
		TankIds.ENGINE_FEED: feed,
		TankIds.ENGINE_REPAIR: 0.05,
	}


## What the seating reads (the latest target list, TankAux.targets): {"targets": something the main
## gun could engage with the searchlights lit (an enemy or Behemoth part on screen, rear lights
## aside, or a barricade blocking the road), "near": one of them within the gun's reach now
## (TankAim.in_reach: the headlight's range while the searchlights are dark), "only_light": something
## in the bow guns' range and every target there a light one (light_target), "bow": something in the bow
## guns' range, "far": an enemy beyond the headlight's range, "gun": the auto-aim can lay on a
## target now (TankAim.pick), "rack": shells in the rack, "shells": the rack plus a chambered round}.
static func situation(state: TankState) -> Dictionary:
	var aux := TankAux.of(state)
	var cam := state.camera_x()
	var c := state.content
	var lo := c.num("tanks", "bow.min_px", 40.0) if c != null else 40.0
	var hi := c.num("tanks", "bow.max_px", 220.0) if c != null else 220.0
	var reach := c.num("tanks", "arc.dark_range_px", 260.0) if c != null else 260.0
	var light_code := TankIds.enemy_code(TankIds.ENEMY_LIGHT)
	var targets := false
	var near := false
	var only_light := true
	var bow := false
	var far := false
	for t in aux.targets:
		if t.drill or not TankShells.collidable(t) or not TankTargets.engageable(t, cam):
			continue
		var enemy := t.kind == TankTarget.KIND_ENEMY
		if t.kind == TankTarget.KIND_OBSTACLE and not TankDrive.blocks(t.obstacle):
			continue
		if enemy and t.enemy.side < 0 and t.enemy.code == light_code:
			continue
		targets = true
		near = near or TankAim.in_reach(state, t)
		var d := TankBow.distance(state, t)
		var ahead := not enemy or t.enemy.side > 0
		var in_bow := ahead and d >= lo - 1e-6 and d <= hi + 1e-6
		bow = bow or in_bow
		if in_bow and not light_target(state, t):
			only_light = false
		if t.kind != TankTarget.KIND_OBSTACLE and d > reach:
			far = true
	var st := state.station(TankIds.ENGINE_STEAM) as TankSteamState
	var rack := st.rack if st != null else 0
	var chambered := 1 if state.hull.loaded != TankIds.SHELL_NONE else 0
	var elev: Array[float] = [0.0]
	var face: Array[int] = [state.hull.facing]
	var gun := targets and TankAim.pick(state, aux, false, elev, face) != null
	return {
		"targets": targets,
		"near": near,
		"gun": gun,
		"only_light": bow and only_light,
		"bow": bow,
		"far": far,
		"rack": rack,
		"shells": rack + chambered,
	}


## A light target (the solo loop's Secondaries rule): one the bow guns hurt in full, a barricade or
## an enemy whose enemies.json light_mult is 1 or more (light tanks and dug-in turrets).
static func light_target(state: TankState, t: TankTarget) -> bool:
	if t.kind == TankTarget.KIND_OBSTACLE:
		return true
	if t.kind != TankTarget.KIND_ENEMY or state.content == null:
		return false
	var def := state.content.enemy_def(TankIds.enemy_of(t.enemy.code))
	return float(def.get("light_mult", 0.0)) >= 1.0 - 1e-9


## The next segment with work in it after the current one (a checkpoint is skipped: nobody moves
## there): its type, or "" after the last.
static func next_fight_segment(state: TankState) -> String:
	if state.content == null:
		return ""
	var segs := state.content.segments()
	var i := state.seg.segment_index + 1
	while i < segs.size() and str(segs[i].get("type", "")) == TankIds.SEG_CHECKPOINT:
		i += 1
	return str(segs[i].get("type", "")) if i < segs.size() else ""


## The situation the seating expects at the start of a segment of type `seg`: a fight at a gun line
## or the boss (targets in reach and past the headlight), the open road in an Advance; the rack as
## it is now. For a solo rider a gun line reads its enemy list (what a crew of 1 meets of it,
## TankEncounters.crew_counts): "bow" when one stands inside the bow guns' range, "only_light" when
## every one is a light target there (dug-in turrets).
static func expected(state: TankState, seg: String) -> Dictionary:
	var sit := situation(state)
	var fight := seg == TankIds.SEG_GUN_LINE or seg == TankIds.SEG_BOSS
	sit["targets"] = fight
	sit["near"] = fight
	sit["far"] = fight
	sit["bow"] = false
	sit["only_light"] = false
	sit["gun"] = fight
	if seg == TankIds.SEG_GUN_LINE and state.content != null and state.riders.size() == 1:
		var i := next_fight_index(state)
		var specs: Array = state.content.segment(i).get("enemies", []) if i >= 0 else []
		var counts := TankEncounters.crew_counts(state, specs)
		var lo := state.content.num("tanks", "bow.min_px", 40.0)
		var hi := state.content.num("tanks", "bow.max_px", 220.0)
		var light := true
		var bow := false
		for k in specs.size():
			if counts[k] <= 0:
				continue
			var def := state.content.enemy_def(str(specs[k].get("enemy", "")))
			var at: Array = specs[k].get("at_px", [200])
			for n in counts[k]:
				var raw: Variant = at[mini(n, at.size() - 1)]
				var near := not (raw is String) and float(raw) >= lo and float(raw) <= hi
				bow = bow or near
				light = light and near and float(def.get("light_mult", 0.0)) >= 1.0 - 1e-9
		sit["bow"] = bow
		sit["only_light"] = bow and light
	return sit


## The index of the next segment with work in it after the current one (checkpoints skipped), or
## -1 after the last.
static func next_fight_index(state: TankState) -> int:
	if state.content == null:
		return -1
	var segs := state.content.segments()
	var i := state.seg.segment_index + 1
	while i < segs.size() and str(segs[i].get("type", "")) == TankIds.SEG_CHECKPOINT:
		i += 1
	return i if i < segs.size() else -1

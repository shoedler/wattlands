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
##     range (v4: only with an empty rack), and Repairs with the hull below 35% and no far target
##     laid. Crews of 2-4 (seat_wanted_crew): the Autopilot's riders fill the most needed seats
##     (seat_needs: by the situation, ties in TankIds.SEATS order Drive, Gun, Loader, Lights,
##     Secondaries, Repairs) around the riders who play their own seat. 0.3.1: no seat lock; every
##     stay is at least 30 s solo and 60 s in a crew (TankSeats.auto_stay_s), so nothing thrashes.
##     v4: a bot asks through TankBots instead, which adapts to the humans;
##   - obstacle shots: with no enemy in range anywhere and the gun
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

## A target cycle toward a blocking obstacle at most once in this many ticks.
const RETARGET_TICKS := 20
## A shot is asked for at most once in this many ticks (2 a second), so a request the rules decline
## (a breech still closing) never eats the 5-a-second budget.
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
## v4: the Repairs seat's need: 4.2 with the hull below HULL_LOW, 5.6 below HULL_CRITICAL (the solo
## loop's Repairs too), else almost none.
const HULL_LOW := 0.6
const HULL_CRITICAL := 0.35
const REPAIR_LOW := 4.2
const REPAIR_CRITICAL := 5.6
const REPAIR_IDLE := 0.05
## v4: the Secondaries' need while a near threat is alive.
const FEED_NEAR_THREAT := 4.7


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
	if state.all_afk or state.hull.out_of_action():
		return []
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


## The live enemies the main gun could lay on: far kinds within its range, the Behemoth while a part
## of it stands. Near threats are the Secondaries' (the main gun does not lay on them).
static func enemies_in_range(state: TankState) -> int:
	var max_range := 2500.0
	if state.content != null:
		max_range = state.content.num("tanks", "gun.far.max_range_m", max_range)
	var n := 0
	for e in state.enemies:
		if e.mode == TankIds.EM_DEAD or e.hp <= 0.0 or e.is_near():
			continue
		if e.range_m > 0.0 and e.range_m <= max_range:
			n += 1
	var b := state.boss
	var stands := b.phase == TankIds.BOSS_PHASE_1 or b.phase == TankIds.BOSS_PHASE_2
	if stands and b.range_m > 0.0:
		n += 1
	return n


static func _obstacle_shot(state: TankState) -> Array:
	var hull := state.hull
	if enemies_in_range(state) > 0:
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
	if rider.is_bot:
		return TankBots.intent(state, rider)
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
		if seg == TankIds.SEG_NONE:
			return {}  # the last fight is won: nothing but the cool-down comes, and it has no seats
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
	if (
		not at_end
		and not TankSeats.follows_now(state, rider.peer, want)
		and not _solo_shells_to_fire(state, want, sit)
	):
		return {}
	if not at_end and _switches_in_warmup(state, ri, want):
		return {}
	var out := TankIntents.seat(want, TankIds.VIA_AUTO)
	out["auto"] = 1
	return out


## True for a solo rider with rounds, a target and the Gun free in a holding action: past a hold's
## nominal end its trainer would only follow at the segment's end, but the seat lands at once and the
## clock is the fight's, so it fires instead of sitting on a full rack until max_s.
static func _solo_shells_to_fire(state: TankState, want: String, sit: Dictionary) -> bool:
	return (
		state.riders.size() == 1
		and state.seg.seg == TankIds.SEG_GUN_LINE
		and want == TankIds.ENGINE_DYNAMO
		and int(sit["shells"]) > 0
		and bool(sit["gun"])
	)


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
## done). v4: open while a near threat is alive: it lives 8-20 s, and stage 1's recon comes at about
## 40 s, so otherwise no Autopilot crew could ever man the Secondaries (the 1 s ask, the stay and the
## follows_now gate still hold). Also open while an Advance has nobody on Drive: a rider who left it in
## the hold would otherwise keep the tank standing until min_s. Free roam is one long segment with no
## opening to hold: a rider a near threat pulled off the Loader would otherwise stay away until time up.
static func _crew_may_move(state: TankState, at_end: bool) -> bool:
	if state.seg.seg == TankIds.SEG_CHECKPOINT:
		return false
	if near_threat_alive(state) or state.seg.seg == TankIds.SEG_ROAM:
		return true
	if state.seg.seg == TankIds.SEG_ADVANCE and not state.seg.objective_done:
		var drive := state.station(TankIds.ENGINE_DIESEL)
		if drive != null and drive.is_empty():
			return true
	if _gun_dry(state):
		return true
	if state.seg.elapsed_s < TankConst.AUTO_STAY_S - 1e-6:
		return false
	return at_end or (state.seg.open_ended and state.seg.elapsed_s >= state.seg.min_s - 1e-6)


## True in a fight whose Gun has nothing to fire with nobody on the Loader: a small crew that arrives
## with an empty rack would otherwise sit out the opening with an idle gun.
static func _gun_dry(state: TankState) -> bool:
	if state.seg.seg != TankIds.SEG_GUN_LINE and state.seg.seg != TankIds.SEG_BOSS:
		return false
	var loader := state.station(TankIds.ENGINE_STEAM)
	return (
		loader != null
		and loader.is_empty()
		and loader.rack <= 0
		and state.hull.loaded == TankIds.SHELL_NONE
	)


## v4: true while a recon car or a tankette is alive.
static func near_threat_alive(state: TankState) -> bool:
	for e in state.enemies:
		if e.is_near() and e.mode != TankIds.EM_DEAD and e.hp > 0.0:
			return true
	return false


## v4: the hull's share of its maximum (1 while it cannot be worked on: at 0 under a tow or broken down,
## the restart or the breakdown's own repair lifts it, not the Repairs seat).
static func _hull_share(state: TankState) -> float:
	var hull := state.hull
	if hull.out_of_action() or hull.hp_max <= 0.0:
		return 1.0
	return hull.hp / hull.hp_max


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
	if here and _hull_share(state) < HULL_CRITICAL and not bool(sit["gun"]):
		return TankIds.ENGINE_REPAIR
	if not bool(sit["near"]):
		return TankIds.ENGINE_DIESEL
	var rack := int(sit["rack"])
	var shells := int(sit["shells"])
	# v4: the Secondaries only when nothing else works: the main gun has no round to fire.
	if bool(sit["only_light"]) and shells <= 0:
		return TankIds.ENGINE_FEED
	match rider.engine:
		TankIds.ENGINE_STEAM:
			var enough := rack >= TankConst.RACK_MAX or rack >= _hits_to_clear(state)
			return TankIds.ENGINE_DYNAMO if enough else TankIds.ENGINE_STEAM
		TankIds.ENGINE_DYNAMO:
			return TankIds.ENGINE_DYNAMO if shells > 0 else TankIds.ENGINE_STEAM
	# From Drive (or the Secondaries): a rack with SOLO_GUN_FIRST shells or more goes to the Gun at
	# once (a 60 s stay on the Loader would only top it up), else the Loader fills it first.
	if shells >= SOLO_GUN_FIRST or rack >= TankConst.RACK_MAX:
		return TankIds.ENGINE_DYNAMO
	return TankIds.ENGINE_STEAM


## The heavy shells that would kill every far enemy standing, at least 1: the solo Loader stops
## filling the rack once it holds them (a hold's clock has no time for a third shell nobody needs).
## RACK_MAX when the Behemoth stands: that fight wants a full rack.
static func _hits_to_clear(state: TankState) -> int:
	if state.boss.phase != TankIds.BOSS_NONE and state.boss.phase != TankIds.BOSS_DEAD:
		return TankConst.RACK_MAX
	var dmg := maxf(state.content.num("tanks", "damage.heavy", 35.0), 1.0)
	var hits := 0
	for e in state.enemies:
		if not e.is_near() and e.mode != TankIds.EM_DEAD and e.hp > 0.0:
			hits += ceili(e.hp / dmg)
	return maxi(hits, 1)


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
## beyond the headlight; the Secondaries 4.7 while a near threat is alive, else with a barricade in
## the bow guns' range (3.5, a rider on the Lights stays: 3.5 is not 0.5 more; 4.6 when the main gun
## has nothing to lay on); Repairs by the hull (repair_need).
static func seat_needs(state: TankState, sit: Dictionary = {}, seg: String = "") -> Dictionary:
	if sit.is_empty():
		sit = situation(state)
	if seg == "":
		seg = state.seg.seg
	var fight := bool(sit["targets"])
	var road := [
		TankIds.SEG_ADVANCE,
		TankIds.SEG_SKIRMISH,
		TankIds.SEG_ROAM,
		TankIds.SEG_DEPOT,
		TankIds.SEG_HANGAR,
		TankIds.SEG_ROLLOUT
	]
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
	if bool(sit.get("near_threat", false)):
		feed = FEED_NEAR_THREAT
	elif bool(sit["bow"]):
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
		TankIds.ENGINE_REPAIR: repair_need(state),
	}


## v4: how much the Repairs seat is needed, by the hull.
static func repair_need(state: TankState) -> float:
	var share := _hull_share(state)
	if share < HULL_CRITICAL:
		return REPAIR_CRITICAL
	return REPAIR_LOW if share < HULL_LOW else REPAIR_IDLE


## What the seating reads (the latest target list, TankAux.targets): {"targets": something the main
## gun could engage with the searchlights lit (a far enemy or Behemoth part, or a barricade blocking
## the road), "near": one of them within the gun's reach now (TankAim.in_reach: the headlight's range
## while the searchlights are dark), "only_light": something in the bow guns' range and every target
## there a light one (light_target), "bow": a near threat or a barricade in the bow guns' range,
## "far": a far enemy beyond the headlight's range (arc.dark_range_m), "gun": the auto-aim can lay on
## a target now (TankAim.pick), "rack": shells in the rack, "shells": the rack plus a chambered round,
## "far_target": a far enemy or Behemoth part stands, "near_threat": a recon car or tankette is alive}.
static func situation(state: TankState) -> Dictionary:
	var aux := TankAux.of(state)
	var cam := state.camera_x()
	var c := state.content
	var lo := c.num("tanks", "bow.min_px", 40.0) if c != null else 40.0
	var hi := c.num("tanks", "bow.max_px", 220.0) if c != null else 220.0
	var reach := c.num("tanks", "arc.dark_range_px", 260.0) if c != null else 260.0
	var dark_m := c.num("tanks", "arc.dark_range_m", 2300.0) if c != null else 2300.0
	var targets := false
	var near := false
	var only_light := true
	var bow := false
	var far := false
	var far_target := false
	var near_threat := false
	for t in aux.targets:
		if t.drill:
			continue
		if t.far:
			if t.kind == TankTarget.KIND_ENEMY and t.enemy.hp <= 0.0:
				continue
			targets = true
			far_target = true
			near = near or TankAim.in_reach(state, t)
			far = far or t.range_m > dark_m
			continue
		if t.near:
			if t.enemy.hp <= 0.0:
				continue
			near_threat = true
			var dn := TankBow.distance(state, t)
			if dn >= lo - 1e-6 and dn <= hi + 1e-6:
				bow = true
				only_light = only_light and light_target(state, t)
			continue
		if not TankShells.collidable(t) or not TankTargets.engageable(t, cam):
			continue
		if t.kind == TankTarget.KIND_OBSTACLE and not TankDrive.blocks(t.obstacle):
			continue
		targets = true
		near = near or TankAim.in_reach(state, t)
		var d := TankBow.distance(state, t)
		var in_bow := d >= lo - 1e-6 and d <= hi + 1e-6
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
		"far_target": far_target,
		"near_threat": near_threat,
	}


## A light target (the solo loop's Secondaries rule): one the bow guns hurt in full, a barricade or
## an enemy whose enemies.json light_mult is 1 or more (recon cars and tankettes).
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
## or the boss (far targets in reach and past the headlight; no near threat yet: they burst from the
## bushes later), the open road in an Advance; the rack as it is now.
static func expected(state: TankState, seg: String) -> Dictionary:
	var sit := situation(state)
	var fight := seg == TankIds.SEG_GUN_LINE or seg == TankIds.SEG_BOSS
	sit["targets"] = fight
	sit["near"] = fight
	sit["far"] = fight
	sit["bow"] = false
	sit["only_light"] = false
	sit["gun"] = fight
	sit["far_target"] = fight
	sit["near_threat"] = false
	return sit

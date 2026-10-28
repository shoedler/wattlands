class_name TankBoss
extends RefCounted
## The Behemoth (brief 2.4 Enemies and Foundry Gate; owner: rules). Phase 1: while a bogie stands it
## creeps toward the tank at 2 px/s until its left edge is 120 px from the hull's front; each broken
## bogie pushes it back 24 px. Phase 2 (every bogie broken): immobile; shoot the turret, which only
## takes damage then. The main gun fires every 35-45 s (25-35 s in phase 2) after a 6 s telegraph
## (muzzle glow, "Surge to evade"); a rider who can evade holding the sprint rule 3 s inside it makes
## that shot miss (TankEvade; `evaded` turns true once one has). A secondary does 3 damage every 5 s
## at 60%. Maximum HP is the content HP x the tank's enemy_scale. Not killed when the boss segment
## ends: it withdraws.


## The boss segment starts: full health, phase 1, the first main-gun and secondary countdowns.
static func start(state: TankState, aux: TankAux, events: Array[Dictionary]) -> void:
	var c := state.content
	var def := c.boss_def()
	var b := state.boss
	var scale := c.enemy_scale(state.hull.tank)
	b.bogie_max = float(def.get("bogie_hp", 100.0)) * scale
	b.turret_max = float(def.get("turret_hp", 300.0)) * scale
	b.bogie_hp = [b.bogie_max, b.bogie_max, b.bogie_max]
	b.turret_hp = b.turret_max
	var seg := c.segment(state.seg.segment_index)
	var left_screen := float((seg.get("boss", {}) as Dictionary).get("start_left_px", 440))
	b.x_px = state.hull.x_px + left_screen - float(TankConst.REAR_SCREEN_X)
	b.evaded = false
	TankEvade.forget(aux, TankEvade.boss_shooter())
	b.telegraph_s = 0.0
	aux.boss_tele_total = 0.0
	b.main_s = _roll(state, def.get("main", {}).get("every_s", [35, 45]))
	b.secondary_s = float((def.get("secondary", {}) as Dictionary).get("every_s", 5.0))
	b.phase = TankIds.BOSS_PHASE_1
	events.append(TankEvents.boss_phase(b.phase))


static func _roll(state: TankState, span: Array) -> float:
	if state.rng == null:
		return float(span[0])
	return state.rng.randf_range(float(span[0]), float(span[1]))


## Creep, countdowns, the main gun and the secondary.
static func step(state: TankState, aux: TankAux, dt: float, events: Array[Dictionary]) -> void:
	var b := state.boss
	if b.phase != TankIds.BOSS_PHASE_1 and b.phase != TankIds.BOSS_PHASE_2:
		return
	var c := state.content
	var def := c.boss_def()
	var hull := state.hull
	if b.phase == TankIds.BOSS_PHASE_1:
		var gap := b.x_px - (hull.x_px + hull.hull_w)
		var stop := float(def.get("stop_px", 120.0))
		if gap > stop:
			b.x_px = maxf(
				b.x_px - float(def.get("creep_px_s", 2.0)) * dt, hull.x_px + hull.hull_w + stop
			)
	var origin := TankTargets.boss_origin(state, aux)
	var main: Dictionary = def.get("main", {})
	var tele := float(main.get("telegraph_s", 6.0))
	var need := c.num("tanks", "evade.boss_hold_s", 3.0)
	b.main_s -= dt
	if b.main_s > 0.0 and b.main_s <= tele:
		if b.telegraph_s <= 0.0:
			aux.boss_tele_total = b.main_s
		b.telegraph_s = b.main_s
		if TankEvade.accumulate(state, aux, TankEvade.boss_shooter(), dt, need):
			b.evaded = true
	elif b.main_s <= 0.0:
		var miss := TankEvade.resolve(
			state, aux, TankEvade.boss_shooter(), TankIds.BOSS_CODE, need, events
		)
		var from := origin + aux.geo.boss_muzzle()
		TankEnemies.launch(
			state,
			aux,
			from,
			TankIds.SHELL_BOSS_MAIN,
			float(main.get("damage", 20.0)),
			float(main.get("hit", 0.85)),
			miss,
			0,
			TankIds.BOSS_CODE,
			events
		)
		var key := "every_s" if b.phase == TankIds.BOSS_PHASE_1 else "every_s_phase2"
		b.main_s = _roll(state, main.get(key, [35, 45]))
		b.telegraph_s = 0.0
		b.evaded = false
		aux.boss_tele_total = 0.0
	var sec: Dictionary = def.get("secondary", {})
	b.secondary_s -= dt
	if b.secondary_s <= 0.0:
		b.secondary_s = float(sec.get("every_s", 5.0))
		TankEnemies.launch(
			state,
			aux,
			origin + aux.geo.boss_secondary_muzzle(),
			TankIds.SHELL_ENEMY,
			float(sec.get("damage", 3.0)),
			float(sec.get("hit", 0.6)),
			false,
			0,
			TankIds.BOSS_CODE,
			events
		)


## A bogie broke: the Behemoth is pushed back; the last one ends phase 1.
static func bogie_broken(state: TankState, events: Array[Dictionary]) -> void:
	var b := state.boss
	b.x_px += float(state.content.boss_def().get("pushback_px", 24.0))
	if b.bogies_left() == 0 and b.phase == TankIds.BOSS_PHASE_1:
		b.phase = TankIds.BOSS_PHASE_2
		events.append(TankEvents.boss_phase(b.phase))


## The turret fell: the Behemoth is dead (credited to `slot`).
static func die(state: TankState, aux: TankAux, slot: int, events: Array[Dictionary]) -> void:
	var b := state.boss
	b.phase = TankIds.BOSS_DEAD
	b.telegraph_s = 0.0
	b.evaded = false
	aux.boss_tele_total = 0.0
	TankEvade.forget(aux, TankEvade.boss_shooter())
	state.score.behemoth_killed = true
	state.score.kills[TankIds.BOSS_CODE] += 1
	state.score.crew_kills += 1
	events.append(
		TankEvents.kill(
			TankBossState.part_id(TankBossState.TURRET_PART),
			TankIds.BOSS_CODE,
			TankEvents.BY_SHELL,
			slot
		)
	)
	events.append(TankEvents.boss_phase(b.phase))


## The boss segment ended with the Behemoth alive: it withdraws.
static func withdraw(state: TankState, aux: TankAux, events: Array[Dictionary]) -> void:
	var b := state.boss
	if b.phase != TankIds.BOSS_PHASE_1 and b.phase != TankIds.BOSS_PHASE_2:
		return
	b.phase = TankIds.BOSS_WITHDRAWN
	b.telegraph_s = 0.0
	b.evaded = false
	aux.boss_tele_total = 0.0
	TankEvade.forget(aux, TankEvade.boss_shooter())
	events.append(TankEvents.boss_phase(b.phase))

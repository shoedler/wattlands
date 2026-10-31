class_name TankBoss
extends RefCounted
## The Behemoth (brief 2.4 Enemies and Foundry Gate; v4: the far frame; owner: rules). Phase 1: while a
## bogie stands it creeps toward the tank at boss.far.creep_mps until boss.far.stop_m; each broken bogie
## pushes it back pushback_m. Phase 2 (every bogie broken): immobile; shoot the turret, which only takes
## damage then. The main gun fires every 35-45 s (25-35 s in phase 2) after its telegraph (muzzle glow,
## "Surge to evade"; x difficulty.telegraph); a rider who can evade holding the sprint rule 3 s inside
## the telegraph and the shell's flight makes that shot miss (TankEvade; `evaded` turns true once one
## has, until it lands). A secondary fires every 5 s. Every hit chance x difficulty.accuracy, capped.
## Maximum HP is the content HP x the tank's enemy_scale x difficulty.hp. Not killed when the boss
## segment ends: it withdraws.


## The boss segment starts: full health, phase 1, the first main-gun and secondary countdowns.
static func start(state: TankState, aux: TankAux, events: Array[Dictionary]) -> void:
	var c := state.content
	var def := c.boss_def()
	var b := state.boss
	var scale := c.enemy_scale(state.hull.tank) * TankDifficulty.mult(state, "hp")
	var far: Dictionary = def.get("far", {})
	b.bogie_max = float(def.get("bogie_hp", 100.0)) * scale
	b.turret_max = float(def.get("turret_hp", 300.0)) * scale
	b.bogie_hp = [b.bogie_max, b.bogie_max, b.bogie_max]
	# v3 solo balance: a small crew meets a Behemoth with its far bogies (or all) already wrecked.
	for i in range(c.boss_bogies(state.crew), b.bogie_hp.size()):
		b.bogie_hp[i] = 0.0
	b.turret_hp = b.turret_max
	var seg := c.segment(state.seg.segment_index)
	var left_screen := float((seg.get("boss", {}) as Dictionary).get("start_left_px", 440))
	b.x_px = state.hull.x_px + left_screen - float(TankConst.REAR_SCREEN_X)
	b.range_m = float(far.get("start_m", 1450.0))
	aux.boss_rate_mps = 0.0
	b.evaded = false
	TankEvade.forget(aux, TankEvade.boss_shooter())
	b.telegraph_s = 0.0
	aux.boss_tele_total = 0.0
	b.main_s = _roll(state, def.get("main", {}).get("every_s", [35, 45]))
	b.secondary_s = float((def.get("secondary", {}) as Dictionary).get("every_s", 5.0))
	b.phase = TankIds.BOSS_PHASE_1
	events.append(TankEvents.boss_phase(b.phase))
	if b.bogies_left() == 0:
		# Every bogie wrecked: it stands immobile at its stop line from the start and its turret
		# fights (phase 2).
		b.range_m = float(far.get("stop_m", 1000.0))
		b.main_s = _roll(state, def.get("main", {}).get("every_s_phase2", [25, 35]))
		b.phase = TankIds.BOSS_PHASE_2
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
	var def := state.content.boss_def()
	var far: Dictionary = def.get("far", {})
	aux.boss_rate_mps = 0.0
	if b.phase == TankIds.BOSS_PHASE_1:
		var stop := float(far.get("stop_m", 1000.0))
		if b.range_m > stop:
			var creep := float(far.get("creep_mps", 1.5))
			b.range_m = maxf(b.range_m - creep * dt, stop)
			aux.boss_rate_mps = -creep
	var main: Dictionary = def.get("main", {})
	var tele := float(main.get("telegraph_s", 6.0)) * TankDifficulty.mult(state, "telegraph")
	var need := TankEvade.need_s(state, TankIds.SHELL_BOSS_MAIN)
	b.main_s -= dt
	if b.main_s > 0.0 and b.main_s <= tele:
		if b.telegraph_s <= 0.0:
			aux.boss_tele_total = b.main_s
		b.telegraph_s = b.main_s
		if TankEvade.accumulate(state, aux, TankEvade.boss_shooter(), dt, need):
			b.evaded = true
	elif b.main_s <= 0.0:
		TankEnemies.launch_far(
			state,
			aux,
			b.range_m,
			TankIds.SHELL_BOSS_MAIN,
			float(main.get("damage", 20.0)),
			TankEnemies.chance(state, float(main.get("hit", 0.85))),
			true,
			0,
			TankIds.BOSS_CODE,
			events
		)
		var key := "every_s" if b.phase == TankIds.BOSS_PHASE_1 else "every_s_phase2"
		b.main_s = _roll(state, main.get(key, [35, 45]))
		b.telegraph_s = 0.0
		aux.boss_tele_total = 0.0
	var sec: Dictionary = def.get("secondary", {})
	b.secondary_s -= dt
	if b.secondary_s <= 0.0:
		b.secondary_s = float(sec.get("every_s", 5.0))
		TankEnemies.launch_far(
			state,
			aux,
			b.range_m,
			TankIds.SHELL_ENEMY,
			float(sec.get("damage", 3.0)),
			TankEnemies.chance(state, float(sec.get("hit", 0.6))),
			false,
			0,
			TankIds.BOSS_CODE,
			events
		)


## A bogie broke: the Behemoth is pushed back; the last one ends phase 1.
static func bogie_broken(state: TankState, events: Array[Dictionary]) -> void:
	var b := state.boss
	var far: Dictionary = state.content.boss_def().get("far", {})
	b.range_m += float(far.get("pushback_m", 60.0))
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

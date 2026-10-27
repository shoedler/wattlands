class_name TankEvade
extends RefCounted
## "Surge to evade" (brief 2.4; owner: rules). Some enemy shots are telegraphed: a tank destroyer's
## 4 s glint, a heavy tank's 3 s muzzle glow, a light tank's 2.5 s flank shot (its first shot after
## it reaches its hold distance) and the Behemoth's 6 s main gun. While a telegraph runs, every
## rider who can evade (TankRiderState.can_evade: a SIM WORK phase of its own plan, past its first
## 300 s, present, not in rescue) and holds the sprint rule (>= 1.2 x FTP raw over the trailing
## 3 s, BRIEF 3.5) collects the seconds it held; the shot misses when any one rider held for
## evade.hold_s (2 s), evade.boss_hold_s (3 s) for the Behemoth. There is no intent: pedaling is
## the input, so the Autopilot never evades.
##
## Every telegraphed shot that resolves raises `evade {id, e, ok, s}` just before its `shot` event,
## and counts toward the results: the team's evades tried (some rider could evade) and successful,
## and per rider the shots it could evade and the ones its own surge made miss. A shooter that dies
## or breaks off before it fires resolves nothing. Pure: no random draws, time only through `dt`.

## aux.evade entries: shooter id -> {"held": {slot: seconds held inside the telegraph}, "able":
## {slot: true for every rider who could evade at some tick of it}}.
const HELD := "held"
const ABLE := "able"


## The shooter id of the Behemoth's main gun (its turret part's target id).
static func boss_shooter() -> int:
	return TankBossState.part_id(TankBossState.TURRET_PART)


## Whether rider input `ri` can evade now (brief 2.4): a SIM WORK phase of its own plan past its
## first 300 s (TankDrive.ability_ok), present (not on reserve), not in a rescue hold, and the crew
## not all AFK.
static func can_evade(state: TankState, ri: TankRiderInput) -> bool:
	return (
		TankDrive.ability_ok(ri)
		and not ri.on_reserve()
		and not TankStations.in_rescue(ri)
		and not state.all_afk
	)


## One tick of a running telegraph of `shooter_id`: every rider who can evade is noted, and one who
## holds the sprint rule adds `dt` to its held seconds. Returns true once a rider held for `need_s`.
static func accumulate(
	state: TankState, aux: TankAux, shooter_id: int, dt: float, need_s: float
) -> bool:
	var entry: Dictionary = aux.evade.get(shooter_id, {})
	if entry.is_empty():
		entry = {HELD: {}, ABLE: {}}
		aux.evade[shooter_id] = entry
	var held: Dictionary = entry[HELD]
	var able: Dictionary = entry[ABLE]
	var done := false
	for r in state.riders:
		if not r.can_evade:
			continue
		able[r.slot] = true
		if r.sprinting:
			held[r.slot] = float(held.get(r.slot, 0.0)) + dt
		if float(held.get(r.slot, 0.0)) >= need_s - 1e-6:
			done = true
	return done


## The telegraphed shot of `shooter_id` (enemy code `code`) fires now: raises the evade event and
## counts the results. Returns true when the shot misses (a rider held for `need_s`).
static func resolve(
	state: TankState,
	aux: TankAux,
	shooter_id: int,
	code: int,
	need_s: float,
	events: Array[Dictionary]
) -> bool:
	var entry: Dictionary = aux.evade.get(shooter_id, {})
	aux.evade.erase(shooter_id)
	var held: Dictionary = entry.get(HELD, {})
	var able: Dictionary = entry.get(ABLE, {})
	var by := -1
	for r in state.riders:
		if float(held.get(r.slot, 0.0)) >= need_s - 1e-6 and (by < 0 or r.slot < by):
			by = r.slot
	var ok := by >= 0
	if not able.is_empty():
		state.score.evades_tried += 1
		if ok:
			state.score.evades_ok += 1
	for r in state.riders:
		if able.has(r.slot):
			r.evades_tried += 1
			if float(held.get(r.slot, 0.0)) >= need_s - 1e-6:
				r.evades_ok += 1
	events.append(TankEvents.evade(shooter_id, code, ok, by))
	return ok


## Seconds the best rider has held inside the running telegraph of `shooter_id` (0 when none).
static func best_held(aux: TankAux, shooter_id: int) -> float:
	var held: Dictionary = (aux.evade.get(shooter_id, {}) as Dictionary).get(HELD, {})
	var best := 0.0
	for s: int in held:
		best = maxf(best, float(held[s]))
	return best


## Forgets the telegraph of `shooter_id` (it died, broke off or the segment ended).
static func forget(aux: TankAux, shooter_id: int) -> void:
	aux.evade.erase(shooter_id)

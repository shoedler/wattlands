class_name TankEvade
extends RefCounted
## "Surge to evade" (brief 2.4; v4; owner: rules). Some enemy shots are telegraphed: a tank destroyer's
## glint, a heavy tank's muzzle glow, a light tank's flank shot (its first shot after it reaches its
## hold) and the Behemoth's main gun. While a telegraph runs, and on through the shell's flight, every
## rider who can evade (TankRiderState.can_evade: a SIM WORK phase of its own plan, past its first
## 300 s, present, not in rescue) and holds the sprint rule (>= 1.2 x FTP raw over the trailing
## 3 s, BRIEF 3.5) collects the seconds it held; the shot misses when any one rider held for
## evade.hold_s (2 s), evade.boss_hold_s (3 s) for the Behemoth. There is no intent: pedaling is
## the input, so the Autopilot never evades.
##
## At fire the entry moves from the shooter to the shell (to_shell), so a dead shooter's shell still
## resolves. Every telegraphed shot raises `evade {id, e, ok, s}` when it lands, after its `shot`, and
## counts toward the results: the team's evades tried (some rider could evade) and successful, and per
## rider the shots it could evade and the ones its own surge made miss. A shooter that dies or breaks
## off before it fires resolves nothing. Pure: no random draws, time only through `dt`.

## aux.evade entries: shooter id, or shell_key(shell id) once fired -> {"held": {slot: seconds held},
## "able": {slot: true for every rider who could evade at some tick of it}}; a shell's entry also has
## "shooter" and "code", what its event reports.
const HELD := "held"
const ABLE := "able"
const SHOOTER := "shooter"
const CODE := "code"


## The shooter id of the Behemoth's main gun (its turret part's target id).
static func boss_shooter() -> int:
	return TankBossState.part_id(TankBossState.TURRET_PART)


## aux.evade's key for the telegraphed shell `shell_id`.
static func shell_key(shell_id: int) -> int:
	return -shell_id - 1000


## The seconds a rider must hold to make a shot of `shell` miss.
static func need_s(state: TankState, shell: int) -> float:
	if shell == TankIds.SHELL_BOSS_MAIN:
		return state.content.num("tanks", "evade.boss_hold_s", 3.0)
	return state.content.num("tanks", "evade.hold_s", 2.0)


## The shot of `shooter_id` left the barrel as shell `shell_id`: the running entry moves to the shell.
static func to_shell(aux: TankAux, shooter_id: int, shell_id: int, code: int) -> void:
	var entry: Dictionary = aux.evade.get(shooter_id, {HELD: {}, ABLE: {}})
	aux.evade.erase(shooter_id)
	entry[SHOOTER] = shooter_id
	entry[CODE] = code
	aux.evade[shell_key(shell_id)] = entry


## One tick of the flight of the telegraphed far shell `s`.
static func accumulate_shell(state: TankState, aux: TankAux, s: TankShellState, dt: float) -> void:
	if accumulate(state, aux, shell_key(s.id), dt, need_s(state, s.type)):
		if s.type == TankIds.SHELL_BOSS_MAIN:
			state.boss.evaded = true


## The telegraphed far shell `s` lands: its evade event and counts. Returns true when it misses.
static func land(
	state: TankState, aux: TankAux, s: TankShellState, events: Array[Dictionary]
) -> bool:
	var key := shell_key(s.id)
	var code := int((aux.evade.get(key, {}) as Dictionary).get(CODE, 0))
	return resolve(state, aux, key, code, need_s(state, s.type), events)


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


## The telegraphed shot keyed `shooter_id` (enemy code `code`) resolves now: raises the evade event
## and counts the results. Returns true when the shot misses (a rider held for `need_s`).
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
	var shooter := int(entry.get(SHOOTER, shooter_id))
	if shooter == boss_shooter():
		state.boss.evaded = false
	events.append(TankEvents.evade(shooter, code, ok, by))
	return ok


## Forgets the telegraph of `shooter_id` (it died, broke off or the segment ended).
static func forget(aux: TankAux, shooter_id: int) -> void:
	aux.evade.erase(shooter_id)

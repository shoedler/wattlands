class_name TankEvents
extends RefCounted
## Game events (brief 2.6; G0 contract). The rules return them from TankRules.step; the module
## sends each with send_event (host), raises the host's own effects where it sends them, and
## clients apply them in apply_event in the host's order. Every number is an int (declared in
## INT_FIELDS, returned by int_fields()). Never name an event "snapshot" or "wl.*".
##
##   segment    {i: phase index, sg: seg code, st: stage}                 the group entered a segment
##   rotation   {r: [[slot, engine code], ...]}                           stations changed (checkpoint)
##   shot       {s: slot or -1 (enemy), sh: shell type, id: shell id, src: enemy id or 0,
##               e: enemy code or 0}
##   hit        {on: ON_*, id: target id (0 the tank), dmg: the round's damage before the berm
##               (rounded), sh: shell type, b: the part the berm absorbed (rounded), x: world x px};
##               a tank hit by the Behemoth's main gun has sh SHELL_BOSS_MAIN
##   kill       {id, e: enemy code (BOSS_CODE for the Behemoth), by: BY_*, s: credited slot or -1}
##   ram, dodge reserved (v1's Ram and boss dodge; v2 removed both, brief 2.4): never emitted, kept
##              in TYPES and INT_FIELDS so their names stay taken on the wire
##   breakdown  {}                                                        the hull hit 0 HP
##   repaired   {hp}                                                      back to 40 HP
##   overrun    {sg: seg code, st: stage}                                 the previous segment hit max_s
##   boss_phase {p: TankIds.BOSS_*}
## Additive (G0): latch {s, sh: shell type}, lever {s, lv: TankIds.LEVER_*} for sound and view.
## Additive (v2, brief 2.4, 2.6, 2.10):
##   evade      {id: the shooter's id (an enemy, or the Behemoth's turret part id), e: enemy code
##               (BOSS_CODE for the Behemoth's main gun), ok: 1 the shot missed (a rider held the
##               sprint rule inside the telegraph) / 0 it was not evaded, s: the slot whose surge
##               made it miss (the lowest such slot; -1 when not evaded)}: every telegraphed shot
##               that resolves (the shot event follows it in the same tick)
##   turn       {s: the slot that turned or -1 (Autopilot at a map end), dir: the new travel
##               direction TankIds.DIR_*}                         free roam: the tank turns round
##   time_up    {p: patrols raised before it}                  free roam: min_s reached, no new patrols
##
## Semantics the haptics depend on (brief 2.7; the director reads them this way):
## - An evaded shot misses: no `hit` event, so no haptic.
## - During a breakdown (damage ignored) a round that lands still emits `hit` with dmg 0: no haptic.
## - A hit the berm absorbs keeps its pre-berm dmg (b says how much the berm took): it still
##   counts as a "Hit of >= 8 damage".
## - A Behemoth main-gun hit is `hit` with sh SHELL_BOSS_MAIN: is_boss_main_hit, never is_tank_hit,
##   so it sends the boss_hit haptic (3.0 for 2 s) and not the 2.0 one.
## - At most one haptic per receiver per tick, by precedence boss_hit, then hit (crew-wide;
##   TankDirector.crew_haptic picks it); a haptic inside the receiver's 15 s cooldown is dropped,
##   never queued.

const SEGMENT := "segment"
const ROTATION := "rotation"
const SHOT := "shot"
const HIT := "hit"
const KILL := "kill"
## Reserved (v1; never emitted in v2).
const RAM := "ram"
## Reserved (v1; never emitted in v2).
const DODGE := "dodge"
const BREAKDOWN := "breakdown"
const REPAIRED := "repaired"
const OVERRUN := "overrun"
const BOSS_PHASE := "boss_phase"
const LATCH := "latch"
const LEVER := "lever"
const EVADE := "evade"
const TURN := "turn"
const TIME_UP := "time_up"
const TYPES: Array[String] = [
	SEGMENT,
	ROTATION,
	SHOT,
	HIT,
	KILL,
	RAM,
	DODGE,
	BREAKDOWN,
	REPAIRED,
	OVERRUN,
	BOSS_PHASE,
	LATCH,
	LEVER,
	EVADE,
	TURN,
	TIME_UP
]

## hit "on"
const ON_TANK := 0
const ON_ENEMY := 1
const ON_BOSS := 2
const ON_OBSTACLE := 3
## kill "by" (1 was v1's Ram: reserved, never used in v2)
const BY_SHELL := 0
const BY_BARRAGE := 2
## v2: a bow-gun burst (brief 2.4 Gun).
const BY_BOW := 3

## int_fields() entries for every event type (the snapshot's are TankSnapshotSchema.INT_PATHS).
const INT_FIELDS := {
	SEGMENT: ["i", "sg", "st"],
	ROTATION: ["r[][]"],
	SHOT: ["s", "sh", "id", "src", "e"],
	HIT: ["on", "id", "dmg", "sh", "b", "x"],
	KILL: ["id", "e", "by", "s"],
	RAM: ["s", "ok", "id"],
	DODGE: ["s"],
	BREAKDOWN: [],
	REPAIRED: ["hp"],
	OVERRUN: ["sg", "st"],
	BOSS_PHASE: ["p"],
	LATCH: ["s", "sh"],
	LEVER: ["s", "lv"],
	EVADE: ["id", "e", "ok", "s"],
	TURN: ["s", "dir"],
	TIME_UP: ["p"],
}


static func segment(index: int, seg: String, stage: int) -> Dictionary:
	return {"type": SEGMENT, "i": index, "sg": TankIds.seg_code(seg), "st": stage}


## `pairs`: [[slot, engine], ...] in slot order.
static func rotation(pairs: Array) -> Dictionary:
	var r: Array = []
	for p: Array in pairs:
		r.append([int(p[0]), TankIds.engine_code(str(p[1]))])
	return {"type": ROTATION, "r": r}


static func shot(
	slot: int, shell: int, shell_id: int, src: int = 0, enemy_code: int = 0
) -> Dictionary:
	return {"type": SHOT, "s": slot, "sh": shell, "id": shell_id, "src": src, "e": enemy_code}


static func hit(
	on: int, target_id: int, dmg: float, shell: int, berm: float, x: float
) -> Dictionary:
	return {
		"type": HIT,
		"on": on,
		"id": target_id,
		"dmg": roundi(dmg),
		"sh": shell,
		"b": roundi(berm),
		"x": roundi(x)
	}


static func kill(target_id: int, code: int, by: int, slot: int) -> Dictionary:
	return {"type": KILL, "id": target_id, "e": code, "by": by, "s": slot}


static func breakdown() -> Dictionary:
	return {"type": BREAKDOWN}


static func repaired(hp: float) -> Dictionary:
	return {"type": REPAIRED, "hp": roundi(hp)}


static func overrun(seg: String, stage: int) -> Dictionary:
	return {"type": OVERRUN, "sg": TankIds.seg_code(seg), "st": stage}


static func boss_phase(phase: int) -> Dictionary:
	return {"type": BOSS_PHASE, "p": phase}


static func latch(slot: int, shell: int) -> Dictionary:
	return {"type": LATCH, "s": slot, "sh": shell}


static func lever(slot: int, position: int) -> Dictionary:
	return {"type": LEVER, "s": slot, "lv": position}


## A telegraphed shot resolved: `ok` true when the crew's surge made it miss; `slot` the rider
## whose surge did it (-1 when not evaded).
static func evade(shooter_id: int, code: int, ok: bool, slot: int = -1) -> Dictionary:
	return {"type": EVADE, "id": shooter_id, "e": code, "ok": int(ok), "s": slot if ok else -1}


## The tank turned round (free roam); `dir` is the new TankIds.DIR_*.
static func turn(slot: int, dir: int) -> Dictionary:
	return {"type": TURN, "s": slot, "dir": dir}


## Free roam's time up; `patrols`: how many patrols came before it (none come after: the results'
## TANK_TEAM_PATROLS equals it).
static func time_up(patrols: int = 0) -> Dictionary:
	return {"type": TIME_UP, "p": patrols}


## True for a hit on the tank that the brief's "Hit of >= 8 damage" haptic covers (brief 2.7):
## the round's damage, before the berm absorbed any. A Behemoth main-gun hit is excluded: it is
## is_boss_main_hit (its own, larger haptic).
static func is_tank_hit(e: Dictionary, min_damage: float) -> bool:
	return (
		str(e.get("type", "")) == HIT
		and int(e.get("on", -1)) == ON_TANK
		and int(e.get("sh", 0)) != TankIds.SHELL_BOSS_MAIN
		and float(e.get("dmg", 0)) >= min_damage
	)


## True for a hit on the tank by the Behemoth's main gun (the boss_hit haptic).
static func is_boss_main_hit(e: Dictionary) -> bool:
	return (
		str(e.get("type", "")) == HIT
		and int(e.get("on", -1)) == ON_TANK
		and int(e.get("sh", 0)) == TankIds.SHELL_BOSS_MAIN
	)

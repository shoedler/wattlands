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
##   ram        {s: slot, ok: 1 destroyed / 0 failed (10 HP, 5 s stall), id: target id or 0}
##   dodge      {s: slot}                                                 the boss shot will miss
##   breakdown  {}                                                        the hull hit 0 HP
##   repaired   {hp}                                                      back to 40 HP
##   overrun    {sg: seg code, st: stage}                                 the previous segment hit max_s
##   boss_phase {p: TankIds.BOSS_*}
## Additive (G0): latch {s, sh: shell type}, lever {s, lv: TankIds.LEVER_*} for sound and view.

const SEGMENT := "segment"
const ROTATION := "rotation"
const SHOT := "shot"
const HIT := "hit"
const KILL := "kill"
const RAM := "ram"
const DODGE := "dodge"
const BREAKDOWN := "breakdown"
const REPAIRED := "repaired"
const OVERRUN := "overrun"
const BOSS_PHASE := "boss_phase"
const LATCH := "latch"
const LEVER := "lever"
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
	LEVER
]

## hit "on"
const ON_TANK := 0
const ON_ENEMY := 1
const ON_BOSS := 2
const ON_OBSTACLE := 3
## kill "by"
const BY_SHELL := 0
const BY_RAM := 1
const BY_BARRAGE := 2

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


static func ram(slot: int, ok: bool, target_id: int) -> Dictionary:
	return {"type": RAM, "s": slot, "ok": int(ok), "id": target_id}


static func dodge(slot: int) -> Dictionary:
	return {"type": DODGE, "s": slot}


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


## True for a hit on the tank that the brief's "Hit of >= 8 damage" haptic covers (brief 2.7):
## the round's damage, before the berm absorbed any.
static func is_tank_hit(e: Dictionary, min_damage: float) -> bool:
	return (
		str(e.get("type", "")) == HIT
		and int(e.get("on", -1)) == ON_TANK
		and float(e.get("dmg", 0)) >= min_damage
	)


## True for a hit on the tank by the Behemoth's main gun (the boss_hit haptic).
static func is_boss_main_hit(e: Dictionary) -> bool:
	return (
		str(e.get("type", "")) == HIT
		and int(e.get("on", -1)) == ON_TANK
		and int(e.get("sh", 0)) == TankIds.SHELL_BOSS_MAIN
	)

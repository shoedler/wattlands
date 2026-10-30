class_name SiegePads
extends RefCounted
## The pads' crew-wound weapons (brief 2.4 "Pads"). Pure, deterministic. No rider drives them and
## their kills pay no bounty.
##
## The Scorpion fires a 50 m/s bolt (k 0.001, 10 damage, no pierce) every 2.4 s at the live enemy
## nearest the gate within its band (0..60 m), lead-aimed (SiegeAim, the low arc); it turns to
## its target at once. Upgrades: 1 +40% rate, 2 +25% range, 3 a second bolt per shot (the shot
## event's n 2). Pads stop outside waves, in a Breach (perks included) and, for pads 1 and 2,
## while a docked siege tower's boarders are on the wall. An armed pad with nothing in range
## looks again every tick.


static func step(
	state: SiegeState, tb: SiegeCombatTable, dt: float, events: Array[Dictionary]
) -> void:
	for pd in state.pads:
		if not pd.built():
			continue
		if not tb.live or (state.tar.boarded and SiegeIds.BOARDED_PADS.has(pd.pad)):
			continue
		var def := state.content.pad_def(pd.type)
		var rate := float(def.get("rate_mult", 1.4)) if pd.level >= 1 else 1.0
		pd.cd_s -= dt * rate
		if pd.cd_s > 0.0:
			continue
		if _fire(state, tb, pd, def, events):
			pd.cd_s += float(def.get("interval_s", 2.4))
		else:
			pd.cd_s = 0.0


## The live enemy nearest the gate within pad `n`'s band, or null.
static func target(state: SiegeState, n: int) -> SiegeEnemyState:
	var band := state.pad_band(n)
	var at := state.path.pads[n - 1]
	var lo2 := band.x * band.x
	var hi2 := band.y * band.y
	var best: SiegeEnemyState = null
	for e in state.enemies:
		if not e.alive():
			continue
		var d2 := (e.pos.x - at.x) * (e.pos.x - at.x) + (e.pos.y - at.y) * (e.pos.y - at.y)
		if d2 < lo2 or d2 > hi2:
			continue
		if best == null or e.prog_m > best.prog_m:
			best = e
	return best


static func _fire(
	state: SiegeState,
	tb: SiegeCombatTable,
	pd: SiegePadState,
	def: Dictionary,
	events: Array[Dictionary]
) -> bool:
	var e := target(state, pd.pad)
	if e == null:
		return false
	var spec := def.duplicate()
	spec["aim"] = "angle"
	var rounds := int(state.content.st_num("lead_rounds", 3))
	var sol := SiegeAim.lead(state.path, state.path.pads[pd.pad - 1], 0.0, e, spec, 1.0, rounds)
	if sol.is_empty():
		return false
	pd.yaw_deg = float(sol["yaw"])
	var n := int(def.get("special_bolts", 2)) if pd.level >= 3 else 1
	SiegeProjectiles.fire(state, tb, SiegeIds.SRC_PAD + pd.pad, sol, n, e.id, events)
	return true

class_name SiegeEconomy
extends RefCounted
## Denarii (brief 2.4 "Economy"). Pure.
##
## - The generator pays 1 denarius per kJ of P_eff x (1 + 0.2 x generator level) to a rider whose
##   output reaches it (all output goes there in breaks).
## - A kill pays its bounty x bounty_scale, split among the tower's delivering riders by P_eff
##   share. A riderless tower (Reserve flywheel hold, Aqueduct drive) earns nothing. A rush
##   kill pays double to a rider whose Overdrive is on. The kill's top-share rider gets the kill.
## - Denarii are personal floats; the shop floors them.


## The generator's payout multiplier now (denarii per kJ of P_eff).
static func generator_rate(state: SiegeState) -> float:
	return (
		state.content.num("generator.denarii_per_kj", 1.0)
		* (1.0 + state.content.num("generator.level_bonus", 0.2) * state.gen_level)
	)


## Pays `rider` for `p_eff_w` over `dt` at the generator; returns the denarii.
static func pay_generator(
	state: SiegeState, rider: SiegeRiderState, p_eff_w: float, dt: float, rate: float
) -> float:
	var pay := maxf(p_eff_w, 0.0) * dt / 1000.0 * rate
	rider.denarii += pay
	rider.gen_denarii += pay
	state.team_earned += pay
	return pay


## Pays the bounty of enemy type `enemy_type` killed by the tower on `pad` to its riders by
## P_eff share. Returns true when any rider got the rush double.
static func pay_bounty(
	state: SiegeState, pad: int, enemy_type: int, base_bounty: float, rush: bool
) -> bool:
	var riders := state.riders_on(pad)
	var total := 0.0
	for r in riders:
		total += maxf(r.p_eff_w, 0.0)
	if total <= 0.0:
		return false
	var bonus := state.content.num("rush.od_bounty_mult", 2.0)
	var doubled := false
	var top: SiegeRiderState = null
	var top_w := -1.0
	for r in riders:
		var w := maxf(r.p_eff_w, 0.0)
		var mult := 1.0
		if rush and r.od_state == SiegeIds.OD_ACTIVE:
			mult = bonus
			doubled = true
		var pay := base_bounty * state.bounty_scale * w / total * mult
		r.denarii += pay
		r.bounty_denarii += pay
		state.team_earned += pay
		if w > top_w:
			top = r
			top_w = w
	if top != null and enemy_type > 0:
		top.kills += 1
	return doubled

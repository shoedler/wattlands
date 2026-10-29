class_name SiegeEconomy
extends RefCounted
## Gold (brief 2.4 "Economy"). Pure.
##
## - The mine pays 1 gold per kJ of P_eff x (1 + 0.2 x mine level) to a rider whose output reaches
##   it (in waves) and to every delivering rider in breaks (all output goes to the mine then). It
##   stops in a Breach like every station (ADR "the mine in a Breach").
## - A kill pays its bounty x bounty_scale, split among the riders who delivered to the killing
##   station when the projectile left, by P_eff share (pads pay nothing). A rush kill pays double
##   to a rider whose Overdrive is on. The kill's top-share rider gets the kill.
## - Gold is personal (floats; the shop and the snapshot floor them).


## The mine's payout multiplier now (gold per kJ of P_eff).
static func mine_rate(state: SiegeState) -> float:
	return (
		state.content.num("mine.gold_per_kj", 1.0)
		* (1.0 + state.content.num("mine.level_bonus", 0.2) * state.mine_level)
	)


## Pays `rider` for `p_eff_w` over `dt` at the mine; returns the gold.
static func pay_mine(
	state: SiegeState, rider: SiegeRiderState, p_eff_w: float, dt: float, rate: float
) -> float:
	var pay := maxf(p_eff_w, 0.0) * dt / 1000.0 * rate
	rider.gold += pay
	rider.mine_gold += pay
	state.team_earned += pay
	return pay


## Pays the bounty `base_bounty` of an enemy of `enemy_type` to `peers` by their `shares`
## (fractions summing to 1). Returns true when any rider got the rush double.
static func pay_bounty(
	state: SiegeState,
	peers: Array[int],
	shares: Array[float],
	enemy_type: int,
	base_bounty: float,
	rush: bool
) -> bool:
	var bonus := state.content.num("rush.od_bounty_mult", 2.0)
	var doubled := false
	var top: SiegeRiderState = null
	var top_share := -1.0
	for i in peers.size():
		var r := state.rider(peers[i])
		if r == null:
			continue
		var mult := 1.0
		if rush and r.od_state == SiegeIds.OD_ACTIVE:
			mult = bonus
			doubled = true
		var pay := base_bounty * state.bounty_scale * shares[i] * mult
		r.gold += pay
		r.bounty_gold += pay
		state.team_earned += pay
		if shares[i] > top_share:
			top = r
			top_share = shares[i]
	if top != null and enemy_type > 0:
		top.kills += 1
	return doubled

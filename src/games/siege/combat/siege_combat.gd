class_name SiegeCombat
extends RefCounted
## Roads, enemies, towers, Caltrop zones, the spawner, rushes and the 150-enemy cap (brief 2.4).
## Owner: B1 "rules" (src/games/siege/combat/). Pure and deterministic like SiegeRules.
##
## G0 status: a stub that spawns nothing. B1 implements step() (called by SiegeRules.step after
## routing and the generator) and may split it into more combat/ files. Contract it keeps:
## - enemies move along SiegeMap roads at speed x slow, keep `pos` current (SiegeEnemyState.place),
##   and never exceed enemies.json cap alive (the rest wait in state.queue);
## - tower output m from state.riders_on(pad) with SiegeOverdrive.multiplier(); hits resolve on
##   the fire tick; every shot goes to state.shots (kept 0.1 s);
## - kills pay bounty x bounty_scale split by P_eff share (rush kills double for riders in
##   Overdrive); leaks damage the gate; a Breach stops every tower and perk for 10 s;
## - returns kill, leak, breach, gate_restored, roads, push and rush events (SiegeEvents).


## One combat tick; returns its events in order.
static func step(_state: SiegeState, _inputs: SiegeInputs, _dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	return events

class_name SiegeTarWorks
extends RefCounted
## The tar works (brief 2.4 "Tar works"). Pure.
##
## - The cauldrons hold 300 L (+100 with the Spare cauldron) and reheat at 1 L/s, with or without
##   a rider, in every phase.
## - The pump moves 6 L/s x m into the curtain while there is tar (and room), only while the
##   station is live (a wave, no Breach) and no boarders are on the wall.
## - The curtain holds 0..200 HP (1 HP per litre; +25% after upgrade 2) and drains 1 HP/s.
##   Gate damage hits it first (SiegeCombat.damage_gate).
## - The bridge coat is min(1, curtain / 100); the combat table turns it into the bridge's speed
##   factor 1 - 0.5 x coat (0.65 after upgrade 3) for the next step.
## - Boarders: a docked siege tower on the wall (tar.boarded) stops the pump and pads 1 and 2.


static func step(state: SiegeState, tb: SiegeCombatTable, dt: float) -> void:
	var c := state.content
	var tar := state.tar
	var st := state.station(SiegeIds.STATION_TAR)
	tar.cauldron_max_l = state.cauldron_max()
	tar.curtain_max = state.curtain_max()
	tar.boarded = state.docked_tower() != null
	tar.cauldron_l = minf(
		tar.cauldron_l + c.st_num("stations.tar.reheat_lps", 1.0) * dt, tar.cauldron_max_l
	)
	st.m = 0.0
	if tb.live and not tar.boarded:
		st.m = SiegeStations.output(state, tb, st, dt, false)
	elif not tb.live:
		st.hold_s = 0.0
	if st.m > 0.0:
		var want := c.st_num("stations.tar.pump_lps", 6.0) * st.m * dt
		var litres := minf(minf(want, tar.cauldron_l), maxf(tar.curtain_max - tar.curtain_hp, 0.0))
		tar.cauldron_l -= litres
		tar.curtain_hp += litres
	tar.curtain_hp = maxf(
		tar.curtain_hp - c.st_num("stations.tar.curtain_drain_hps", 1.0) * dt, 0.0
	)
	tar.curtain_hp = minf(tar.curtain_hp, tar.curtain_max)
	tar.coat = minf(1.0, tar.curtain_hp / maxf(c.st_num("stations.tar.coat_full_hp", 100.0), 0.001))
	st.wind = clampf(tar.cauldron_l / maxf(tar.cauldron_max_l, 1.0), 0.0, 1.0)
	st.arm = st.wind

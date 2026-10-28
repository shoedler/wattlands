class_name TankFeedState
extends TankStationState
## The Secondaries seat (v3, brief "One tank, five seats"): a crank-driven twin belt feed for the
## two bow guns, SIM flat. Each pedal revolution of its rider fires exactly ROUNDS_PER_REV rounds,
## alternating guns, at the nearest enemy 40-220 px ahead, so its rate in rounds per minute is
## ROUNDS_PER_REV x cadence; power in band sets the guns' slew speed. An empty seat is silent.
## The rules builder implements the firing (TankBow); this is the state it keeps and the view and
## HUD read.

## Rounds per pedal revolution (brief: exactly 2).
const ROUNDS_PER_REV := 2

## [snap] Rounds fired since the session start, both guns. Round k (1-based) fires gun
## (k - 1) mod 2 (0 the upper, 1 the lower bow gun), so the last round came from gun
## (rounds - 1) mod 2; the view flashes, tracers and ejects one casing per new round.
var rounds: int = 0
## [snap] Rounds per minute now: ROUNDS_PER_REV x the rider's cadence while the guns fire, 0 while
## silent (the HUD's Secondaries card and dial).
var rpm: float = 0.0
## [snap] Game tick of the latest round; -1 before the first.
var fire_tick: int = -1
## Host only: pedal revolutions counted toward the next round (cadence / 60 x dt per tick; a round
## leaves every 1 / ROUNDS_PER_REV revolution, so it stays below that between ticks).
var rev_acc: float = 0.0


## The bow gun (0 upper, 1 lower) that fired the latest round; -1 before the first.
func last_gun() -> int:
	return posmod(rounds - 1, 2) if rounds > 0 else -1

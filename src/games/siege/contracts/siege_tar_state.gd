class_name SiegeTarState
extends SiegeRecord
## The tar works (brief 2.4 "Tar works", STATE_V2.md): cauldrons, the curtain over the gate, the
## coat on the bridge, and the boarders of a docked siege tower. [snap] fields come back on
## clients (snapshot "tar").

## [snap] Litres in the cauldrons, of cauldron_max_l (300, or 400 with the Spare cauldron).
var cauldron_l: float = 300.0
var cauldron_max_l: float = 300.0
## [snap] Curtain HP 0..curtain_max (200, +25% with upgrade 2); gate damage hits it first.
var curtain_hp: float = 0.0
var curtain_max: float = 200.0
## [snap] 0..1: min(1, curtain / 100). Everything on the bridge moves at x (1 - 0.5 x coat).
var coat: float = 0.0
## [snap] A docked siege tower has boarders on the wall: the tar works and pads 1 and 2 stop.
var boarded: bool = false

class_name TankDieselState
extends TankStationState
## The diesel (brief 2.4 Drive): tracks, the dozer blade, Ram and dodge sprints. The Bulwark's
## TankGearboxState extends it.

## [snap] Seconds left of an open Ram window (10 s); 0 when none.
var ram_s: float = 0.0
## [snap] Seconds of the Ram cooldown left (30 s).
var ram_cd_s: float = 0.0
## Seconds the sprint rule has held without a break: held_s() of the rider's SprintRule
## (TankRiderState.sprint_rule(3 s): the trailing 3 s average >= 1.2 x FTP, not "every tick
## >= 1.2 x FTP for 3 s"). A Ram needs holds() at contact; a dodge needs dodge_s >= 3 s.
var sprint_s: float = 0.0
## [snap] The sprint rule holds now.
var sprinting: bool = false
## [snap] A "Surge to ram" or "Surge to dodge" prompt is up (each peer raises its own toast).
var prompt: bool = false
## Boss: seconds the sprint rule held inside the current main-gun telegraph.
var dodge_s: float = 0.0

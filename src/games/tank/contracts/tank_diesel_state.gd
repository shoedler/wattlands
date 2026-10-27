class_name TankDieselState
extends TankStationState
## The diesel (brief 2.4 Drive): tracks and the dozer blade. The Bulwark's TankGearboxState extends
## it. v2 removed the Ram and the boss dodge (brief 2.4): a diesel rider's sprint is "Surge to
## evade" (TankEvade), which needs no state here beyond `sprinting`.

## [snap] The rider's sprint rule holds now (TankRiderState.sprint_rule: the trailing 3 s average
## >= 1.2 x FTP); the view's lurch and exhaust read it.
var sprinting: bool = false

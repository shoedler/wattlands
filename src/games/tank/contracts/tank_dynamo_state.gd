class_name TankDynamoState
extends TankStationState
## The dynamo (brief 2.4 Dynamo): the capacitor bank that drives traverse, elevation, the
## Rampart's hoist and the bow guns of the Rampart and the Citadel (2 units a burst, none below 10).
## The director turns the bank into the ERG target
## 55 + 45 x (1 - bank / 100) % FTP (brief 2.3 pattern 1); the rules never read that target back.

## [snap] Bank units 0..100.
var bank: float = 100.0
## [snap] Rescue: turret frozen, bank not charging ("Dynamo stalled").
var stalled: bool = false
## [snap] Rampart only: seconds left of the hoist lifting a heavy shell (0 idle).
var hoist_s: float = 0.0
## An enemy is in range this tick (the stabilizer drains 1.5 units/s).
var stabilizing: bool = false

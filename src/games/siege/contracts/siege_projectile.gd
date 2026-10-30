class_name SiegeProjectile
extends SiegeRecord
## One projectile in flight on the host (SiegeState.projectiles; clients replay it from its
## `shot` event instead, brief 2.6). Bolts fly tick by tick through the bodies they pass; stones
## and arrows land where their drag flight says, decided at fire time.

## SiegeIds.SHOT_*.
var kind: int = SiegeIds.SHOT_BOLT
## A station 1..3, or SiegeIds.SRC_PAD + pad.
var src: int = 0
var pos: Vector3 = Vector3.ZERO
var vel: Vector3 = Vector3.ZERO
var k: float = 0.0
## Ticks until it lands (stones, arrows), or until it is given up (bolts).
var ticks: int = 0
## Damage it carries now (a bolt's falls after each body it passes).
var damage: float = 0.0
## The ground height it lands on (the aim point's).
var floor_z: float = 0.0
## The enemy it was aimed at (0: none).
var target_id: int = 0
## Bolts: ids already hit. A bolt that pierces keeps flying; a Scorpion's stops at the first.
var hit_ids: Array[int] = []
var pierce: bool = false
## Ballista upgrade 3 (an iron head that ignores armour).
var ignore_armour: bool = false
## Arrows: a shield bearer's testudo would block this one (drawn at fire time).
var testudo: bool = false
## Riders delivering to the source station at fire time and their P_eff shares (bounties and
## damage are credited to them): peers and weights in the same order.
var peers: Array[int] = []
var shares: Array[float] = []
## A hit is counted once per projectile.
var hit: bool = false

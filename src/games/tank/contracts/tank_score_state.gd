class_name TankScoreState
extends TankRecord
## Team counters for the score and the results (G0 contract; brief 2.8). Host only except the
## [snap] fields the HUD's objective line and boss bars need.

## Kills by code: index TankIds.ENEMY_CODES value, BOSS_CODE for the Behemoth (index 0 unused).
var kills: Array[int] = [0, 0, 0, 0, 0, 0, 0]
## Kills by crew fire or Ram (a support barrage kills nothing).
var crew_kills: int = 0
## [snap]
var breakdowns: int = 0
## [snap]
var overruns: int = 0
## Stages whose Advance and gun line both ended without an overrun (objectives: 0.6 x n / 3).
var stages_clean: int = 0
## Per stage 1..3: an overrun happened in it (index stage - 1).
var stage_overrun: Array[bool] = [false, false, false]
## [snap]
var behemoth_killed: bool = false
## Main-gun shots and hits (accuracy = hits / shots, 0 with no shot).
var shots: int = 0
var hits: int = 0
## Hull HP at the end of each plan segment (index = phase index).
var hp_by_segment: Array[int] = []
## Damage the berm absorbed in all.
var berm_absorbed: float = 0.0

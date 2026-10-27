class_name TankRoamState
extends TankRecord
## Free roam (brief 2.10; v2): where the tank is on the valley road, the turn, the clock's time up,
## the crew's points, the patrol timer and the strongpoints. TankRoam (rules/) writes it on the host;
## TankSnapshot carries the [snap] fields in its optional "rm" row; the view and HUD only read it.
## Missions leave it inactive (active false, every field at its default).
##
## The rules keep working in the travel frame (the tank always drives toward +x in rules px, as in a
## mission): map_m is where the hull's centre stands on the valley road, and TankHullState.dir says
## which way along the road +x points (DIR_RIGHT east, DIR_LEFT west). A turn mirrors the travel
## frame about the hull's centre at its midpoint (TankRoam.flip), so every map point keeps its place.

## [snap] A free-roam session (the content's kind is "roam").
var active: bool = false
## [snap] The valley's seed (drawn from ctx.rng at the session start; TankRoamMap rebuilds the map
## from it on every peer).
var map_seed: int = 0
## [snap] The hull centre's place on the road in game metres (0 the west turning place).
var map_m: float = 0.0
## [snap] Seconds left of the turn stop (0: not turning). The flip happens at its midpoint.
var turn_s: float = 0.0
## [snap] Seconds left of the turn intent's cooldown.
var turn_cd_s: float = 0.0
## The running turn already flipped the travel frame (host).
var flipped: bool = false
## [snap] The map end the tank stands at: -1 west, +1 east, 0 none (the road stops there).
var at_end: int = 0
## [snap] Seconds the tank has stood at that end (the Autopilot turns after valley.json
## turn.autopilot_wait_s).
var end_s: float = 0.0
## [snap] The tank halts to engage a strongpoint or a heavy tank in range ("Engage").
var engaging: bool = false
## [snap] min_s of the roam phase passed: no new patrols or strongpoints.
var time_up: bool = false
## [snap] Past time up while a fight finishes (an enemy within valley.json fight_px).
var overtime: bool = false
## [snap] The crew's points (brief 2.10 Points).
var points: int = 0
## Full kilometres of the roam phase already paid (+2 each).
var km_paid: int = 0
## [snap] Metres driven in the whole session and in the roam WORK phase.
var odo_m: float = 0.0
var work_m: float = 0.0
## Game seconds of the roam WORK phase (points per WORK minute grade it).
var work_s: float = 0.0
## Seconds of WORK time to the next patrol (host).
var patrol_s: float = 0.0
## Patrols raised (host; results).
var patrols: int = 0
## Per strongpoint spot (TankRoamMap.strongpoints order): seconds until it returns (0: standing),
## and the id of its enemy while it stands near the tank (0: none on the field).
var strong_back_s: Array[float] = []
var strong_id: Array[int] = []
## Points earned per source (results): kills, evades, breakdowns, kilometres.
var kill_points: int = 0
var evade_points: int = 0
var breakdown_points: int = 0
var km_points: int = 0


## Whether strongpoint `i` is down (returns later).
func strong_down(i: int) -> bool:
	return i >= 0 and i < strong_back_s.size() and strong_back_s[i] > 0.0


## The bit mask of the strongpoints that are down (bit i = spot i), for the snapshot.
func down_mask() -> int:
	var m := 0
	for i in mini(strong_back_s.size(), 30):
		if strong_back_s[i] > 0.0:
			m |= 1 << i
	return m

class_name FishingState
extends FishingRecord
## The whole simulation state of a session (contract v2): one FishingRiderState per slot, in
## slot order, the shared ocean (world) and the team's catch board. FishingRules.new_state builds
## it on every peer at configure time; the host steps it; clients overwrite it from snapshots.

var tick: int = 0
## Game seconds since the session started (tick x 0.05).
var t: float = 0.0
var trip_id: String = ""
var trip_kind: String = ""
## Free Roam (true) or a workout.
var roam: bool = false
## The ocean: the roam map or the endless workout map. Not serialized.
var world: FishingWorld = null
## species id -> FishingSpeciesDef (hint draws and Free Roam fights). Not serialized.
var species: Dictionary = {}
var riders: Array[FishingRiderState] = []

# --- Clock -------------------------------------------------------------------------------------
## Game time play ends (Free Roam: the content's minutes; workouts: fishing's end) and the latest
## a fight may end (+ 5 min).
var play_end_t: float = 0.0
var overtime_end_t: float = 0.0
## Time is up: no new bites; the session ends once no fight is on (or at overtime_end_t).
var time_up: bool = false
## finished("trip_over") was emitted.
var trip_over: bool = false
## The session's nominal length without the cool-down.
var total_s: float = 0.0

# --- Workouts ------------------------------------------------------------------------------
## Threshold or e2e: one shared schedule, fixed Reels, self-hooking fish.
var scheduled: bool = false
## R_min = max(120 s, k_rmin x the previous fight's length incl. landing).
var k_rmin: float = 1.5
## Fight budget per rider: fight_cap_frac x fishing_s.
var fight_budget_s: float = 0.0

# --- Team ----------------------------------------------------------------------------------------
var team_points: int = 0
var team_fish: int = 0
## Fights on right now (0..4).
var hookup_level: int = 0
## The catch board, newest last, flat: [slot, species, kg x 10, trophy, ...] (<= 5 catches).
var catches: Array[int] = []
## Workouts: points if every started fish were Landed with no bonuses (the team grade's base).
var expected_points: float = 0.0
var fish_started: int = 0


func rider_of_peer(peer: int) -> FishingRiderState:
	for r in riders:
		if r.peer == peer:
			return r
	return null


func rider(slot: int) -> FishingRiderState:
	return riders[slot] if slot >= 0 and slot < riders.size() else null


## Seconds of play left (0 once time is up).
func time_left_s() -> float:
	return maxf(play_end_t - t, 0.0)

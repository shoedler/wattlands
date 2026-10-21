class_name WorkoutRiderState
extends RefCounted
## One rider's Workout state: position for the ride view (SpeedModel from P_eff, BRIEF
## 3.11), compliance (in band now, time in band per interval and for the session), sprint
## results and ride statistics. Owned by WorkoutState; changed only by WorkoutRules on the
## host and by WorkoutSnapshot on clients.

var peer_id: int = 0
var slot_index: int = 0
var name: String = ""
var ftp: float = 200.0
var ftp_verified: bool = true
var is_bot: bool = false
var speed: SpeedModel = null
## Distance ridden inside the current course phase (m), for the course profile.
var course_d: float = 0.0
var phase_index: int = -1
var in_band: bool = false
var rescue: bool = false
var afk: bool = false
var connected: bool = true
var power_w: float = 0.0
var cadence_rpm: float = 0.0
## Seconds in band and seconds ridden over the session's own phases (cool-down excluded).
var tib_s: float = 0.0
var ride_s: float = 0.0
## phase index -> [in_band_s, ridden_s]
var intervals: Dictionary = {}
## The sprint in progress (FREE phase), or null.
var sprint: WorkoutSprintTracker = null
## Finished sprints: [{i, peak_w, best_s, held_s, hit}].
var sprints: Array[Dictionary] = []
var stats: WorkoutPowerStats = WorkoutPowerStats.new()
## Clients: values from the latest snapshot.
var snap_tib_permille: int = 0
var snap_interval_permille: int = 0


static func from_slot(slot: PlayerSlot) -> WorkoutRiderState:
	var r := WorkoutRiderState.new()
	r.peer_id = slot.peer_id
	r.slot_index = slot.slot_index
	r.name = slot.name
	r.ftp = slot.ftp if slot.ftp > 0.0 else 200.0
	r.ftp_verified = slot.ftp_verified
	r.is_bot = slot.is_bot
	r.speed = SpeedModel.create(slot.rider_mass_kg if slot.rider_mass_kg > 0.0 else 75.0)
	return r


func distance_m() -> float:
	return speed.distance_m


func speed_mps() -> float:
	return speed.v_mps


## Session time in band, 0..1 (cool-down excluded).
func tib_fraction() -> float:
	return tib_s / ride_s if ride_s > 0.0 else 0.0


## Time in band of one interval, 0..1.
func interval_fraction(index: int) -> float:
	var iv: Array = intervals.get(index, [0.0, 0.0])
	return float(iv[0]) / float(iv[1]) if float(iv[1]) > 0.0 else 0.0


func add_interval_time(index: int, in_band_now: bool, dt: float) -> void:
	var iv: Array = intervals.get(index, [0.0, 0.0])
	if in_band_now:
		iv[0] = float(iv[0]) + dt
	iv[1] = float(iv[1]) + dt
	intervals[index] = iv
	if in_band_now:
		tib_s += dt
	ride_s += dt

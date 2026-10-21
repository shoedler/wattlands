class_name RideRecorderApi
extends RefCounted
## The ride recorder contract (BRIEF 3.8). Frozen after W0; the rides agent implements
## RideRecorder (addons/wattlands/rides/ride_recorder.gd) extending this.
##
## Every session records the local rider at 1 Hz (timestamp, power, cadence, speed and
## distance from the trainer's reported speed) with a lap at each game lap_marker, at each
## plan phase marked lap, and at the start of the appended cool-down (always its own lap).
## On the results screen it writes Paths.user_dir()/rides/<UTC start>_<game>.fit and a
## JSON summary next to it. Each rider keeps only their own ride. Time comes from the
## caller (platform seconds), never the wall clock, except the UTC start stamp.


## Start a ride. `utc_start_unix` is the wall-clock start (seconds since 1970, UTC) used
## for FIT timestamps and the file name; `t` is the platform time at the start.
func start(_game_id: String, _content_id: String, _utc_start_unix: int, _t: float) -> void:
	pass


## Feed the latest values; the recorder keeps one record per second of platform time.
func record(_t: float, _power_w: float, _cadence_rpm: float, _speed_kmh: float) -> void:
	pass


## Close the current lap and open a new one named `label` at platform time `t`.
func lap(_label: String, _t: float) -> void:
	pass


## Pause/resume the timer (FIT timer stop/start events).
func set_timer_running(_running: bool, _t: float) -> void:
	pass


## Stop recording at platform time `t`.
func stop(_t: float) -> void:
	pass


func is_recording() -> bool:
	return false


## Write the FIT file and the JSON summary into `dir` (default Paths.rides_dir()).
## Returns the FIT path, or "" on failure.
func save(_dir: String = "") -> String:
	return ""


## {ride_id (UUID), game_id, content_id, utc_start, duration_s, distance_m, records,
##  laps: [{label, start_s, duration_s, avg_power_w, ...}], kj, avg_power_w, max_power_w,
##  avg_cadence_rpm, max_cadence_rpm, fit_path}
func summary() -> Dictionary:
	return {}

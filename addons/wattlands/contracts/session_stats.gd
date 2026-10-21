class_name SessionStats
extends RefCounted
## Per-rider ride statistics the GameHost accumulates from telemetry for the results
## screen (`ctx.stats`). Contract, frozen after W0; the sdk-runtime implements the
## accumulation (see SessionStatsTracker). Units: watts, seconds, kJ.
##
## Generic time in band: in ERG, power within +-5% of the applied target; in SIM, power
## inside the band published with ctx.hud.power_band (no band: not counted). Games with
## their own definition (BRIEF 3.7) override the row values.


## {kj, avg_power_w, avg_ftp_pct, np_w, best_1m_w, best_5m_w, best_20m_w, ride_s,
##  time_in_band_s, time_in_band_pct} for `peer` (zeros if unknown).
func base_row(_peer: int) -> Dictionary:
	return {
		"kj": 0.0,
		"avg_power_w": 0.0,
		"avg_ftp_pct": 0.0,
		"np_w": 0.0,
		"best_1m_w": 0.0,
		"best_5m_w": 0.0,
		"best_20m_w": 0.0,
		"ride_s": 0.0,
		"time_in_band_s": 0.0,
		"time_in_band_pct": 0.0,
	}


## Best average power over `window_s` seconds so far for `peer`.
func best_power(_peer: int, _window_s: float) -> float:
	return 0.0


## Total work so far for `peer`, kJ.
func kj(_peer: int) -> float:
	return 0.0

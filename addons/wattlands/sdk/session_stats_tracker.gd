class_name SessionStatsTracker
extends SessionStats
## Accumulates per-rider ride statistics from each sim frame's telemetry on the authority
## (`ctx.stats`, BRIEF 3.6, 3.7; docs/OWNERSHIP.md CTX15, RES1). The GameHost calls
## add_sample() once per game tick (not while paused) for every rider in ctx.players.
##
##   kj               work, sum(power x dt) / 1000
##   ride_s           game seconds sampled
##   avg_power_w      kJ x 1000 / ride_s;  avg_ftp_pct = avg_power_w / FTP x 100
##   np_w             normalized power: 30 s rolling average of the 1 s means, 4th-power
##                    mean, 4th root (rides shorter than 30 s: the average power)
##   best_1m/5m/20m_w the best rolling average over 60/300/1200 whole seconds (0 when the
##                    ride is shorter than the window)
##   time_in_band_s   ERG: |power - applied target| <= 5% of the applied target;
##                    SIM: power inside the published power band (ctx.hud.power_band);
##                    SIM without a band and ERG without a target are not counted
##   time_in_band_pct time_in_band_s / the seconds that could count x 100
## Games with their own definition (BRIEF 3.7) override the row values in results().

const NP_WINDOW_S := 30
const BAND_TOLERANCE := 0.05


class RiderStats:
	extends RefCounted
	var ftp: float = 200.0
	var joules: float = 0.0
	var ride_s: float = 0.0
	var band_s: float = 0.0
	var eligible_s: float = 0.0
	## Mean power of each whole second.
	var seconds: PackedFloat64Array = PackedFloat64Array()
	var bucket_j: float = 0.0
	var bucket_s: float = 0.0


var _riders: Dictionary = {}


func add_rider(peer: int, ftp_w: float) -> void:
	var r := RiderStats.new()
	r.ftp = maxf(ftp_w, 1.0)
	_riders[peer] = r


func has_rider(peer: int) -> bool:
	return _riders.has(peer)


## One sample of `dt` game seconds. `band_lo`/`band_hi` is the rider's published power band
## (0, 0 = none).
func add_sample(peer: int, dt: float, power_w: float, mode: String, applied_target_w: float, band_lo: float = 0.0, band_hi: float = 0.0) -> void:
	var r: RiderStats = _riders.get(peer)
	if r == null or dt <= 0.0:
		return
	var p := maxf(power_w, 0.0)
	r.joules += p * dt
	r.ride_s += dt
	if mode == Wl.ERG and applied_target_w > 0.0:
		r.eligible_s += dt
		if absf(p - applied_target_w) <= BAND_TOLERANCE * applied_target_w + 1e-9:
			r.band_s += dt
	elif mode == Wl.SIM and band_hi > 0.0:
		r.eligible_s += dt
		if p >= band_lo - 1e-9 and p <= band_hi + 1e-9:
			r.band_s += dt
	r.bucket_j += p * dt
	r.bucket_s += dt
	if r.bucket_s >= 1.0 - 1e-9:
		r.seconds.append(r.bucket_j / r.bucket_s)
		r.bucket_j = 0.0
		r.bucket_s = 0.0


## {kj, avg_power_w, avg_ftp_pct, np_w, best_1m_w, best_5m_w, best_20m_w, ride_s,
##  time_in_band_s, time_in_band_pct} for `peer` (zeros if unknown).
func base_row(peer: int) -> Dictionary:
	var r: RiderStats = _riders.get(peer)
	if r == null:
		return super.base_row(peer)
	var avg := r.joules / r.ride_s if r.ride_s > 0.0 else 0.0
	return {
		"kj": r.joules / 1000.0,
		"avg_power_w": avg,
		"avg_ftp_pct": avg / r.ftp * 100.0,
		"np_w": np_w(peer),
		"best_1m_w": best_power(peer, 60.0),
		"best_5m_w": best_power(peer, 300.0),
		"best_20m_w": best_power(peer, 1200.0),
		"ride_s": r.ride_s,
		"time_in_band_s": r.band_s,
		"time_in_band_pct": r.band_s / r.eligible_s * 100.0 if r.eligible_s > 0.0 else 0.0,
	}


## Best average power over `window_s` whole seconds so far for `peer` (0 if shorter).
func best_power(peer: int, window_s: float) -> float:
	var r: RiderStats = _riders.get(peer)
	if r == null:
		return 0.0
	var n := int(roundf(window_s))
	if n <= 0 or r.seconds.size() < n:
		return 0.0
	var sum := 0.0
	for i in n:
		sum += r.seconds[i]
	var best := sum
	for i in range(n, r.seconds.size()):
		sum += r.seconds[i] - r.seconds[i - n]
		best = maxf(best, sum)
	return best / n


## Total work so far for `peer`, kJ.
func kj(peer: int) -> float:
	var r: RiderStats = _riders.get(peer)
	return r.joules / 1000.0 if r != null else 0.0


## Normalized power so far (see the class comment).
func np_w(peer: int) -> float:
	var r: RiderStats = _riders.get(peer)
	if r == null or r.ride_s <= 0.0:
		return 0.0
	if r.seconds.size() < NP_WINDOW_S:
		return r.joules / r.ride_s
	var sum := 0.0
	for i in NP_WINDOW_S:
		sum += r.seconds[i]
	var acc := pow(sum / NP_WINDOW_S, 4.0)
	var count := 1
	for i in range(NP_WINDOW_S, r.seconds.size()):
		sum += r.seconds[i] - r.seconds[i - NP_WINDOW_S]
		acc += pow(sum / NP_WINDOW_S, 4.0)
		count += 1
	return pow(acc / count, 0.25)


func time_in_band_s(peer: int) -> float:
	var r: RiderStats = _riders.get(peer)
	return r.band_s if r != null else 0.0


func ride_s(peer: int) -> float:
	var r: RiderStats = _riders.get(peer)
	return r.ride_s if r != null else 0.0

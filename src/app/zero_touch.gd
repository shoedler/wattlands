class_name AppZeroTouch
extends RefCounted
## Zero-touch start on the title screen (BRIEF 3.5).
##   - With a saved profile, holding pedal_start for 5 s starts the last-played game solo with
##     its zero_input_content.
##   - First run (no profile) with no input: 20 s of pedaling creates a profile called Rider
##     (FTP 200, unverified) and starts the first-run game solo.
## "Pedaling" is the pedal_start condition (cadence >= 40 rpm or power >= 30% FTP), held
## continuously: the stretch starts at the first sample that meets it and breaks at the first
## sample that doesn't. Time comes only from the samples (TrainerSample.t, platform time), so
## the rule is exact at any sim speed and testable with a synthetic stream.
## With fresh_start (the title again after a ride or a menu, not the launch visit), a stretch
## that was already running when the title opened does not count: the hold starts only after a
## sample without pedaling, so a rider still spinning after Continue never restarts a ride.

const PEDAL_START_CADENCE_RPM := 40.0
const PEDAL_START_FTP_FRACTION := 0.30
const HOLD_START_S := 5.0
const FIRST_RUN_S := 20.0

var ftp_w: float = 200.0
## Seconds of pedaling needed (5 s with a profile, 20 s on the first run).
var hold_s: float = HOLD_START_S
## False once cancelled (a device action, or the rider backing out); stays fired once fired.
var armed: bool = true
var fired: bool = false
## True once any sample in a countable stretch met the pedaling condition (since configure()).
var pedaled: bool = false
## True until the first sample without pedaling when configured with fresh_start.
var need_fresh: bool = false
## Length of the current pedaling stretch in seconds.
var held_s: float = 0.0
var _start_t: float = -1.0


## `first_run` true: 20 s rule; false: 5 s rule. `fresh_start`: ignore a stretch already running
## (see above). Re-arms the tracker.
func configure(p_ftp_w: float, first_run: bool, fresh_start: bool = false) -> void:
	ftp_w = maxf(p_ftp_w, 1.0)
	hold_s = FIRST_RUN_S if first_run else HOLD_START_S
	armed = true
	fired = false
	pedaled = false
	need_fresh = fresh_start
	held_s = 0.0
	_start_t = -1.0


## The pedal_start condition on one sample.
func is_pedaling(power_w: float, cadence_rpm: float) -> bool:
	return cadence_rpm >= PEDAL_START_CADENCE_RPM or power_w >= PEDAL_START_FTP_FRACTION * ftp_w


## Feed one trainer sample. Returns true exactly once: on the sample that completes the hold.
func feed(sample: TrainerSample) -> bool:
	if sample == null:
		return false
	var cadence := sample.cadence_rpm if sample.has_cadence() else 0.0
	return feed_values(sample.t, sample.power_w, cadence)


func feed_values(t: float, power_w: float, cadence_rpm: float) -> bool:
	if is_pedaling(power_w, cadence_rpm) and not need_fresh:
		pedaled = true
		if _start_t < 0.0 or t < _start_t:
			_start_t = t
		held_s = t - _start_t
	else:
		if not is_pedaling(power_w, cadence_rpm):
			need_fresh = false
		_start_t = -1.0
		held_s = 0.0
	if not armed or fired:
		return false
	if _start_t >= 0.0 and held_s >= hold_s - 1e-6:
		fired = true
		return true
	return false


## Stop the countdown for good (until configure()).
func cancel() -> void:
	armed = false


## 0..1 progress of the current stretch toward the hold (0 when disarmed).
func progress() -> float:
	if not armed or fired:
		return 0.0
	return clampf(held_s / hold_s, 0.0, 1.0)


## Whole seconds left in the countdown (0 when not pedaling).
func seconds_left() -> int:
	if _start_t < 0.0 or not armed:
		return 0
	return int(ceil(maxf(hold_s - held_s, 0.0)))

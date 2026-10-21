class_name CadenceEstimator
extends RefCounted
## Cadence when the trainer doesn't report it (BRIEF 4.5): use FTMS cadence when present;
## estimate it from flywheel speed when absent or stale (older than `stale_s`), learning the
## speed-to-cadence ratio while both are valid, or from a 10 s calibration at 90 rpm.
## Owned by trainer-control; public API frozen after W0. LocalRider passes every sample
## through process() before gestures, the governor and telemetry use it.

var stale_s: float = 3.0


## Returns `sample` (or a copy) with cadence filled in and TrainerSample.CADENCE_ESTIMATED
## set when it had to be estimated; unchanged when cadence is present and fresh or no ratio
## is known yet.
func process(sample: TrainerSample) -> TrainerSample:
	return sample


## Start a 10 s calibration: the rider holds 90 rpm; samples during it set the ratio.
func start_calibration(_target_rpm: float = 90.0) -> void:
	pass


func is_calibrating() -> bool:
	return false


## Learned km/h per rpm (0 when unknown).
func ratio() -> float:
	return 0.0

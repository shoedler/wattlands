class_name GestureRecognizer
extends RefCounted
## Pedal gestures from a rider's sample stream (BRIEF 3.5). Owned by sim; public API frozen
## after W0. Unit-tested on synthetic streams.
##   pedal_start: cadence >= 40 rpm or power >= 30% FTP for 3 s.
##   surge (confirm): outside ERG, power >= max(1.3 x its 10 s average, 10 s average + 40 W)
##     for 1.5 s (two consecutive ~1 Hz samples); inside ERG, flywheel speed >= 1.12 x its
##     10 s average for 1.5 s.
##   not_pedaling (shared detector): power < 15 W and cadence < 20 rpm. Drives coast,
##     stop_5s and the governor's coasting rule (4.6.4).
##   coast (back): not_pedaling for 3 s, never during ERG.
##   stop_5s (pause): not_pedaling for 5 s, solo and outside ERG only.
## Arbitration: within one stop, coast fires once at 3 s and stop_5s once at 5 s (each only
## where allowed); surge never fires while not_pedaling; pedal_start fires once per start
## (re-armed after not_pedaling).
## Time comes from the samples (TrainerSample.t, platform time); never the wall clock.

## A gesture fired (Wl.G_*).
signal gesture(gesture_name: StringName)


## ftp_w for the 30% rule; solo enables stop_5s.
func configure(_ftp_w: float, _solo: bool) -> void:
	pass


## Whether the rider's trainer is in ERG right now (switches surge to the speed rule and
## suppresses coast/stop_5s).
func set_erg(_in_erg: bool) -> void:
	pass


## Feed one sample; returns the gestures fired by it (also emitted).
func on_sample(_sample: TrainerSample) -> Array[StringName]:
	return []


## The shared not_pedaling detector on a single sample.
static func is_not_pedaling(power_w: float, cadence_rpm: float) -> bool:
	return power_w < 15.0 and cadence_rpm < 20.0


## True while the latest sample meets not_pedaling.
func not_pedaling() -> bool:
	return false


## Seconds the current not_pedaling stretch has lasted (from its first sample).
func not_pedaling_s() -> float:
	return 0.0


func reset() -> void:
	pass

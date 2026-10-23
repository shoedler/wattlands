class_name FishingStepOut
extends RefCounted
## What one FishingRules.step asks the platform to do (G0 contract). The rules stay pure: they
## never call ctx; FishingGame applies these in this order, in the same tick: directives
## (ctx.directives.request), bands (cadence_band), end_phase, events (send_event), toasts, then
## finished.

## [[peer, EffortDirective dictionary], ...] in send order (ERG pulls, runs, the landing haptic).
var directives: Array = []
## [[peer, lo_rpm, hi_rpm], ...] (ints; [peer, 0, 0] clears the band).
var bands: Array = []
## Peers whose open-ended phase ends this tick (only once its min_s has passed).
var end_phase: Array[int] = []
## FishingEvents dictionaries in emission order.
var events: Array = []
## [[key, args, peer], ...]: HUD toasts for one rider's own peer (peer 0 = everyone).
var toasts: Array = []
## "trip_over" once fishing time is up and no Fight or Landing is on; "" otherwise.
var finished: String = ""

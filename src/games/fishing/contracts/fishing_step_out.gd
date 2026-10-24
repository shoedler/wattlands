class_name FishingStepOut
extends RefCounted
## What one FishingRules.step asks the platform to do (contract v2). The rules stay pure: they
## never call ctx; FishingGame applies these in this order, in the same tick: replans
## (ctx.directives.replan), directives (request), grades (course_grade), bands (cadence_band),
## power bands (ctx.hud.power_band, bots only), end_phase, events (send_event), toasts, then
## finished.

## [[peer, EffortPlan], ...]: the rest of a rider's plan (Free Roam: a fight, its landing, a Roam).
var replans: Array = []
## [[peer, EffortDirective dictionary], ...] in send order (ERG pulls, runs, the landing haptic).
var directives: Array = []
## [[peer, grade_pct], ...]: the driving load in a grade_source "game" phase.
var grades: Array = []
## [[peer, lo_rpm, hi_rpm], ...] (ints; [peer, 0, 0] clears the band).
var bands: Array = []
## [[peer, lo_w, hi_w], ...]: a bot's power band (it rides the centre in SIM).
var power_bands: Array = []
## Peers whose open-ended phase ends this tick (only once its min_s has passed).
var end_phase: Array[int] = []
## FishingEvents dictionaries in emission order.
var events: Array = []
## [[key, args, peer], ...]: HUD toasts for one rider's own peer (peer 0 = everyone).
var toasts: Array = []
## "trip_over" once play time is up and no fight is on (or the overtime ran out); "" otherwise.
var finished: String = ""

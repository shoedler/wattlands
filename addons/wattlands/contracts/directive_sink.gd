class_name DirectiveSink
extends RefCounted
## The only way a game changes trainer load (BRIEF 3.6, `ctx.directives`). Contract,
## frozen after W0; the sdk-runtime implements it (addons/wattlands/sdk/).
##
## On the host (and in SOLO) the sink validates each call against the rider's plan and
## current phase, then routes it to that rider's governor: a local rider's governor
## directly, a remote rider's through a 5.5 `directive` message, where the client's
## governor validates and clamps it again and reports what it applied. On a CLIENT the
## calls are ignored with a warning (only the authority simulates).
##
## Channel edge cases (sink and governor agree): a haptic for a rider in ERG refuses the
## whole request; `mode: SIM` while a SIM block is running only confirms it (never extends
## it); `mode: ERG` in an ERG phase ends a running block, or confirms when none runs; a
## haptic dropped because the rider opted out, is in warm-up or is inside the 15 s haptic
## cooldown is reported in the applied record's `dropped` list and the rest of the request
## applies.
##
## Every refusal is logged with push_warning and reported (DirectiveResult and the
## EventBus `directive_applied` record). Applied values, `clamped_by` and refusals reach
## `EventBus.directive_applied(peer, record)` on the host for every rider.


## Request an EffortDirective for `peer` (see EffortDirective for channels and expiry).
## Refused (accepted = false) when: no active phase or the cool-down is running;
## an ERG target is outside the phase's range_pct; a SIM block (mode SIM in an ERG phase)
## has duration_s outside [10, 30] or starts < 30 s after the rider's previous ERG<->SIM
## switch; mode_grade is set outside a SIM block or SIM phase; a haptic targets a rider in
## ERG (dropped and logged, never a mode switch). The governor clamps what is accepted.
func request(_peer: int, _directive: EffortDirective) -> DirectiveResult:
	return DirectiveResult.refused(Wl.REFUSE_NOT_AUTHORITY)


## Course grade for a phase with grade_source "game" (coalesced to 2 Hz, stacked by 4.6.6).
func course_grade(_peer: int, _grade_pct: float) -> void:
	pass


## End `peer`'s open-ended phase. Returns false (and warns) before min_s or if the
## current phase is not open-ended.
func end_phase(_peer: int) -> bool:
	return false


## Publish the cadence band the game wants for `peer` (drawn by the HUD cadence widget,
## followed by bots and MockTrainer's `band` policy; never changes trainer load).
## Holds across phases until replaced; (0, 0) clears it; the cool-down clears every band.
func cadence_band(_peer: int, _lo_rpm: float, _hi_rpm: float) -> void:
	pass


## Replace `peer`'s remaining plan between phases. The new plan holds the phases after
## the current one; it is validated like the original (warm-up and 4.6.1 rules on the
## whole resulting plan) and the cool-down is re-appended. Returns false if rejected.
func replan(_peer: int, _plan: EffortPlan) -> bool:
	return false

class_name SafetyGovernor
extends Node
## The only path that can change trainer resistance (BRIEF 3.1 pillar 5, 4.6). One per
## rider (local riders, bots and every in-process MockTrainer rider). Owned by
## trainer-control; the public API below is frozen after W0 (additive changes only).
##
## Structure (4.6.11): only SafetyGovernor holds a TrainerController; only the
## controller calls TrainerDevice setters. Everything a game asks for arrives as an
## EffortPlan (set_plan + start_phase) plus EffortDirectives, course grades and gear shifts;
## the governor turns them into one applied ERG target or SIM state per tick, applying in
## order (4.6.12): panic > [plan/directive target x unverified factor, limited by the
## ceilings, the long-phase cap, duration limits and the warm-up cap] > rescue 50% >
## coasting floor > the floor (wins over every cap and over rescue) > slew (increases only).
## SIM grade follows 4.6.6 stacking. Mode switches are ramped (4.5).
##
## Time: tick(dt) advances every time-based rule on PLATFORM time (fixed 0.05 s steps);
## phase-relative values (ramps, directive expiry) count game time, which stops while
## set_game_paused(true). on_sample() feeds trainer samples (about 1 Hz). Never reads the
## wall clock, so headless runs at any sim speed are exact.
##
## Status dictionary (status(), status_changed, Telemetry fields):
##   mode ("ERG"/"SIM"/"OFF"), applied_target_w (int), applied_pct, applied_grade_pct,
##   wind_mps, crr, cw, haptic_active, clamped_by (Array[String], Wl.CLAMP_*), rescue,
##   coasting, afk, paused, panic, warmup_active, warmup_remaining_s, gear (1..24),
##   s_left_105, s_left_120, latched_105, latched_120, phase_index, phase_elapsed_s,
##   sim_block_active, last_switch_t, profile ("normal"/"ramp_test").

## Any status field changed (at most once per tick).
signal status_changed(status: Dictionary)
signal rescue_changed(active: bool)
signal coasting_changed(active: bool)
## Coasting for 10 s (4.6.4): SOLO pauses, multiplayer marks AFK. `multiplayer` comes from
## configure(). Emitted once when the 10 s pass; cleared when pedaling resumes.
signal pause_requested(reason: String)
signal afk_changed(afk: bool)
## What happened to a directive, course grade or band: {id, kind, requested: {...},
## applied: {...}, clamped_by: [...], refused: bool, reason: String, t: float}.
signal directive_applied(record: Dictionary)
signal warmup_changed(active: bool)
signal panic_changed(active: bool)


## Bind the device (the governor creates and owns its TrainerController around it).
func setup(_device: TrainerDevice) -> void:
	pass


## Rider and safety parameters. Keys (all optional, defaults from BRIEF 3.2/4.6):
##   ftp_w (200), ftp_verified (false), difficulty_pct (50), grade_min_pct (-5),
##   grade_max_pct (10), haptics_on (true), haptic_intensity (0.7, 0..1),
##   skip_warmup (false), multiplayer (false: coasting pauses; true: marks AFK),
##   crr (0.004), cw (0.51), trainer_max_w (from the device's power range),
##   profile ("normal" or "ramp_test", BRIEF 3.2).
func configure(_params: Dictionary) -> void:
	pass


## The rider's validated plan (cool-down appended). Resets channel state.
func set_plan(_plan: EffortPlan) -> void:
	pass


## Enter phase `index` (elapsed 0). The platform calls it on every phase change (duration,
## max_s, end_phase, finished, rejoin). Directive channels revert to the plan; the
## cool-down clears every directive.
func start_phase(_index: int) -> void:
	pass


## Pause (4.1): the game clock stops; the trainer goes to the ERG floor or SIM flat;
## telemetry, rescue, coasting and panic keep working.
func set_game_paused(_paused: bool) -> void:
	pass


## Validate and clamp a directive for this rider; returns the applied record (also
## emitted as directive_applied). Refuses (record.refused = true, push_warning) anything
## BRIEF 3.6 disallows: outside range_pct, SIM block length or spacing, mode_grade outside
## SIM, haptics in ERG / warm-up / opted out / in cooldown, during the cool-down.
func apply_directive(_directive: EffortDirective) -> Dictionary:
	return {}


## Course grade for grade_source "game" phases (coalesced by the controller).
func set_course_grade(_grade_pct: float) -> void:
	pass


## The rider's distance from the speed model, for grade_source "course" phases.
func set_course_distance(_distance_m: float) -> void:
	pass


## Virtual gears (4.5): +1 / -1 steps within 1..24. Returns the new gear.
func shift(_delta: int) -> int:
	return 12


## Feed a trainer sample (power, cadence, speed): rescue, coasting, warm-up, 3 s power.
func on_sample(_sample: TrainerSample) -> void:
	pass


## Advance every time-based rule by dt platform seconds and command the controller.
func tick(_dt: float) -> void:
	pass


## Panic (4.6.5): ERG off, SIM grade 0 and wind 0 immediately; stays safe until resume().
func emergency_safe() -> void:
	pass


## Leave the panic state (the player resumed). The plan resumes from the floor with slew.
func resume() -> void:
	pass


## Exit, crash and disconnect paths (4.6.9): try SIM flat, then Stop (0x08 0x01).
func shutdown() -> void:
	pass


func status() -> Dictionary:
	return {}


func is_rescue() -> bool:
	return false


func is_coasting() -> bool:
	return false


func is_warmup_active() -> bool:
	return true

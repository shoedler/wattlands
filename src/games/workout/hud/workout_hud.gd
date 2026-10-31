class_name WorkoutHud
extends RefCounted
## Workout's HUD (BRIEF 3.7, 3.9): which kit widgets show where, and the host-side calls
## that feed them through ctx.hud (banners at interval starts, sprint countdowns and
## results, interval results, teammate compliance, the Rolling road and sprint power
## bands, and the local rider's in-band readout).
##
## Layout: the phase timeline top centre; big readouts (watts, then time in band) top
## right; power gauge, cadence and W' bottom left; the teammate strip bottom centre; the
## gear indicator bottom right (the kit shows it whenever the trainer is in SIM: sprints and
## Rolling road); toasts top left, banners top centre.

const READOUT_TIB := "workout_tib"
## Teammate status refresh (sim steps) when nothing flips.
const STATUS_EVERY_TICKS := 20
## Local in-band readout refresh (sim steps).
const READOUT_EVERY_TICKS := 10
const SPRINT_WARN_S := 10.0
const BANNER_S := 4.0
## Sprint power band shown on the gauge (x FTP) outside the warm-up (the rule needs 1.2).
const SPRINT_BAND := [1.2, 1.6]
## The first 300 s of the plan are the warm-up (BRIEF 4.6.8): no sprint band there.
const WARMUP_S := 300.0


static func spec(_game: WorkoutGame = null) -> HudSpec:
	return (
		HudSpec
		. new()
		. add(HudSpec.TIMELINE, HudSpec.TOP)
		. add(
			HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "power_w", "label": "WORKOUT_HUD_WATTS"}
		)
		. add(
			HudSpec.READOUT,
			HudSpec.TOP_RIGHT,
			{"source": "custom", "id": READOUT_TIB, "label": "WORKOUT_HUD_IN_BAND"}
		)
		. add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.CADENCE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.WBAL, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.TEAMMATES, HudSpec.BOTTOM)
		. add(HudSpec.GEAR, HudSpec.BOTTOM_RIGHT)
		. toasts_at(HudSpec.TOP_LEFT)
		. banners_at(HudSpec.TOP)
	)


## The power band (W) for `rider` in SIM phase `index`, or [] for none:
## Rolling road: the session band (76-105% FTP); a FREE sprint after the warm-up:
## 120-160% FTP; a sprint inside the first 300 s: none (the rider stays easy there); a
## longer FREE phase (free riding, WorkoutSession.is_sprint false): none.
static func band_for(state: WorkoutState, index: int, rider: WorkoutRiderState) -> Array:
	var p := state.phase(index)
	if p == null or p.mode != Wl.SIM:
		return []
	if p.kind == Wl.FREE:
		if state.phase_start_s(index) < WARMUP_S or not WorkoutSession.is_sprint(p):
			return []
		return [float(SPRINT_BAND[0]) * rider.ftp, float(SPRINT_BAND[1]) * rider.ftp]
	return [
		float(state.band_pct[0]) / 100.0 * rider.ftp, float(state.band_pct[1]) / 100.0 * rider.ftp
	]


## Banner key and args for the start of phase `index` ({} for none: the cool-down has the
## platform's own).
static func interval_banner(state: WorkoutState, index: int, strings: GameStrings) -> Dictionary:
	var p := state.phase(index)
	if p == null or p.kind == Wl.COOLDOWN:
		return {}
	var args := {"label": strings.t(p.label), "time": WorkoutSession.clock(p.duration_s)}
	if p.mode == Wl.ERG:
		if p.has_ramp():
			args["from"] = int(round(p.target_pct))
			args["to"] = int(round(p.ramp_to_pct))
			return {"key": "WORKOUT_BANNER_RAMP", "args": args}
		args["pct"] = int(round(p.target_pct))
		return {"key": "WORKOUT_BANNER_ERG", "args": args}
	if p.kind == Wl.FREE:
		return {
			"key":
			"WORKOUT_BANNER_SPRINT" if WorkoutSession.is_sprint(p) else "WORKOUT_BANNER_FREE",
			"args": args
		}
	args["lo"] = int(round(float(state.band_pct[0])))
	args["hi"] = int(round(float(state.band_pct[1])))
	return {"key": "WORKOUT_BANNER_ROLLING", "args": args}


## "94%" for a 0..1 fraction.
static func pct_text(fraction: float) -> String:
	return "%d%%" % int(round(clampf(fraction, 0.0, 1.0) * 100.0))

class_name SiegeCockpitModel
extends RefCounted
## What the cockpit says to the local rider (docs/games/siege.md 3 "HUD"): one source for each
## value, as data the tests read. Feed it the local telemetry every tick (HudRiderNumbers holds the
## 3 s power, stale power, band hysteresis, heart rate and low-cadence rules); face(game) gives:
##   "clock_cap", "clock", "clock_soon"           the interval clock (gold in the last 30 s to a step up)
##   "target_cap", "applied_w"                    the applied target from telemetry, never the plan
##   "w_text", "w" (-1: stale), "pct_text", "state", "wkg" ("" unless opted in)
##   "band" (Vector2, ZERO: none), "scale"        the watts gauge
##   "cad_text", "cad", "cad_cap", "cad_low", "cad_nudge", "cad_stale", "cband"
##   "hr": HudRiderNumbers.HR_*, "hr_text"        no cell at HR_NONE, the plate narrows ("wide")
##   "line", "line_kind" (LINE_*), "line_alarm"   the one instruction, by state
##   "sim", "gear"                                the chip and the gear only in SIM
##   "next", "wbal", "wbal_text"                  what comes next; W' with a number below 50%
##   "name", "station", "slot", "shape", "color"  whose plate this is

const LINE_SPIN := "spin"
const LINE_WARMUP := "warmup"
const LINE_LOAD_UP := "load_up"
const LINE_LOW := "low"
const LINE_RESCUE := "rescue"
const LINE_COAST := "coast"
const LINE_SPRINT := "sprint"
const LINE_HOLD := "hold"
const LINE_EASE := "ease"
const LINE_NO_DATA := "no_data"
const LINE_COOL := "cool"
## The last seconds before a step up, and how much higher the next target must be to be one.
const LOAD_UP_S := 30.0
const STEP_UP_FACTOR := 1.05
const WBAL_NUMBER_BELOW := 0.5
## The watts gauge runs to this share of FTP.
const SCALE_FTP := 1.6

var numbers := HudRiderNumbers.new()
var tm: Telemetry = null
## >= 0 overrides the W/kg weight (HudLayer.wkg_weight_kg; tests).
var wkg_override_kg: float = -1.0


func feed(t: Telemetry) -> void:
	if t == null:
		return
	tm = t
	numbers.feed(t)


## The cockpit's face for the local rider ({} without one).
func face(game: SiegeGame) -> Dictionary:
	var r := SiegeHudModel.own_rider(game)
	if r == null:
		return {}
	var s := game.state
	numbers.ftp_w = r.ftp
	if tm == null:
		numbers.push_power(s.t, r.raw_w)
	var tx := SiegeHudModel.strings_of(game)
	var plan := game.hud_plan(r.peer)
	var ph := plan.phase(s.phase_index)
	var next := plan.phase(s.phase_index + 1)
	var rescue := tm.rescue if tm != null else r.rescue
	var coasting := tm.coasting if tm != null else false
	var od_on := r.od_state == SiegeIds.OD_ACTIVE
	var sim := tm.mode == Wl.SIM if tm != null else od_on
	var applied := tm.applied_target_w if tm != null and tm.mode == Wl.ERG else 0
	var sprint := SiegeOverdrive.band_w(s.content, r.ftp)
	var soon := _load_up_soon(s, r, ph, next, od_on)
	_feed_band(sim, od_on, applied, sprint)
	var out := {}
	_clock(out, s, r, tx, od_on, soon)
	_target(out, s, r, tx, ph, rescue, od_on, applied, sprint)
	_watts(out, r)
	_cadence(out, s, r, tx, rescue)
	_heart(out)
	_line(out, s, tx, rescue, coasting, od_on, soon, sprint)
	_next(out, s, r, tx, ph, next, rescue, od_on)
	out["sim"] = sim
	out["gear"] = tm.gear if tm != null else 12
	var wbal := tm.wbal_j / maxf(HudRiderNumbers.wprime_j(), 1.0) if tm != null else 1.0
	out["wbal"] = clampf(wbal, 0.0, 1.0)
	out["wbal_text"] = "%d%%" % roundi(out["wbal"] * 100.0) if wbal < WBAL_NUMBER_BELOW else ""
	var look := SiegeHudModel.look_of(game, r.slot)
	out["name"] = SiegeHudModel.rider_name(game, r)
	out["station"] = tx.t(SiegeGame.station_key(r.target))
	out["slot"] = r.slot
	out["shape"] = str(look["shape"])
	out["color"] = look["color"]
	return out


func _feed_band(sim: bool, od_on: bool, applied: int, sprint: Vector2) -> void:
	if numbers.is_stale():
		numbers.set_band(0.0, 0.0)
	elif od_on:
		numbers.set_band(sprint.x, sprint.y)
	elif applied > 0 and not sim:
		var a := float(applied)
		numbers.set_band(a * (1.0 - SiegeHudModel.ERG_BAND), a * (1.0 + SiegeHudModel.ERG_BAND))
	else:
		numbers.set_band(0.0, 0.0)


## True in the last LOAD_UP_S of a phase when the next phase's target is a step up from this one's.
func _load_up_soon(
	s: SiegeState, r: SiegeRiderState, ph: PlanPhase, next: PlanPhase, od_on: bool
) -> bool:
	if ph == null or next == null or od_on:
		return false
	if SiegeHudModel.phase_remaining_s(s) > LOAD_UP_S:
		return false
	var now := SiegeHudModel.applied_w(
		ph.ramp_to_pct if ph.has_ramp() else ph.target_pct, r.ftp, r.ftp_verified
	)
	var then := SiegeHudModel.applied_w(next.target_pct, r.ftp, r.ftp_verified)
	return float(then) > float(now) * STEP_UP_FACTOR


func _clock(
	out: Dictionary, s: SiegeState, r: SiegeRiderState, tx: GameStrings, od_on: bool, soon: bool
) -> void:
	var left := SiegeHudModel.phase_remaining_s(s)
	var cap := "SIEGE_HUD_CAP_WAVE"
	match s.role:
		SiegeIds.ROLE_WARMUP_WAVE:
			cap = "SIEGE_HUD_CAP_WARMUP"
		SiegeIds.ROLE_BUILD_BREAK, SiegeIds.ROLE_BREAK:
			cap = "SIEGE_HUD_CAP_BREAK"
		SiegeIds.ROLE_COOLDOWN:
			cap = "SIEGE_HUD_CAP_COOLDOWN"
	if od_on:
		cap = "SIEGE_HUD_CAP_SPRINT"
		left = r.od_s
	out["clock_cap"] = tx.t(cap)
	out["clock"] = HudWidget.clock_text(left)
	out["clock_soon"] = soon


func _target(
	out: Dictionary,
	s: SiegeState,
	r: SiegeRiderState,
	tx: GameStrings,
	ph: PlanPhase,
	rescue: bool,
	od_on: bool,
	applied: int,
	sprint: Vector2
) -> void:
	out["applied_w"] = 0 if numbers.is_stale() else applied
	if numbers.is_stale():
		out["target_cap"] = tx.t("SIEGE_HUD_TARGET_NONE")
	elif od_on:
		out["target_cap"] = tx.t("SIEGE_HUD_TARGET_SPRINT", [roundi(sprint.x), roundi(sprint.y)])
	elif applied <= 0:
		out["target_cap"] = tx.t("SIEGE_HUD_TARGET_NONE")
	elif rescue:
		out["target_cap"] = tx.t("SIEGE_HUD_TARGET_RESCUE", [applied])
	elif ph != null and ph.has_ramp() and s.phase_elapsed_s < ph.duration_s:
		var end := SiegeHudModel.applied_w(ph.ramp_to_pct, r.ftp, r.ftp_verified)
		out["target_cap"] = tx.t("SIEGE_HUD_TARGET_RAMP", [applied, end])
	else:
		out["target_cap"] = tx.t("SIEGE_HUD_TARGET", [applied])


func _watts(out: Dictionary, r: SiegeRiderState) -> void:
	var stale := numbers.is_stale()
	var mean := numbers.mean_power_w()
	var w := roundi(mean)
	out["w"] = -1 if stale else w
	out["w_text"] = "--" if stale else str(w)
	out["pct_text"] = "--" if stale else "%d%%" % roundi(mean / maxf(r.ftp, 1.0) * 100.0)
	out["state"] = numbers.band_state()
	out["band"] = numbers.band()
	out["scale"] = r.ftp * SCALE_FTP
	out["wkg"] = ""
	var weight := HudRiderNumbers.opted_in_weight_kg(wkg_override_kg)
	if weight > 0.0 and not stale:
		out["wkg"] = "%.1f" % (mean / weight)


func _cadence(
	out: Dictionary, s: SiegeState, r: SiegeRiderState, tx: GameStrings, rescue: bool
) -> void:
	var stale := numbers.cadence_stale()
	var rpm := tm.cadence_rpm if tm != null else r.cadence_rpm
	out["cad"] = rpm
	out["cad_stale"] = stale
	out["cad_text"] = "--" if stale else str(roundi(rpm))
	out["cband"] = Vector2(SiegeHudModel.CADENCE_LO, SiegeHudModel.CADENCE_HI)
	var recover := roundi(HudRiderNumbers.RESCUE_RECOVER_RPM)
	if rescue:
		out["cad_cap"] = tx.t("SIEGE_HUD_RPM_RESCUE", [recover])
		out["cad_low"] = not stale and rpm < HudRiderNumbers.RESCUE_RECOVER_RPM
	else:
		out["cad_cap"] = tx.t(
			"SIEGE_HUD_RPM_BAND", [SiegeHudModel.CADENCE_LO, SiegeHudModel.CADENCE_HI]
		)
		out["cad_low"] = numbers.low_cadence()
	# under the band in a wave but no alarm: a small up arrow, no chip
	out["cad_nudge"] = (
		s.in_wave()
		and not stale
		and not bool(out["cad_low"])
		and rpm >= HudRiderNumbers.LOW_CADENCE_RPM
		and rpm < float(SiegeHudModel.CADENCE_LO)
	)


func _heart(out: Dictionary) -> void:
	var hr := numbers.heart_state()
	out["hr"] = hr
	out["hr_text"] = str(numbers.heart_bpm()) if hr == HudRiderNumbers.HR_LIVE else "--"


## The one instruction line. No trainer data first: a rider who is pedalling must not be told to
## pedal, and the governor counts a silent stream as coasting. Then coasting (its floor wins over
## rescue, BRIEF 4.6.12), rescue, the sprint by where the 3 s power sits in its band, the low-cadence
## warning while rescue is armed, the cool-down, the step up, the warm-up, and the steady band.
func _line(
	out: Dictionary,
	s: SiegeState,
	tx: GameStrings,
	rescue: bool,
	coasting: bool,
	od_on: bool,
	soon: bool,
	sprint: Vector2
) -> void:
	var lo := SiegeHudModel.CADENCE_LO
	var hi := SiegeHudModel.CADENCE_HI
	var kind := LINE_SPIN
	var text := tx.t("SIEGE_HUD_LINE_SPIN", [lo, hi])
	if numbers.is_stale():
		kind = LINE_NO_DATA
		text = tx.t("SIEGE_HUD_LINE_NO_DATA")
	elif coasting:
		kind = LINE_COAST
		text = tx.t("SIEGE_HUD_LINE_COAST")
	elif rescue:
		kind = LINE_RESCUE
		text = tx.t("SIEGE_HUD_LINE_RESCUE", [roundi(HudRiderNumbers.RESCUE_RECOVER_RPM)])
	elif od_on:
		kind = LINE_SPRINT
		var line_key := "SIEGE_HUD_LINE_SPRINT"
		if numbers.band_state() == HudRiderNumbers.IN_BAND:
			kind = LINE_HOLD
			line_key = "SIEGE_HUD_LINE_HOLD"
		elif numbers.band_state() == HudRiderNumbers.OVER:
			kind = LINE_EASE
			line_key = "SIEGE_HUD_LINE_EASE"
		text = tx.t(line_key, [roundi(sprint.x), roundi(sprint.y)])
	elif numbers.low_cadence():
		kind = LINE_LOW
		text = tx.t("SIEGE_HUD_LINE_LOW", [roundi(HudRiderNumbers.RESCUE_LOW_RPM)])
	elif s.role == SiegeIds.ROLE_COOLDOWN:
		kind = LINE_COOL
		text = tx.t("SIEGE_HUD_LINE_COOL")
	elif soon:
		kind = LINE_LOAD_UP
		text = tx.t(
			"SIEGE_HUD_LINE_LOAD_UP", [HudWidget.clock_text(SiegeHudModel.phase_remaining_s(s))]
		)
	elif s.role == SiegeIds.ROLE_WARMUP_WAVE or s.phase_kind == Wl.WARMUP:
		kind = LINE_WARMUP
		text = tx.t("SIEGE_HUD_LINE_WARMUP", [lo, hi])
	out["line"] = text
	out["line_kind"] = kind
	out["line_alarm"] = (
		kind == LINE_NO_DATA or kind == LINE_COAST or kind == LINE_RESCUE or kind == LINE_LOW
	)


func _next(
	out: Dictionary,
	s: SiegeState,
	r: SiegeRiderState,
	tx: GameStrings,
	ph: PlanPhase,
	next: PlanPhase,
	rescue: bool,
	od_on: bool
) -> void:
	var planned := SiegeHudModel.applied_w(
		SiegeHudModel.phase_pct(ph, s.phase_elapsed_s), r.ftp, r.ftp_verified
	)
	if rescue and ph != null:
		out["next"] = tx.t("SIEGE_HUD_THEN_RAMP", [planned])
	elif od_on and ph != null:
		out["next"] = tx.t("SIEGE_HUD_THEN_ERG", [planned])
	elif next == null:
		out["next"] = tx.t("SIEGE_HUD_NEXT_RESULTS")
	else:
		var at := SiegeHudModel.applied_w(next.target_pct, r.ftp, r.ftp_verified)
		out["next"] = tx.t(
			"SIEGE_HUD_NEXT_PHASE",
			[phase_name(next, tx), HudWidget.clock_text(next.duration_s), at]
		)


## A plan phase's short name on the next line.
static func phase_name(ph: PlanPhase, tx: GameStrings) -> String:
	if ph.kind == Wl.COOLDOWN:
		return tx.t("SIEGE_HUD_COOLDOWN")
	match str(ph.meta.get("role", "")):
		SiegeIds.ROLE_BREAK:
			return tx.t("SIEGE_HUD_NAME_BREAK")
	return tx.t(ph.label)

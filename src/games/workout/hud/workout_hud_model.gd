class_name WorkoutHudModel
extends RefCounted
## What Workout's HUD plates show, with no drawing: each plate's Control asks for one Dictionary here
## and paints it. Every HUD test goes through this class. Pure over the state, the telemetry and the
## values the Control hands in, so it never touches trainer load: the plan does that.

const GEAR_MAX := 24
## The cadence gauge's scale, and the band shown in a FREE phase with none published.
const CAD_LO := 30.0
const CAD_HI := 150.0
const FREE_CADENCE_BAND := Vector2(60.0, 140.0)
## Under this share of W' the bar turns OVER and says LOW.
const WBAL_LOW := 0.25
## The timeline's strip: one column per art px, and its height.
const TIMELINE_COLUMNS := 468
const TIMELINE_H := 20
## The ride view's interval blocks are 40 px at most on the bank (WorkoutRideView._strip_h); half here.
const TIMELINE_H_SCALE := 0.5
const TIMELINE_MIN_H := 2
## The crew plate's cards.
const CARD := Vector2i(102, 32)
const CARD_GAP := 2
const CARD_COLUMNS := 4
const CREW_X0 := 1
const FLAG_RESCUE := "WORKOUT_HUD_RESCUE"
const FLAG_AFK := "WORKOUT_HUD_AFK"
const FLAG_LINK := "WORKOUT_HUD_LINK"


## `key` translated (the game's strings, else the TranslationServer), `{0}`.. filled from `args`.
static func tx(game: WorkoutGame, key: String, args: Variant = []) -> String:
	if game != null and game.ctx != null and game.ctx.strings != null:
		return game.ctx.strings.t(key, args)
	var s := String(TranslationServer.translate(key))
	if (
		(args is Array and not (args as Array).is_empty())
		or (args is Dictionary and not (args as Dictionary).is_empty())
	):
		return s.format(args)
	return s


## A {key, args} line in words ("" for an empty line).
static func say(game: WorkoutGame, line: Dictionary) -> String:
	var key := str(line.get("key", ""))
	return tx(game, key, line.get("args", [])) if key != "" else ""


# --- the rider ----------------------------------------------------------------------


static func is_client(game: WorkoutGame) -> bool:
	return game != null and game.ctx != null and game.ctx.role == Wl.CLIENT


## The phase `r` is in: its own index, else the lead's, never below 0.
static func phase_index(state: WorkoutState, r: WorkoutRiderState) -> int:
	var i := r.phase_index if r != null and r.phase_index >= 0 else state.phase_index
	return maxi(i, 0)


## Session time in band, 0..1. tib_fraction() is 0 on clients: they read the snapshot's value.
static func tib(game: WorkoutGame, r: WorkoutRiderState) -> float:
	if is_client(game):
		return float(r.snap_tib_permille) / 1000.0
	return r.tib_fraction()


## Time in band of the current block, 0..1.
static func block_tib(game: WorkoutGame, r: WorkoutRiderState) -> float:
	if is_client(game):
		return float(r.snap_interval_permille) / 1000.0
	return r.interval_fraction(phase_index(game.state, r))


## The mean of every rider's session time in band (BRIEF 3.7's group score), 0..1.
static func group_tib(game: WorkoutGame) -> float:
	var state := game.state
	if state.order.is_empty():
		return 0.0
	var total := 0.0
	for peer: int in state.order:
		total += tib(game, state.rider(peer))
	return total / float(state.order.size())


# --- targets and instructions -------------------------------------------------------


## The ERG target in watts: the telemetry's applied target when there is one, else the plan's (on a
## ramp, where the ramp is now).
static func target_w(state: WorkoutState, index: int, r: WorkoutRiderState, t: Telemetry) -> float:
	if t != null and t.mode == Wl.ERG and t.applied_target_w > 0:
		return float(t.applied_target_w)
	var p := state.phase(index)
	if p == null or p.mode != Wl.ERG or r == null:
		return 0.0
	var pct := p.target_pct
	if p.has_ramp() and p.duration_s > 0.0:
		var f := clampf((state.plan_t - state.phase_start_s(index)) / p.duration_s, 0.0, 1.0)
		pct = lerpf(p.target_pct, p.ramp_to_pct, f)
	return pct / 100.0 * r.ftp


## The trainer's mode as far as the HUD knows it: the telemetry's, else the plan's.
static func mode_of(state: WorkoutState, index: int, t: Telemetry) -> String:
	if t != null and (t.mode == Wl.ERG or t.mode == Wl.SIM):
		return t.mode
	var p := state.phase(index)
	return p.mode if p != null else Wl.OFF


## The band the watts are judged against: ERG the target +- WorkoutRules.ERG_TOLERANCE, SIM the band
## Workout published (ZERO for none).
static func power_band(
	state: WorkoutState, index: int, r: WorkoutRiderState, t: Telemetry, published: Vector2
) -> Vector2:
	if mode_of(state, index, t) == Wl.SIM:
		return published
	var w := target_w(state, index, r, t)
	if w <= 0.0:
		return Vector2.ZERO
	return Vector2(w * (1.0 - WorkoutRules.ERG_TOLERANCE), w * (1.0 + WorkoutRules.ERG_TOLERANCE))


## The target line under the phase's name, {key, args}. A warm-up sprint is FREE RIDE, never SPRINT:
## nothing asks for a hard effort in the warm-up (BRIEF 4.6.8; WorkoutHud.band_for has no band there).
static func target_text(
	state: WorkoutState, index: int, r: WorkoutRiderState, t: Telemetry
) -> Dictionary:
	var p := state.phase(index)
	if p == null or r == null:
		return {}
	if p.kind == Wl.COOLDOWN:
		return _line("WORKOUT_HUD_TARGET_EASY")
	if p.mode == Wl.ERG:
		if p.has_ramp():
			return _line("WORKOUT_HUD_TARGET_RAMP", [roundi(p.target_pct), roundi(p.ramp_to_pct)])
		return _line(
			"WORKOUT_HUD_TARGET_ERG", [roundi(p.target_pct), roundi(target_w(state, index, r, t))]
		)
	return _band_line(state, index, r)


## The one instruction line on the mine plate, {key, args, urgent}. First match: rescue or the
## low-cadence warning, then by phase.
static func instruction(
	state: WorkoutState, index: int, r: WorkoutRiderState, t: Telemetry, low_cadence: bool
) -> Dictionary:
	if low_cadence or (t != null and t.rescue):
		var rpm := roundi(HudRiderNumbers.RESCUE_RECOVER_RPM)
		return _line("WORKOUT_HUD_DO_SPIN", [rpm], true)
	var p := state.phase(index)
	if p == null or r == null:
		return {}
	if p.kind == Wl.COOLDOWN:
		return _line("WORKOUT_HUD_DO_EASY")
	if p.mode == Wl.ERG:
		return _line("WORKOUT_HUD_DO_HOLD", [roundi(target_w(state, index, r, t))])
	return _band_line(state, index, r)


## SIM phases: SPRINT 240+ W, HOLD 152-210 W or FREE RIDE, from WorkoutHud.band_for.
static func _band_line(state: WorkoutState, index: int, r: WorkoutRiderState) -> Dictionary:
	var band := WorkoutHud.band_for(state, index, r)
	if band.is_empty():
		return _line("WORKOUT_HUD_FREE_RIDE")
	if state.phase(index).kind == Wl.FREE:
		return _line("WORKOUT_HUD_SPRINT", [roundi(float(band[0]))])
	return _line("WORKOUT_HUD_HOLD_BAND", [roundi(float(band[0])), roundi(float(band[1]))])


static func _line(key: String, args: Array = [], urgent: bool = false) -> Dictionary:
	return {"key": key, "args": args, "urgent": urgent}


## The NEXT line's text: the phase's banner text. The cool-down has no banner (the platform has its
## own), so it has its own key; a warm-up sprint reads as what it is there, a free ride.
static func next_text(game: WorkoutGame, index: int) -> String:
	var state := game.state
	var p := state.phase(index)
	if p == null:
		return tx(game, "WORKOUT_HUD_NEXT_END")
	var strings := game.ctx.strings if game.ctx != null else null
	if strings == null:
		strings = GameStrings.new()
	if p.kind == Wl.COOLDOWN:
		var args := {
			"label": strings.t(p.label),
			"pct": roundi(p.target_pct),
			"time": WorkoutSession.clock(p.duration_s),
		}
		return tx(game, "WORKOUT_HUD_NEXT_COOLDOWN", args)
	var b := WorkoutHud.interval_banner(state, index, strings)
	if b.is_empty():
		return ""
	var key := str(b["key"])
	if key == "WORKOUT_BANNER_SPRINT" and state.phase_start_s(index) < WorkoutHud.WARMUP_S:
		key = "WORKOUT_BANNER_FREE"
	return tx(game, key, b["args"])


# --- timeline -----------------------------------------------------------------------


## The phase index of each of `n` columns across the whole session, by time.
static func timeline_columns(phases: Array[PlanPhase], n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if phases.is_empty() or n <= 0:
		return out
	var total := 0.0
	for p in phases:
		total += p.duration_s
	out.resize(n)
	var i := 0
	var end := phases[0].duration_s
	for c in n:
		var t := (float(c) + 0.5) / float(n) * total
		while t >= end and i + 1 < phases.size():
			i += 1
			end += phases[i].duration_s
		out[c] = i
	return out


## The block height of `p` in `f` of the way through it, whole art px of the strip.
static func block_h(state: WorkoutState, p: PlanPhase, f: float) -> int:
	var pct: float
	if p.mode == Wl.ERG:
		pct = lerpf(p.target_pct, p.ramp_to_pct, f) if p.has_ramp() else p.target_pct
	elif p.kind == Wl.FREE:
		pct = (
			WorkoutRideView.SPRINT_STRIP_PCT
			if WorkoutSession.is_sprint(p)
			else WorkoutRideView.FREE_STRIP_PCT
		)
	else:
		pct = float(state.band_pct[1])
	var h := roundi(WorkoutRideView._strip_h(pct) * TIMELINE_H_SCALE)
	return clampi(h, TIMELINE_MIN_H, TIMELINE_H)


## The strip as merged runs, one rect each (Controls redraw every frame): [{x, w, phase, h, hatched}].
## A ramp comes out as a stair of runs.
static func timeline_runs(state: WorkoutState, n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cols := timeline_columns(state.phases, n)
	var i := 0
	while i < cols.size():
		var phase_i := cols[i]
		var p := state.phases[phase_i]
		var phase_end := i
		while phase_end < cols.size() and cols[phase_end] == phase_i:
			phase_end += 1
		var width := phase_end - i
		var x := i
		while x < phase_end:
			var h := block_h(state, p, (float(x - i) + 0.5) / float(width))
			var run_end := x + 1
			while (
				run_end < phase_end
				and block_h(state, p, (float(run_end - i) + 0.5) / float(width)) == h
			):
				run_end += 1
			(
				out
				. append(
					{
						"x": x,
						"w": run_end - x,
						"phase": phase_i,
						"h": h,
						"hatched": p.mode == Wl.SIM or p.kind == Wl.FREE,
					}
				)
			)
			x = run_end
		i = phase_end
	return out


## The timeline plate's words and marks.
static func timeline(game: WorkoutGame, t: Telemetry) -> Dictionary:
	var state := game.state
	var r := state.rider(game.view_peer())
	var i := phase_index(state, r)
	var p := state.phase(i)
	var total := state.total_s()
	var now := clampf(state.plan_t / total, 0.0, 1.0) if total > 0.0 else 0.0
	var phase_end := state.phase_start_s(i + 1)
	return {
		"index": i,
		"label": tx(game, p.label).to_upper() if p != null else "",
		"target": say(game, target_text(state, i, r, t)),
		"phase_left_s": maxf(phase_end - state.plan_t, 0.0),
		"next": next_text(game, i + 1),
		"session_left_s": maxf(total - state.plan_t, 0.0),
		"now_x": roundi(now * float(TIMELINE_COLUMNS)),
	}


# --- mine ---------------------------------------------------------------------------


## The mine plate. `nums` has been fed this rider's telemetry and told its band (see band_for_nums).
static func mine(
	game: WorkoutGame,
	nums: HudRiderNumbers,
	t: Telemetry,
	cadence_band: Vector2,
	weight_kg: float,
) -> Dictionary:
	var state := game.state
	var r := state.rider(game.view_peer())
	if r == null:
		return {}
	var i := phase_index(state, r)
	var p := state.phase(i)
	var no_data := t == null or nums.is_stale()
	var mean := nums.mean_power_w()
	var band := nums.band()
	var hi := band.y if band.y > 0.0 else 0.0
	var top := maxf(hi * 1.5, maxf(mean * 1.05, 100.0))
	var cad_no_data := t == null
	var cb := cadence_band
	if cb.y <= 0.0 and p != null and p.kind == Wl.FREE:
		cb = FREE_CADENCE_BAND
	var line := instruction(state, i, r, t, nums.low_cadence())
	var wprime := HudRiderNumbers.wprime_j()
	var wb := clampf(t.wbal_j / wprime, 0.0, 1.0) if t != null and wprime > 0.0 else -1.0
	var hs := nums.heart_state()
	var wkg := ""
	if weight_kg > 0.0 and not no_data:
		wkg = tx(game, "WORKOUT_HUD_WKG", ["%.1f" % (mean / weight_kg)])
	var sim_on := t != null and t.mode == Wl.SIM
	return {
		"mode": mode_of(state, i, t),
		"hr_state": hs,
		"hr": "--" if hs == HudRiderNumbers.HR_DROPOUT else str(nums.heart_bpm()),
		"in_band": nums.in_band(),
		"watts": "--" if no_data else str(roundi(mean)),
		"band_state": HudRiderNumbers.IN_BAND if no_data else nums.band_state(),
		"pct": "--" if no_data else "%d%%" % roundi(mean / maxf(r.ftp, 1.0) * 100.0),
		"wkg": wkg,
		"band": band,
		"gauge_lo": band.x / top,
		"gauge_hi": hi / top,
		"gauge_v": -1.0 if no_data else mean / top,
		"cadence": "--" if cad_no_data else str(roundi(t.cadence_rpm)),
		"cadence_dim": cad_no_data or nums.cadence_stale(),
		"cadence_lo": _cad_f(cb.x) if cb.y > 0.0 else 0.0,
		"cadence_hi": _cad_f(cb.y) if cb.y > 0.0 else 0.0,
		"cadence_v": -1.0 if cad_no_data else _cad_f(t.cadence_rpm),
		"cadence_in":
		not cad_no_data and (cb.y <= 0.0 or (t.cadence_rpm >= cb.x and t.cadence_rpm <= cb.y)),
		"crank_frame": WorkoutRig.crank_frame(game.cranks.revs(r.peer_id)),
		"line": say(game, line),
		"urgent": bool(line.get("urgent", false)),
		"wbal": wb,
		"wbal_low": wb >= 0.0 and wb < WBAL_LOW,
		"wbal_pct": "--" if wb < 0.0 else "%d%%" % roundi(wb * 100.0),
		"gear_lit": sim_on,
		"gear": str(t.gear) if sim_on else "-",
		"gear_f": clampf(float(t.gear) / float(GEAR_MAX), 0.0, 1.0) if sim_on else 0.0,
	}


static func _cad_f(rpm: float) -> float:
	return clampf(inverse_lerp(CAD_LO, CAD_HI, rpm), 0.0, 1.0)


# --- crew ---------------------------------------------------------------------------


## Card `i`'s rect in the crew plate: 4 columns, 2 rows, filling from the bottom row, so 1-4 riders is
## one row and 8 fit.
static func card_rect(i: int) -> Rect2i:
	var col := i % CARD_COLUMNS
	var row := i / CARD_COLUMNS
	return Rect2i(
		CREW_X0 + col * (CARD.x + CARD_GAP), (1 - row) * (CARD.y + CARD_GAP), CARD.x, CARD.y
	)


## One card per rider in slot order. ctx.roster first (2 Hz, every peer), else the state.
static func crew(game: WorkoutGame) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var state := game.state
	var roster: Dictionary = game.ctx.roster if game.ctx != null else {}
	var local := game.view_peer()
	for peer: int in state.order:
		var r := state.rider(peer)
		var row: Dictionary = roster.get(peer, {})
		var connected := bool(row.get("connected", r.connected))
		var rescue := bool(row.get("rescue", r.rescue))
		var afk := bool(row.get("afk", r.afk))
		var w := float(row.get("raw_w", r.power_w))
		var pct := float(row.get("ftp_pct", w / maxf(r.ftp, 1.0) * 100.0))
		var status: Dictionary = row.get("status", {})
		var flag := ""
		if not connected:
			flag = FLAG_LINK
		elif rescue:
			flag = FLAG_RESCUE
		elif afk:
			flag = FLAG_AFK
		var slot := game.ctx.player(peer) if game.ctx != null else null
		(
			out
			. append(
				{
					"peer": peer,
					"slot": r.slot_index,
					"name": slot.name if slot != null and slot.name != "" else r.name,
					"local": peer == local,
					"line":
					(
						tx(game, "WORKOUT_HUD_NO_POWER")
						if not connected
						else tx(game, "WORKOUT_HUD_CARD", [roundi(w), roundi(pct)])
					),
					"in_band": bool(status.get("in_band", r.in_band)) and connected,
					"tib": WorkoutHud.pct_text(tib(game, r)),
					"flag": tx(game, flag) if flag != "" else "",
					"flag_over": flag == FLAG_RESCUE,
				}
			)
		)
	return out


# --- score --------------------------------------------------------------------------


## The score plate. `peak_w` is the local rider's peak this phase (the Control tracks it from the
## telemetry). A warm-up sprint shows no peak: nothing there asks for one.
static func score(game: WorkoutGame, t: Telemetry, peak_w: float) -> Dictionary:
	var state := game.state
	var r := state.rider(game.view_peer())
	if r == null:
		return {}
	var i := phase_index(state, r)
	var p := state.phase(i)
	var f := tib(game, r)
	var sprint := WorkoutSession.is_sprint(p) and not WorkoutHud.band_for(state, i, r).is_empty()
	var graded := state.is_course_phase(i) and t != null
	return {
		"tib": str(roundi(clampf(f, 0.0, 1.0) * 100.0)),
		"grade": GameResults.grade_from_fraction(f),
		"block": tx(game, "WORKOUT_HUD_BLOCK", [WorkoutHud.pct_text(block_tib(game, r))]),
		"group":
		(
			tx(game, "WORKOUT_HUD_GROUP", [WorkoutHud.pct_text(group_tib(game))])
			if state.order.size() >= 2
			else ""
		),
		"speed": tx(game, "WORKOUT_HUD_KMH", ["%.1f" % (r.speed_mps() * 3.6)]),
		"km": tx(game, "WORKOUT_HUD_KM", ["%.1f" % (r.distance_m() / 1000.0)]),
		"grade_pct": "%+.1f%%" % t.applied_grade_pct if graded else "",
		"peak": tx(game, "WORKOUT_HUD_PEAK", [roundi(peak_w)]) if sprint else "",
	}

class_name SiegePlanBuilder
extends RefCounted
## Every slot's EffortPlan from content/siege/shifts.json and its wave offset (brief 2.3).
## G0 architect's file (B1 owns the rest of rules/; changes go through the lead).
##
## - Every slot, bots included, gets the same phases and lengths; only WORK targets differ.
## - Phases are ERG, lap: true, with no range_pct (Siege never moves an ERG target); the
##   PlanValidator appends the cool-down (180 s at 50%), never this builder.
## - A wave's WORK target is the shift's target plus the rider's wave_offset (player option,
##   clamped to -10..+5; bots 0), clamped to <= 105% in waves longer than 240 s and <= 117% in
##   waves of 240 s or less (and never below 50%). Waves of WARMUP kind (the drill's) and every
##   break take no offset.
## - PlanPhase.meta carries the Siege role the rules read (never inferred from `kind`):
##   {"role": SiegeIds.ROLE_*, "number": wave or break number (the warm-up wave 0),
##    "waves": waves in the shift, "last_wave": bool, "mix": SiegeIds.MIX_* (waves),
##    "rushes_at_s": [wave seconds] (waves with rushes), "shift": content id}.
## - Labels are strings keys: SIEGE_PHASE_WARMUP_WAVE, SIEGE_PHASE_BUILD_BREAK,
##   SIEGE_PHASE_WAVE_<n>, SIEGE_PHASE_BREAK_<n> (n 1..10).

const OFFSET_MIN := -10
const OFFSET_MAX := 5
## Waves longer than this may not go above LONG_WAVE_MAX_PCT (brief 2.3, P1 custom shifts too).
const SHORT_WAVE_S := 240.0
const LONG_WAVE_MAX_PCT := 105.0
const SHORT_WAVE_MAX_PCT := 117.0
const MIN_PCT := 50.0
const MAX_LABEL_N := 10


## The slot's wave offset in points: PlayerSlot.options["wave_offset"] clamped to -10..+5; 0 for
## bots and when missing or not a number.
static func offset_of(slot: PlayerSlot) -> int:
	if slot == null or slot.is_bot:
		return 0
	var v: Variant = slot.options.get("wave_offset", 0)
	if not (v is int or v is float) or not is_finite(float(v)):
		return 0
	return clampi(int(v), OFFSET_MIN, OFFSET_MAX)


## A WORK wave's target in % FTP: base + offset, clamped to <= 105 in waves > 240 s and <= 117
## in waves <= 240 s, and >= 50. (300 s at 105 +5 -> 105; 240 s at 115 +5 -> 117.)
static func wave_target(base_pct: float, duration_s: float, offset: int) -> float:
	var cap := LONG_WAVE_MAX_PCT if duration_s > SHORT_WAVE_S else SHORT_WAVE_MAX_PCT
	return clampf(base_pct + float(offset), MIN_PCT, cap)


## The meta of every phase of `shift`, in order (the same for every slot).
static func phase_metas(shift: Dictionary, shift_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var phases: Array = shift.get("phases", [])
	var waves := wave_count(shift)
	var wave_n := 0
	for d: Variant in phases:
		var role := str(d.get("role", ""))
		var meta := {
			"role": role, "number": 0, "waves": waves, "shift": shift_id, "last_wave": false
		}
		match role:
			SiegeIds.ROLE_WAVE:
				wave_n += 1
				meta["number"] = wave_n
				meta["last_wave"] = wave_n == waves
				meta["mix"] = str(d.get("mix", SiegeIds.MIX_STANDARD))
				if d.has("rushes_at_s"):
					meta["rushes_at_s"] = (d["rushes_at_s"] as Array).map(
						func(r: Variant) -> float: return float(r)
					)
			SiegeIds.ROLE_WARMUP_WAVE:
				meta["mix"] = SiegeIds.MIX_STANDARD
			SiegeIds.ROLE_BREAK:
				meta["number"] = wave_n
		out.append(meta)
	return out


## One slot's plan (no cool-down; the PlanValidator appends it).
static func build(shift: Dictionary, slot: PlayerSlot, shift_id: String = "") -> EffortPlan:
	var plan := EffortPlan.new()
	var offset := offset_of(slot)
	var metas := phase_metas(shift, shift_id)
	var phases: Array = shift.get("phases", [])
	for i in phases.size():
		var d: Dictionary = phases[i]
		var meta := metas[i]
		var kind := str(d["kind"])
		var dur := float(d["duration_s"])
		var target := float(d["target_pct"])
		if str(meta["role"]) == SiegeIds.ROLE_WAVE and kind == Wl.WORK:
			target = wave_target(target, dur, offset)
		var ph := PlanPhase.erg(
			kind, target, dur, label_for(str(meta["role"]), int(meta["number"]))
		)
		if d.has("ramp_to_pct"):
			ph.with_ramp(float(d["ramp_to_pct"]))
		plan.add(ph.with_lap().with_meta(meta))
	return plan


## {peer_id: EffortPlan} for every slot.
static func build_all(
	shift: Dictionary, players: Array[PlayerSlot], shift_id: String = ""
) -> Dictionary:
	var plans := {}
	for p in players:
		plans[p.peer_id] = build(shift, p, shift_id)
	return plans


## The meta of phase `index` of `plan`: {"role": "cooldown"} past the plan's end (the appended
## cool-down), {"role": ""} before the start or without a plan.
static func role_of(plan: EffortPlan, index: int) -> Dictionary:
	if plan == null or index < 0:
		return {"role": SiegeIds.ROLE_NONE}
	if index >= plan.size() or plan.phase(index).kind == Wl.COOLDOWN:
		return {"role": SiegeIds.ROLE_COOLDOWN}
	return plan.phase(index).meta


## The phase's mean planned ERG target in % FTP (a ramp's mean; the budget B's planned P_eff).
static func mean_pct(ph: PlanPhase) -> float:
	if ph == null or ph.mode != Wl.ERG:
		return 0.0
	return (ph.target_pct + ph.ramp_to_pct) / 2.0 if ph.has_ramp() else ph.target_pct


static func wave_count(shift: Dictionary) -> int:
	var n := 0
	for d: Variant in shift.get("phases", []):
		if d is Dictionary and str(d.get("role", "")) == SiegeIds.ROLE_WAVE:
			n += 1
	return n


## Seconds of the shift without the cool-down.
static func total_s(shift: Dictionary) -> float:
	var s := 0.0
	for d: Variant in shift.get("phases", []):
		s += float(d.get("duration_s", 0.0))
	return s


## The label key of a phase role (number: the wave or break number).
static func label_for(role: String, number: int) -> String:
	match role:
		SiegeIds.ROLE_WARMUP_WAVE:
			return "SIEGE_PHASE_WARMUP_WAVE"
		SiegeIds.ROLE_BUILD_BREAK:
			return "SIEGE_PHASE_BUILD_BREAK"
		SiegeIds.ROLE_WAVE:
			return "SIEGE_PHASE_WAVE_%d" % clampi(number, 1, MAX_LABEL_N)
		SiegeIds.ROLE_BREAK:
			return "SIEGE_PHASE_BREAK_%d" % clampi(number, 1, MAX_LABEL_N)
	return "SIEGE_PHASE_WAVE_1"

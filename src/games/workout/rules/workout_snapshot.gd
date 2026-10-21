class_name WorkoutSnapshot
extends RefCounted
## Workout's compact snapshot (BRIEF 3.6, 5.5): every number is an int, so the paths in
## INT_FIELDS make Protocol.decode() return exact ints.
## [codeblock]
## {"t": tick, "p": lead phase index, "pt": plan time in 0.1 s,
##  "r": [[peer, distance_dm, course_dm, speed_cm_s, flags, tib_permille, power_w,
##         cadence_rpm, interval_tib_permille], ...],          # slot order
##  "tl": [[kind, mode, target_x10, ramp_x10 or -1, duration_ds, grade_source], ...],
##  "tll": [label, ...]}                                       # timeline, every 20th snapshot
## [/codeblock]
## A timeline of more than TIMELINE_PART_PHASES phases (a long imported .zwo) would push the
## snapshot past the relay's 16 KB limit (W3 NET-3), so it travels in parts on consecutive
## snapshots: "tl"/"tll" hold a slice, "tlo" its first phase index and "tln" the whole count;
## a client sets its timeline once it holds every part.
## flags: 1 in band, 2 rescue, 4 AFK, 8 disconnected. Kind indexes Wl.PHASE_KINDS, mode is
## 0 ERG / 1 SIM, grade_source 0 flat / 1 course / 2 game.

const F_IN_BAND := 1
const F_RESCUE := 2
const F_AFK := 4
const F_DISCONNECTED := 8
const MODES: Array[String] = [Wl.ERG, Wl.SIM]
const SOURCES: Array[String] = [Wl.GRADE_FLAT, Wl.GRADE_COURSE, Wl.GRADE_GAME]
## Protocol int_fields for the snapshot.
const INT_FIELDS: Array[String] = ["t", "p", "pt", "r[][]", "tl[][]", "tlo", "tln"]
## Phases per timeline part (about 6 KB with labels).
const TIMELINE_PART_PHASES := 120


## How many snapshots the timeline takes (1 unless it is longer than TIMELINE_PART_PHASES).
static func timeline_parts(phases: Array[PlanPhase]) -> int:
	return maxi(1, ceili(float(phases.size()) / float(TIMELINE_PART_PHASES)))


## `timeline_part`: -1 for none, else the part to carry (0 for a timeline in one part).
static func encode(state: WorkoutState, with_timeline: bool, timeline_part: int = 0) -> Dictionary:
	var rows: Array = []
	for peer: int in state.order:
		var r := state.rider(peer)
		var flags := 0
		if r.in_band:
			flags |= F_IN_BAND
		if r.rescue:
			flags |= F_RESCUE
		if r.afk:
			flags |= F_AFK
		if not r.connected:
			flags |= F_DISCONNECTED
		rows.append([
			peer,
			int(round(r.speed.distance_m * 10.0)),
			int(round(r.course_d * 10.0)),
			int(round(r.speed.v_mps * 100.0)),
			flags,
			int(round(r.tib_fraction() * 1000.0)),
			int(round(r.power_w)),
			int(round(r.cadence_rpm)),
			int(round(r.interval_fraction(r.phase_index) * 1000.0)),
		])
	var snap := {"t": state.tick, "p": state.phase_index, "pt": int(round(state.plan_t * 10.0)), "r": rows}
	if with_timeline and timeline_part >= 0:
		var parts := timeline_parts(state.phases)
		if parts == 1:
			var tl := encode_timeline(state.phases)
			snap["tl"] = tl["tl"]
			snap["tll"] = tl["tll"]
		elif timeline_part < parts:
			var lo := timeline_part * TIMELINE_PART_PHASES
			var slice: Array[PlanPhase] = state.phases.slice(lo, lo + TIMELINE_PART_PHASES)
			var tl := encode_timeline(slice)
			snap["tl"] = tl["tl"]
			snap["tll"] = tl["tll"]
			snap["tlo"] = lo
			snap["tln"] = state.phases.size()
	return snap


static func encode_timeline(phases: Array[PlanPhase]) -> Dictionary:
	var tl: Array = []
	var labels: Array = []
	for p in phases:
		tl.append([
			maxi(Wl.PHASE_KINDS.find(p.kind), 0),
			maxi(MODES.find(p.mode), 0),
			int(round(p.target_pct * 10.0)),
			int(round(p.ramp_to_pct * 10.0)) if p.has_ramp() else -1,
			int(round(p.duration_s * 10.0)),
			maxi(SOURCES.find(p.grade_source), 0),
		])
		labels.append(p.label)
	return {"tl": tl, "tll": labels}


## Rebuilds the timeline (course profiles are not sent; clients use their own course).
static func decode_timeline(tl: Array, labels: Array, course: WorkoutCourse) -> Array[PlanPhase]:
	var out: Array[PlanPhase] = []
	for i in tl.size():
		var e: Array = tl[i]
		if e.size() < 6:
			continue
		var kind: String = Wl.PHASE_KINDS[clampi(int(e[0]), 0, Wl.PHASE_KINDS.size() - 1)]
		var mode: String = MODES[clampi(int(e[1]), 0, MODES.size() - 1)]
		var label := str(labels[i]) if i < labels.size() else ""
		var p: PlanPhase
		if mode == Wl.ERG:
			p = PlanPhase.erg(kind, float(e[2]) / 10.0, float(e[4]) / 10.0, label)
			if int(e[3]) >= 0:
				p.with_ramp(float(e[3]) / 10.0)
		else:
			p = PlanPhase.sim(kind, SOURCES[clampi(int(e[5]), 0, SOURCES.size() - 1)], float(e[4]) / 10.0, label)
			if p.grade_source == Wl.GRADE_COURSE and course != null:
				p.course_profile = course.to_course_profile()
		p.with_lap(true)
		out.append(p)
	return out


## One part of a long timeline: kept in state.timeline_parts until every phase is in, then the
## whole timeline is set. A part of another length starts over.
static func _apply_timeline_part(state: WorkoutState, tl: Array, labels: Array, offset: int, total: int) -> void:
	if total <= 0 or offset < 0 or offset >= total:
		return
	if int(state.timeline_parts.get("n", -1)) != total:
		state.timeline_parts = {"n": total, "parts": {}}
	(state.timeline_parts["parts"] as Dictionary)[offset] = [tl, labels]
	var all_tl: Array = []
	var all_labels: Array = []
	while all_tl.size() < total:
		var part: Variant = (state.timeline_parts["parts"] as Dictionary).get(all_tl.size())
		if part == null or ((part as Array)[0] as Array).is_empty():
			return
		all_tl.append_array((part as Array)[0])
		all_labels.append_array((part as Array)[1])
	state.set_timeline(decode_timeline(all_tl.slice(0, total), all_labels.slice(0, total), state.course))
	state.timeline_parts = {}


## Applies a snapshot to a client's state. Riders not in the state are ignored.
static func apply(state: WorkoutState, snap: Dictionary) -> void:
	state.tick = int(snap.get("t", state.tick))
	state.phase_index = int(snap.get("p", state.phase_index))
	state.plan_t = float(snap.get("pt", 0)) / 10.0
	if snap.has("tl") and snap["tl"] is Array:
		var labels: Array = snap.get("tll", []) if snap.get("tll", []) is Array else []
		if snap.has("tln"):
			_apply_timeline_part(state, snap["tl"], labels, int(snap.get("tlo", 0)), int(snap["tln"]))
		else:
			state.set_timeline(decode_timeline(snap["tl"], labels, state.course))
	var rows: Variant = snap.get("r", [])
	if not (rows is Array):
		return
	for row: Variant in rows:
		if not (row is Array) or (row as Array).size() < 9:
			continue
		var r := state.rider(int(row[0]))
		if r == null:
			continue
		r.speed.distance_m = float(row[1]) / 10.0
		r.course_d = float(row[2]) / 10.0
		r.speed.v_mps = float(row[3]) / 100.0
		var flags := int(row[4])
		r.in_band = (flags & F_IN_BAND) != 0
		r.rescue = (flags & F_RESCUE) != 0
		r.afk = (flags & F_AFK) != 0
		r.connected = (flags & F_DISCONNECTED) == 0
		r.snap_tib_permille = int(row[5])
		r.power_w = float(row[6])
		r.cadence_rpm = float(row[7])
		r.snap_interval_permille = int(row[8])
		r.phase_index = state.phase_index

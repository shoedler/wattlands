class_name WorkoutResults
extends RefCounted
## Builds Workout's GameResults (BRIEF 3.7): per rider and interval time in band, kJ,
## average and normalized power, best 1-, 5- and 20-minute power and sprint peaks; the group
## grade from the average session time in band (S >= 95%, A >= 90%, B >= 80%, C >= 65%,
## else D); XP per rider. FIT laps per interval come from the plan (lap = true phases), so
## nothing here emits lap_marker.
##
## Rows start from GameResults.from_stats(ctx.stats, players). Ride statistics the platform
## reports as 0 (or doesn't report) are filled from Workout's own WorkoutPowerStats.
## Extra row keys: "intervals" [{i, label, kind, tib_s, ride_s, tib_pct}] and "sprints"
## [{i, label, peak_w, best_s, held_s, hit}]; display stats go in "stats" (strings keys), which
## the results screen draws: grade, time in band, intervals in band, best 1-, 5- and 20-minute power
## (each only once the ride is that long), every sprint's peak and the best one, sprints hit.

const POWER_KEYS: Array[String] = [
	"kj", "avg_power_w", "avg_ftp_pct", "np_w", "best_1m_w", "best_5m_w", "best_20m_w", "ride_s"
]
const XP_PER_SPRINT := 10
const STAT_GRADE := "WORKOUT_STAT_GRADE"
const STAT_TIB := "WORKOUT_STAT_TIB_PCT"
const STAT_INTERVALS := "WORKOUT_STAT_INTERVALS"
const STAT_SPRINT_PEAK := "WORKOUT_STAT_SPRINT_PEAK_W"
const STAT_SPRINTS_HIT := "WORKOUT_STAT_SPRINTS_HIT"
const STAT_SPRINT_PEAKS := "WORKOUT_STAT_SPRINT_PEAKS_W"
## Row key -> stats key for the best-power display stats (BRIEF 3.7 results).
const BEST_STATS: Dictionary = {
	"best_1m_w": "WORKOUT_STAT_BEST_1M_W",
	"best_5m_w": "WORKOUT_STAT_BEST_5M_W",
	"best_20m_w": "WORKOUT_STAT_BEST_20M_W"
}
const TEAM_TIB := "WORKOUT_STAT_GROUP_TIB_PCT"
const TEAM_RIDERS := "WORKOUT_STAT_RIDERS"
const TEAM_SPRINTS := "WORKOUT_STAT_GROUP_SPRINTS_HIT"


static func build(
	state: WorkoutState, stats: SessionStats, players: Array[PlayerSlot]
) -> GameResults:
	var res := GameResults.from_stats(stats, players)
	var fractions: Array[float] = []
	var team_hits := 0
	for row in res.rows:
		var r := state.rider(int(row["peer_id"]))
		if r == null:
			continue
		var mine := r.stats.row_values(r.ftp)
		for key in POWER_KEYS:
			if float(row.get(key, 0.0)) <= 0.0:
				row[key] = mine[key]
		var frac := r.tib_fraction()
		fractions.append(frac)
		row["time_in_band_s"] = snappedf(r.tib_s, 0.05)
		row["time_in_band_pct"] = snappedf(frac * 100.0, 0.1)
		var intervals: Array = []
		var interval_text: Array[String] = []
		for i in state.phases.size():
			var p := state.phases[i]
			if p.kind == Wl.COOLDOWN or not r.intervals.has(i):
				continue
			var iv: Array = r.intervals[i]
			var pct := snappedf(r.interval_fraction(i) * 100.0, 0.1)
			(
				intervals
				. append(
					{
						"i": i,
						"label": p.label,
						"kind": p.kind,
						"tib_s": snappedf(float(iv[0]), 0.05),
						"ride_s": snappedf(float(iv[1]), 0.05),
						"tib_pct": pct,
					}
				)
			)
			interval_text.append(str(int(round(pct))))
		var sprints: Array = []
		var peaks: Array[String] = []
		var best_peak := 0
		var hits := 0
		for s in r.sprints:
			var p := state.phase(int(s["i"]))
			var entry: Dictionary = s.duplicate()
			entry["label"] = p.label if p != null else ""
			sprints.append(entry)
			peaks.append(str(int(s["peak_w"])))
			best_peak = maxi(best_peak, int(s["peak_w"]))
			if bool(s["hit"]):
				hits += 1
		team_hits += hits
		row["intervals"] = intervals
		row["sprints"] = sprints
		var st: Dictionary = row.get("stats", {})
		st[STAT_GRADE] = GameResults.grade_from_fraction(frac)
		st[STAT_TIB] = snappedf(frac * 100.0, 0.1)
		st[STAT_INTERVALS] = " / ".join(interval_text)
		for key: String in BEST_STATS:
			# A ride shorter than the window has no best power for it (0): no stat then.
			if float(row.get(key, 0.0)) > 0.0:
				st[BEST_STATS[key]] = roundi(float(row[key]))
		if not r.sprints.is_empty():
			st[STAT_SPRINT_PEAK] = best_peak
			st[STAT_SPRINT_PEAKS] = " / ".join(peaks)
			st[STAT_SPRINTS_HIT] = "%d/%d" % [hits, r.sprints.size()]
		row["stats"] = st
		row["xp"] = xp_for(float(row["kj"]), frac, hits)
	var group := 0.0
	for f in fractions:
		group += f
	group = group / float(fractions.size()) if not fractions.is_empty() else 0.0
	res.grade = GameResults.grade_from_fraction(group)
	res.score = snappedf(group * 100.0, 0.1)
	res.summary_key = "WORKOUT_RESULT_" + res.grade
	res.team = {TEAM_TIB: res.score, TEAM_RIDERS: fractions.size(), TEAM_SPRINTS: team_hits}
	return res


## XP: one per kJ, plus the session time in band in percent, plus 10 per sprint hit.
static func xp_for(kj: float, tib_fraction: float, sprints_hit: int) -> int:
	return int(round(kj)) + int(round(tib_fraction * 100.0)) + XP_PER_SPRINT * sprints_hit

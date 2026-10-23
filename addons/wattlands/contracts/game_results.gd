class_name GameResults
extends RefCounted
## What `GameModule.results()` returns (BRIEF 3.6): a grade, per-player rows, XP and
## cosmetic unlocks. Contract, frozen after W0.
##
## Start from the platform's rows with `GameResults.from_stats(ctx.stats, ctx.players)`:
## they already hold kJ, average power and %FTP, normalized power, best 1/5/20-minute
## power and a generic time in band. Then set the grade, override time in band if the
## game defines its own, and add custom stats under each row's "stats".
## `results()` runs on the host (or in solo play); the platform sends the GameResults to
## every client, then calls `apply_progress(results, ctx.progress)` on every peer.
##
## Row keys (all JSON-safe):
##   peer_id, slot_index, name, is_bot,
##   kj, avg_power_w, avg_ftp_pct, np_w, best_1m_w, best_5m_w, best_20m_w, ride_s,
##   time_in_band_s, time_in_band_pct, xp (int), unlocks (Array of ids),
##   stats (Dictionary of custom stats: key -> number or String)

## "S", "A", "B", "C" or "D".
var grade: String = "D"
var score: float = 0.0
## Game-defined title or summary string key for the results screen.
var summary_key: String = ""
## The short tag in the Strava title "WATTLANDS: <game> - <ride_tag>" (for example
## "Free Roam 30 min" or a plan name). "" falls back to the content title.
var ride_tag: String = ""
## Game stat lines for the Strava description, above the platform's averages (no heart rate).
var ride_lines: Array[String] = []
var rows: Array[Dictionary] = []
## Team-wide custom stats.
var team: Dictionary = {}
## Unique per session (set by the GameHost) so a peer that receives results twice applies
## progress once.
var session_id: String = ""


static func from_stats(stats: SessionStats, players: Array[PlayerSlot]) -> GameResults:
	var r := GameResults.new()
	for slot in players:
		var row: Dictionary = stats.base_row(slot.peer_id) if stats != null else {}
		row["peer_id"] = slot.peer_id
		row["slot_index"] = slot.slot_index
		row["name"] = slot.name
		row["is_bot"] = slot.is_bot
		if not row.has("xp"):
			row["xp"] = 0
		if not row.has("unlocks"):
			row["unlocks"] = []
		if not row.has("stats"):
			row["stats"] = {}
		r.rows.append(row)
	return r


## The row for `peer`, or an empty Dictionary.
func row(peer: int) -> Dictionary:
	for rw in rows:
		if int(rw.get("peer_id", 0)) == peer:
			return rw
	return {}


## Grade from a fraction 0..1 with BRIEF 3.7's bands (S >= 0.95, A >= 0.90, B >= 0.80,
## C >= 0.65, else D). Games with other bands compute their own.
static func grade_from_fraction(f: float) -> String:
	if f >= 0.95:
		return "S"
	if f >= 0.90:
		return "A"
	if f >= 0.80:
		return "B"
	if f >= 0.65:
		return "C"
	return "D"


func to_dict() -> Dictionary:
	return {
		"grade": grade,
		"score": score,
		"summary_key": summary_key,
		"ride_tag": ride_tag,
		"ride_lines": ride_lines.duplicate(),
		"rows": rows.duplicate(true),
		"team": team.duplicate(true),
		"session_id": session_id,
	}


static func from_dict(d: Dictionary) -> GameResults:
	var r := GameResults.new()
	r.grade = str(d.get("grade", "D"))
	r.score = float(d.get("score", 0.0))
	r.summary_key = str(d.get("summary_key", ""))
	r.ride_tag = str(d.get("ride_tag", ""))
	for line: Variant in d.get("ride_lines", []):
		r.ride_lines.append(str(line))
	var arr: Variant = d.get("rows", [])
	if arr is Array:
		for rw: Variant in arr:
			if rw is Dictionary:
				var row: Dictionary = (rw as Dictionary).duplicate(true)
				row["peer_id"] = int(row.get("peer_id", 0))
				row["slot_index"] = int(row.get("slot_index", 0))
				row["xp"] = int(row.get("xp", 0))
				r.rows.append(row)
	r.session_id = str(d.get("session_id", ""))
	var tm: Variant = d.get("team", {})
	if tm is Dictionary:
		r.team = (tm as Dictionary).duplicate(true)
	return r

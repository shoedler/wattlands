class_name FishingResults
extends RefCounted
## Results and progression (brief 2.8). G0 stub with the frozen API; fish-module owns this file.
##   build(state, stats, players, content) -> GameResults   host/SOLO, once
##   apply_progress(results, progress, local_peer, content, trip_id) -> Array   every peer, once


static func build(
	st: FishingState, stats: SessionStats, players: Array[PlayerSlot], _content: FishingContent
) -> GameResults:
	var res := GameResults.from_stats(stats, players)
	res.team = {"points": st.team_points, "fish": st.team_fish}
	res.score = st.team_points
	res.grade = FishingConst.team_grade(
		st.team_points / maxf(st.expected_points, 1.0), st.fish_started > 0
	)
	res.summary_key = "FISHING_RESULTS"
	return res


static func apply_progress(
	res: GameResults,
	progress: ProgressStore,
	local_peer: int,
	_content: FishingContent,
	_trip_id: String
) -> Array:
	var row := res.row(local_peer)
	if (
		row.is_empty()
		or (res.session_id != "" and progress.get_value("last_session", "") == res.session_id)
	):
		return []
	progress.set_value("last_session", res.session_id)
	progress.add("xp", float(row.get("xp", 0)))
	return []

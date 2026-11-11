class_name FishingResults
extends RefCounted
## Results and progression (contract v2; GAME_SDK 15).
##   build(state, stats, players, content[, strings]) -> GameResults   host/SOLO, once
##   apply_progress(results, progress, local_peer, content, trip_id) -> Array   every peer, once
##   summary_from(progress, content) -> {xp, records, cosmetics}   every peer, at configure
##
## Grade: team points / expected points (FishingState.expected_points: every started fish Landed
## with no bonuses; scheduled workouts include each fish's Double Hookup multiplier), S >= 1.25,
## A >= 1.0, B >= 0.8, C >= 0.6, else D; no started fish: D.
## Rows: GameResults.from_stats (kJ, average %FTP and the rest are in the grid), time in band
## overridden as % of fight time, then the FISHING_STAT_* stats in reading order (Free Roam adds
## the rank by points). Each row also carries "catches" (this session's landed fish), "records"
## (new species records) and "ride_lines" (its Strava lines); apply_progress writes catches and
## records into the local rider's store (a client has no rider catch log).
## Strava: ride_tag = "Free Roam <n> min" or the workout's name; ride_lines = fish caught, the
## biggest fish with kg, points, rank (Free Roam with more than one rider) and the furthest
## distance out (km). res.ride_lines holds the host rider's lines (results stay identical on every
## peer); each row's "ride_lines" holds that rider's own.
## XP: 1 per kJ, 10 per fish, 25 per trophy, 50 per new species record. Every unlock_every_xp
## (500) XP of the rider's running total unlocks the next cosmetics.json item; each kind's newest
## unlock is equipped.
##
## Progress keys (ctx.progress, the local rider's own store):
##   xp (int), unlocks [id, ...] (unlock order), equipped {kind: id}, records {species id: kg},
##   trophies (int), catch_log [{species, kg, grade, fight_s, trip, date}] (the newest
##   CATCH_LOG_MAX), sessions [session id, ...] (the newest PROGRESS_SESSIONS_KEPT applied).
## The catch log's date comes from the session id's nonce (the host's UTC start in hex
## milliseconds, GAME_SDK 14.1), never from a clock; ids without a nonce (run_game_sim) log "".

const STAT_FISH := "FISHING_STAT_FISH"
const STAT_TROPHIES := "FISHING_STAT_TROPHIES"
const STAT_LOST := "FISHING_STAT_LOST"
const STAT_BIGGEST := "FISHING_STAT_BIGGEST"
const STAT_LONGEST := "FISHING_STAT_LONGEST"
const STAT_POINTS := "FISHING_STAT_POINTS"
const STAT_RANK := "FISHING_STAT_RANK"
const STAT_FURTHEST := "FISHING_STAT_FURTHEST"
const RIDE_TAG_ROAM := "FISHING_RIDE_TAG_ROAM"
const LINE_FISH := "FISHING_LINE_FISH"
const LINE_BIGGEST := "FISHING_LINE_BIGGEST"
const LINE_POINTS := "FISHING_LINE_POINTS"
const LINE_RANK := "FISHING_LINE_RANK"
const LINE_FURTHEST := "FISHING_LINE_FURTHEST"
const TEAM_POINTS := "FISHING_STAT_TEAM_POINTS"
const TEAM_FISH := "FISHING_STAT_TEAM_FISH"
const TEAM_TROPHIES := "FISHING_STAT_TEAM_TROPHIES"
const SUMMARY_KEY := "FISHING_RESULTS"
const NONE_TEXT := "-"

const GRADE_TROPHY_NAME := "trophy"
const GRADE_LANDED_NAME := "landed"
const PROGRESS_SESSIONS_KEPT := 32
const CATCH_LOG_MAX := 500
const MS_PER_DAY := 86400000


static func build(
	st: FishingState,
	stats: SessionStats,
	players: Array[PlayerSlot],
	content: FishingContent,
	strings: GameStrings = null
) -> GameResults:
	var res := GameResults.from_stats(stats, players)
	res.summary_key = SUMMARY_KEY
	if st == null:
		res.grade = "D"
		return res
	var every := unlock_every(content)
	var items := unlock_items(content)
	var team_trophies := 0
	var ranks := rank_of(st)
	for row in res.rows:
		var l := st.rider_of_peer(int(row["peer_id"]))
		if l == null:
			continue
		var rank := int(ranks.get(l.slot, 1))
		row["time_in_band_s"] = l.band_s
		row["time_in_band_pct"] = band_pct(l)
		var recs := new_records(l)
		var xp := xp_for(float(row.get("kj", 0.0)), l.fish_landed, l.trophies, recs.size())
		row["xp"] = xp
		row["unlocks"] = unlocks_between(items, every, l.summary_xp, l.summary_xp + xp)
		row["stats"] = _row_stats(st, l, rank, content, strings)
		row["catches"] = catch_rows(l)
		row["records"] = recs
		row["ride_lines"] = ride_lines(st, l, rank, content, strings)
		team_trophies += l.trophies
	res.team = {TEAM_POINTS: st.team_points, TEAM_FISH: st.team_fish, TEAM_TROPHIES: team_trophies}
	res.score = st.team_points
	res.grade = grade_for(st)
	res.ride_tag = ride_tag(st, content, strings)
	if not res.rows.is_empty():
		res.ride_lines.assign(res.rows[0].get("ride_lines", []))
	return res


## "Free Roam <n> min", or the workout's (or the trip on its own map) name.
static func ride_tag(st: FishingState, content: FishingContent, strings: GameStrings) -> String:
	if content == null or content.trip == null:
		return ""
	if st.roam and content.trip.map == FishingTripDef.DEFAULT_MAP:
		return _t(strings, RIDE_TAG_ROAM, {"min": roundi(content.trip.minutes)})
	return _t(strings, content.trip.label, [])


## A rider's Strava lines.
static func ride_lines(
	st: FishingState, l: FishingRiderState, rank: int, content: FishingContent, strings: GameStrings
) -> Array[String]:
	var out: Array[String] = []
	out.append(_t(strings, LINE_FISH, {"n": l.fish_landed}))
	var biggest := _biggest(l)
	if int(biggest[0]) >= 0:
		var name := species_name(int(biggest[0]), content, strings)
		out.append(_t(strings, LINE_BIGGEST, {"species": name, "kg": "%.1f" % float(biggest[1])}))
	out.append(_t(strings, LINE_POINTS, {"points": l.points}))
	if st.roam and st.riders.size() > 1:
		out.append(_t(strings, LINE_RANK, {"rank": rank, "of": st.riders.size()}))
	out.append(_t(strings, LINE_FURTHEST, {"km": "%.1f" % (l.furthest_x_m / 1000.0)}))
	return out


## slot -> rank by points (1 = most; ties share the better rank).
static func rank_of(st: FishingState) -> Dictionary:
	var out := {}
	for l in st.riders:
		var better := 0
		for o in st.riders:
			if o.points > l.points:
				better += 1
		out[l.slot] = better + 1
	return out


static func _t(strings: GameStrings, key: String, args: Variant) -> String:
	if strings != null:
		return strings.t(key, args)
	return str(TranslationServer.translate(key)).format(args) if args is Dictionary else key


## A row's custom stats in reading order (the grid already shows kJ, %FTP and time in band).
static func _row_stats(
	st: FishingState, l: FishingRiderState, rank: int, content: FishingContent, strings: GameStrings
) -> Dictionary:
	var biggest := _biggest(l)
	var s := {}
	s[STAT_FISH] = l.fish_landed
	s[STAT_TROPHIES] = l.trophies
	s[STAT_LOST] = l.lost_lines
	s[STAT_BIGGEST] = NONE_TEXT
	if int(biggest[0]) >= 0:
		s[STAT_BIGGEST] = (
			"%s %.1f kg" % [species_name(int(biggest[0]), content, strings), float(biggest[1])]
		)
	s[STAT_LONGEST] = clock_text(l.longest_fight_s) if l.longest_fight_s > 0.0 else NONE_TEXT
	s[STAT_POINTS] = l.points
	if st.roam and st.riders.size() > 1:
		s[STAT_RANK] = rank
	s[STAT_FURTHEST] = "%.1f km" % (l.furthest_x_m / 1000.0)
	return s


## The team grade from the state (brief 2.8).
static func grade_for(st: FishingState) -> String:
	var frac := float(st.team_points) / st.expected_points if st.expected_points > 0.0 else 0.0
	return FishingConst.team_grade(frac, st.fish_started > 0)


## Time in the tension band as % of fight time (0 without a fight).
static func band_pct(l: FishingRiderState) -> float:
	if l.fight_total_s <= 0.0:
		return 0.0
	return clampf(100.0 * l.band_s / l.fight_total_s, 0.0, 100.0)


static func xp_for(kj: float, fish: int, trophies: int, records: int) -> int:
	return (
		roundi(maxf(kj, 0.0) * FishingConst.XP_PER_KJ)
		+ FishingConst.XP_PER_FISH * fish
		+ FishingConst.XP_PER_TROPHY * trophies
		+ FishingConst.XP_PER_RECORD * records
	)


## Species whose best catch this session beats the rider's record from their summary (no record
## yet counts as 0): {species id: kg}, in FishingConst.SPECIES order.
static func new_records(l: FishingRiderState) -> Dictionary:
	var best := {}
	for c: Variant in l.catches:
		if not c is Dictionary:
			continue
		var sp := int(c.get("sp", FishingConst.SP_NONE))
		if sp < 0 or sp >= FishingConst.SPECIES.size():
			continue
		var id: String = FishingConst.SPECIES[sp]
		best[id] = maxf(float(best.get(id, 0.0)), float(c.get("kg", 0.0)))
	var out := {}
	for id: String in FishingConst.SPECIES:
		if best.has(id) and float(best[id]) > float(l.records.get(id, 0.0)) + 1e-6:
			out[id] = _tenth(float(best[id]))
	return out


## This session's landed fish as JSON-safe rows: {sp (species id), kg, grade, fight_s}.
static func catch_rows(l: FishingRiderState) -> Array:
	var out: Array = []
	for c: Variant in l.catches:
		if not c is Dictionary:
			continue
		var sp := int(c.get("sp", FishingConst.SP_NONE))
		if sp < 0 or sp >= FishingConst.SPECIES.size():
			continue
		var trophy := int(c.get("grade", FishingConst.GRADE_LANDED)) == FishingConst.GRADE_TROPHY
		var entry := {}
		entry["sp"] = FishingConst.SPECIES[sp]
		entry["kg"] = _tenth(float(c.get("kg", 0.0)))
		entry["grade"] = GRADE_TROPHY_NAME if trophy else GRADE_LANDED_NAME
		entry["fight_s"] = roundi(float(c.get("fight_s", 0.0)))
		out.append(entry)
	return out


## [species index, kg] of the biggest fish (the rider's own fields, else its catch log); -1 none.
static func _biggest(l: FishingRiderState) -> Array:
	if l.biggest_sp >= 0 and l.biggest_kg > 0.0:
		return [l.biggest_sp, l.biggest_kg]
	var out: Array = [FishingConst.SP_NONE, 0.0]
	for c: Variant in l.catches:
		if c is Dictionary and float(c.get("kg", 0.0)) > float(out[1]):
			out = [int(c.get("sp", FishingConst.SP_NONE)), float(c.get("kg", 0.0))]
	return out


static func species_name(sp: int, content: FishingContent, strings: GameStrings) -> String:
	if sp < 0 or sp >= FishingConst.SPECIES.size():
		return ""
	var id: String = FishingConst.SPECIES[sp]
	var key := "FISHING_SPECIES_" + id.to_upper()
	if content != null and content.species.has(id):
		key = (content.species[id] as FishingSpeciesDef).label
	if strings != null:
		return strings.t(key)
	return str(TranslationServer.translate(key))


## `x` rounded to 0.1 (an integer over 10, so 54.2 is the same double as the literal).
static func _tenth(x: float) -> float:
	return roundf(x * 10.0) / 10.0


## "m:ss".
static func clock_text(seconds: float) -> String:
	var s := maxi(roundi(seconds), 0)
	return "%d:%02d" % [floori(s / 60.0), s % 60]


# --- Unlocks ------------------------------------------------------------------------------


static func unlock_every(content: FishingContent) -> int:
	if content == null:
		return FishingConst.XP_PER_UNLOCK
	return maxi(int(content.cosmetics.get("unlock_every_xp", FishingConst.XP_PER_UNLOCK)), 1)


## cosmetics.json items in unlock order.
static func unlock_items(content: FishingContent) -> Array:
	if content == null:
		return []
	var items: Variant = content.cosmetics.get("items", [])
	return items if items is Array else []


## Ids of the items unlocked by a running total of `xp` (every `every` XP, the next item).
static func unlocked_ids(items: Array, every: int, xp: int) -> Array:
	var out: Array = []
	for i in mini(floori(maxi(xp, 0) / float(maxi(every, 1))), items.size()):
		out.append(str(items[i].get("id", "")))
	return out


## Ids unlocked between the running totals `xp_before` and `xp_after`.
static func unlocks_between(items: Array, every: int, xp_before: int, xp_after: int) -> Array:
	var before := unlocked_ids(items, every, xp_before)
	var out: Array = []
	for id: Variant in unlocked_ids(items, every, xp_after):
		if not before.has(id):
			out.append(id)
	return out


## {kind: id}: each kind's newest unlock among `held` (unlock order).
static func equipped_for(items: Array, held: Array) -> Dictionary:
	var out := {}
	for it: Variant in items:
		if it is Dictionary and held.has(str(it.get("id", ""))):
			out[str(it.get("kind", ""))] = str(it["id"])
	return out


## The rider's look [line, canopy, trim, pennant]: each kind's equipped item as its 1-based index
## among that kind's items in cosmetics.json (0 = the default look).
static func cosmetic_indexes(content: FishingContent, equipped: Dictionary) -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0]
	if content == null:
		return out
	for k in FishingContent.COSMETIC_KINDS.size():
		var kind: String = FishingContent.COSMETIC_KINDS[k]
		var of_kind := content.cosmetics_of(kind)
		for i in of_kind.size():
			if str(of_kind[i].get("id", "")) == str(equipped.get(kind, "")):
				out[k] = i + 1
	return out


## How many items of each kind exist [line, canopy, trim, pennant] (the highest look index).
static func cosmetic_counts(content: FishingContent) -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0]
	if content == null:
		return out
	for k in FishingContent.COSMETIC_KINDS.size():
		out[k] = content.cosmetics_of(FishingContent.COSMETIC_KINDS[k]).size()
	return out


# --- Progress ------------------------------------------------------------------------------


## What the summary intent carries, from the local rider's store: {"xp": int, "records":
## {species id: kg}, "cosmetics": Array[int] [line, canopy, trim, pennant]}.
static func summary_from(progress: ProgressStore, content: FishingContent) -> Dictionary:
	var records := {}
	var cos: Array[int] = [0, 0, 0, 0]
	var xp := 0
	if progress != null:
		xp = maxi(int(progress.get_value("xp", 0)), 0)
		var raw: Variant = progress.get_value("records", {})
		if raw is Dictionary:
			for id: Variant in raw:
				if FishingConst.SPECIES.has(str(id)):
					records[str(id)] = maxf(float(raw[id]), 0.0)
		var eq: Variant = progress.get_value("equipped", {})
		var equipped: Dictionary = eq if eq is Dictionary else {}
		if equipped.is_empty():
			equipped = equipped_for(unlock_items(content), _array(progress.get_value("unlocks")))
		cos = cosmetic_indexes(content, equipped)
	return {"xp": xp, "records": records, "cosmetics": cos}


static func apply_progress(
	res: GameResults,
	progress: ProgressStore,
	local_peer: int,
	content: FishingContent,
	trip_id: String
) -> Array:
	var row := res.row(local_peer)
	if row.is_empty() or progress == null:
		return []
	var seen: Array = _array(progress.get_value("sessions", []))
	if res.session_id != "":
		if seen.has(res.session_id):
			return []
		seen.append(res.session_id)
		while seen.size() > PROGRESS_SESSIONS_KEPT:
			seen.pop_front()
		progress.set_value("sessions", seen)
	var xp_after := maxi(int(progress.get_value("xp", 0)), 0) + maxi(int(row.get("xp", 0)), 0)
	progress.set_value("xp", xp_after)
	_log_catches(row, progress, trip_id, date_from_session_id(res.session_id))
	var items := unlock_items(content)
	var held: Array = _array(progress.get_value("unlocks", []))
	var fresh: Array = []
	for id: Variant in unlocked_ids(items, unlock_every(content), xp_after):
		if not held.has(id):
			fresh.append(id)
	held.append_array(fresh)
	progress.set_value("unlocks", held)
	progress.set_value("equipped", equipped_for(items, held))
	return fresh


static func _log_catches(
	row: Dictionary, progress: ProgressStore, trip_id: String, date: String
) -> void:
	var log: Array = _array(progress.get_value("catch_log", []))
	var raw_rec: Variant = progress.get_value("records", {})
	var records: Dictionary = (raw_rec as Dictionary).duplicate() if raw_rec is Dictionary else {}
	var trophies := int(progress.get_value("trophies", 0))
	for c: Variant in _array(row.get("catches", [])):
		if not c is Dictionary:
			continue
		var id := str(c.get("sp", ""))
		var kg := float(c.get("kg", 0.0))
		var grade := str(c.get("grade", GRADE_LANDED_NAME))
		var entry := {}
		entry["species"] = id
		entry["kg"] = kg
		entry["grade"] = grade
		entry["fight_s"] = int(c.get("fight_s", 0))
		entry["trip"] = trip_id
		entry["date"] = date
		log.append(entry)
		if FishingConst.SPECIES.has(id) and kg > float(records.get(id, 0.0)):
			records[id] = kg
		if grade == GRADE_TROPHY_NAME:
			trophies += 1
	while log.size() > CATCH_LOG_MAX:
		log.pop_front()
	progress.set_value("catch_log", log)
	progress.set_value("records", records)
	progress.set_value("trophies", trophies)


static func _array(v: Variant) -> Array:
	return (v as Array).duplicate() if v is Array else []


## "YYYY-MM-DD" (UTC) from a session id "<game>/<content>/<seed>/<hex ms>-<hex n>"; "" when the
## id has no nonce (run_game_sim) or it is not hex.
static func date_from_session_id(session_id: String) -> String:
	var parts := session_id.split("/")
	if parts.size() < 4:
		return ""
	var hex := parts[3].get_slice("-", 0)
	if hex == "" or not hex.is_valid_hex_number(false):
		return ""
	return civil_date(floori(hex.hex_to_int() / float(MS_PER_DAY)))


## "YYYY-MM-DD" of `days` since 1970-01-01 (proleptic Gregorian; H. Hinnant's civil_from_days,
## integer division written as floori so it rounds toward minus infinity).
static func civil_date(days: int) -> String:
	var z := days + 719468
	var era := floori(z / 146097.0)
	var doe := z - era * 146097
	var yoe := floori(
		(doe - floori(doe / 1460.0) + floori(doe / 36524.0) - floori(doe / 146096.0)) / 365.0
	)
	var y := yoe + era * 400
	var doy := doe - (365 * yoe + floori(yoe / 4.0) - floori(yoe / 100.0))
	var mp := floori((5 * doy + 2) / 153.0)
	var d := doy - floori((153 * mp + 2) / 5.0) + 1
	var m := mp + 3 if mp < 10 else mp - 9
	if m <= 2:
		y += 1
	return "%04d-%02d-%02d" % [y, m, d]

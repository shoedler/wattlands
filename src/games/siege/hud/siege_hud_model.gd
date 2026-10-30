class_name SiegeHudModel
extends RefCounted
## What the Siege HUD says (docs/games/siege.md 3 "HUD"), as pure functions of the state, so the
## host and a client (its state rebuilt from snapshots) show the same and the tests read it
## without any Control. The Controls in this folder only draw what these return. The local rider's
## cockpit, which also needs telemetry, has its own model (SiegeCockpitModel).

## The gate counts as failing below this share of its max.
const GATE_LOW_FRAC := 0.3
## Engines nearer than this to the gate (rams) or the moat (towers) raise the warning.
const ENGINE_WARN_M := 200.0
## The cadence band Siege publishes and asks for (rpm).
const CADENCE_LO := 80
const CADENCE_HI := 100
## Half-width of the ERG band around the applied target, as the kit's gauge has it.
const ERG_BAND := 0.05
## Above this many teammates there is no room (the session holds four riders).
const MAX_CARDS := 3
## The Overdrive plate's modes.
const OD_CLOSED := "closed"
const OD_READY := "ready"
const OD_PROMPT := "prompt"
const OD_ACTIVE := "active"
const OD_COOLDOWN := "cooldown"
## Enemy types on the session plate, in this order (warned engines first).
const ENEMY_ORDER: Array[int] = [
	SiegeIds.ENEMY_SPEAR,
	SiegeIds.ENEMY_SHIELD,
	SiegeIds.ENEMY_CHARIOT,
	SiegeIds.ENEMY_RAM,
	SiegeIds.ENEMY_TOWER,
]

## Every string key the HUD uses (a test checks each one exists in strings.csv).
const STRING_KEYS: Array[String] = [
	"SIEGE_HUD_GATE",
	"SIEGE_HUD_GOLD",
	"SIEGE_HUD_TAR",
	"SIEGE_HUD_LITRES",
	"SIEGE_HUD_WAVE",
	"SIEGE_HUD_WARMUP_WAVE",
	"SIEGE_HUD_COOLDOWN",
	"SIEGE_HUD_ENDS_IN",
	"SIEGE_HUD_ROUTE",
	"SIEGE_HUD_CONNECTING",
	"SIEGE_HUD_OVERDRIVE",
	"SIEGE_HUD_OD_READY",
	"SIEGE_HUD_OD_SURGE",
	"SIEGE_HUD_OD_PRESS",
	"SIEGE_HUD_OD_ON",
	"SIEGE_HUD_OD_DOUBLE",
	"SIEGE_HUD_OD_RECHARGING",
	"SIEGE_HUD_OD_WHY_WAVES",
	"SIEGE_HUD_OD_WHY_WARMUP",
	"SIEGE_HUD_OD_WHY_LATE",
	"SIEGE_HUD_OD_WHY_RESCUE",
	"SIEGE_HUD_OD_WHY_AFK",
	"SIEGE_HUD_OD_WHY_COASTING",
	"SIEGE_HUD_BREACH",
	"SIEGE_HUD_BOARDED",
	"SIEGE_HUD_RAM_ON_ROAD",
	"SIEGE_HUD_TOWER_ON_ROAD",
	"SIEGE_HUD_RUSH_ON",
	"SIEGE_HUD_GATE_FAILING",
	"SIEGE_HUD_GATE_FAILING_SHORT",
	"SIEGE_HUD_MARK_OD",
	"SIEGE_HUD_MARK_RESCUE",
	"SIEGE_HUD_MARK_AFK",
	"SIEGE_HUD_CAP_WAVE",
	"SIEGE_HUD_CAP_BREAK",
	"SIEGE_HUD_CAP_WARMUP",
	"SIEGE_HUD_CAP_COOLDOWN",
	"SIEGE_HUD_CAP_SPRINT",
	"SIEGE_HUD_TARGET",
	"SIEGE_HUD_TARGET_NONE",
	"SIEGE_HUD_TARGET_RAMP",
	"SIEGE_HUD_TARGET_RESCUE",
	"SIEGE_HUD_TARGET_SPRINT",
	"SIEGE_HUD_RPM_BAND",
	"SIEGE_HUD_RPM_RESCUE",
	"SIEGE_HUD_BPM",
	"SIEGE_HUD_ERG",
	"SIEGE_HUD_SIM",
	"SIEGE_HUD_GEAR",
	"SIEGE_HUD_WPRIME",
	"SIEGE_HUD_LINE_SPIN",
	"SIEGE_HUD_LINE_LOAD_UP",
	"SIEGE_HUD_LINE_LOW",
	"SIEGE_HUD_LINE_RESCUE",
	"SIEGE_HUD_LINE_COAST",
	"SIEGE_HUD_LINE_SPRINT",
	"SIEGE_HUD_LINE_HOLD",
	"SIEGE_HUD_LINE_EASE",
	"SIEGE_HUD_LINE_NO_DATA",
	"SIEGE_HUD_WKG",
	"SIEGE_HUD_LINE_COOL",
	"SIEGE_HUD_LINE_WARMUP",
	"SIEGE_HUD_NEXT_PHASE",
	"SIEGE_HUD_NEXT_RESULTS",
	"SIEGE_HUD_THEN_ERG",
	"SIEGE_HUD_THEN_RAMP",
	"SIEGE_HUD_NAME_BREAK",
	"SIEGE_WARN_RUSH",
	"SIEGE_PHASE_BUILD_BREAK",
	"SIEGE_PHASE_BREAK_1",
	"SIEGE_PHASE_WARMUP_WAVE",
	"SIEGE_PHASE_WAVE_1",
	"SIEGE_STATION_MINE",
	"SIEGE_STATION_BALLISTA",
	"SIEGE_STATION_ONAGER",
	"SIEGE_STATION_ARROWS",
	"SIEGE_STATION_TAR",
	"SIEGE_PAD",
	"SIEGE_SHOP_TITLE",
	"SIEGE_SHOP_BEST",
	"SIEGE_SHOP_SHORT",
	"SIEGE_SHOP_RECOMMENDED",
	"SIEGE_SHOP_COUNTDOWN",
	"SIEGE_SHOP_COST",
	"SIEGE_SHOP_MORE",
	"SIEGE_ITEM_UPGRADE_1",
	"SIEGE_ITEM_UPGRADE_2",
	"SIEGE_ITEM_UPGRADE_3",
	"SIEGE_ITEM_MINE_1",
	"SIEGE_ITEM_MINE_2",
	"SIEGE_ITEM_MINE_3",
	"SIEGE_ITEM_SCORPION",
	"SIEGE_ITEM_PAD_UPGRADE_1",
	"SIEGE_ITEM_PAD_UPGRADE_2",
	"SIEGE_ITEM_PAD_UPGRADE_3",
	"SIEGE_ITEM_IRON_BANDS",
	"SIEGE_ITEM_REPAIR",
	"SIEGE_ITEM_RESERVE_FLYWHEEL",
	"SIEGE_ITEM_AQUEDUCT_DRIVE",
	"SIEGE_ITEM_SPARE_CAULDRON",
	"SIEGE_ITEM_SAVE",
	"SIEGE_HELP_WHEEL",
	"SIEGE_HELP_PATH",
	"SIEGE_HELP_STATIONS",
	"SIEGE_HELP_ROAD",
	"SIEGE_HELP_GATE",
	"SIEGE_HELP_ROUTE_CARD",
	"SIEGE_HELP_SHOP",
]


static func strings_of(game: SiegeGame) -> GameStrings:
	if game != null and game.ctx != null and game.ctx.strings != null:
		return game.ctx.strings
	return GameStrings.new()


## The local rider's state (null when the local peer has no wheel or there is no state).
static func own_rider(game: SiegeGame) -> SiegeRiderState:
	if game == null or game.state == null or game.ctx == null:
		return null
	return game.state.rider(game.ctx.local_peer)


## The session's look of `slot` (color, shape, pattern, hollow).
static func look_of(game: SiegeGame, slot: int) -> Dictionary:
	if game != null and game.ctx != null:
		for p in game.ctx.players:
			if p.slot_index == slot:
				return {
					"color": p.color, "shape": p.shape, "pattern": p.pattern, "hollow": p.hollow
				}
	return Wl.slot_look(slot)


## The rider's name (never empty).
static func rider_name(game: SiegeGame, r: SiegeRiderState) -> String:
	if game != null and game.ctx != null:
		var p := game.ctx.player(r.peer)
		if p != null and p.name != "":
			return p.name
	return "Rider %d" % (r.slot + 1)


static func phase_remaining_s(state: SiegeState) -> float:
	if state == null or state.phase_duration_s <= 0.0:
		return 0.0
	return maxf(state.phase_duration_s - state.phase_elapsed_s, 0.0)


## "Wave 2 of 3", "Warm-up wave", "Break 1", "Build break", "Cool-down".
static func wave_title(state: SiegeState, strings: GameStrings) -> String:
	if state == null:
		return ""
	match state.role:
		SiegeIds.ROLE_WARMUP_WAVE:
			return strings.t("SIEGE_HUD_WARMUP_WAVE")
		SiegeIds.ROLE_WAVE:
			return strings.t("SIEGE_HUD_WAVE", [state.wave_no, maxi(state.waves_total, 1)])
		SiegeIds.ROLE_BUILD_BREAK:
			return strings.t("SIEGE_PHASE_BUILD_BREAK")
		SiegeIds.ROLE_BREAK:
			return strings.t("SIEGE_PHASE_BREAK_%d" % clampi(state.wave_no, 1, 10))
		SiegeIds.ROLE_COOLDOWN:
			return strings.t("SIEGE_HUD_COOLDOWN")
	return ""


## The watts a plan's percent comes out as on the trainer: the unverified factor, whole watts
## rounded down, the floor and the ceiling (BRIEF 4.6.1, 4.6.12; GovernorClamps). A preview of what
## the governor will apply: what it does apply comes from telemetry.
static func applied_w(pct: float, ftp: float, verified: bool = true) -> int:
	var w := GovernorClamps.pct_to_w(pct, ftp) * GovernorClamps.unverified_factor(verified)
	return clampi(
		GovernorClamps.whole_w(w), GovernorClamps.floor_w(ftp), GovernorClamps.ceiling_w(ftp)
	)


## The phase's planned target in percent `elapsed_s` into it (a ramp's value by then).
static func phase_pct(ph: PlanPhase, elapsed_s: float) -> float:
	if ph == null:
		return 0.0
	if not ph.has_ramp() or ph.duration_s <= 0.0:
		return ph.target_pct
	return lerpf(ph.target_pct, ph.ramp_to_pct, clampf(elapsed_s / ph.duration_s, 0.0, 1.0))


## The session plate: {"title", "ends", "total_s", "elapsed_s", "index", "phases" [{"from_s", "d",
## "p0", "p1", "kind"}], "rush" [seconds into the session], "enemies" [{"icon", "n", "warn"}],
## "warning"}. ENDS IN counts the cool-down too (nominal length minus elapsed).
static func session_face(game: SiegeGame) -> Dictionary:
	var s := game.state
	var tx := strings_of(game)
	var r := own_rider(game)
	var peer := r.peer if r != null else (s.riders[0].peer if not s.riders.is_empty() else 0)
	var plan := game.hud_plan(peer)
	var phases: Array[Dictionary] = []
	var at := 0.0
	var start := 0.0
	var idx := clampi(s.phase_index, -1, plan.size() - 1)
	for i in plan.size():
		var ph := plan.phase(i)
		if i == idx:
			start = at
		(
			phases
			. append(
				{
					"from_s": at,
					"d": ph.duration_s,
					"p0": ph.target_pct,
					"p1": ph.ramp_to_pct if ph.has_ramp() else ph.target_pct,
					"kind": ph.kind,
				}
			)
		)
		at += ph.duration_s
	var elapsed := start + s.phase_elapsed_s if idx >= 0 else 0.0
	var rush: Array[float] = []
	for t in rush_times(s):
		rush.append(start + t)
	var w := warning(s)
	return {
		"title": wave_title(s, tx),
		"ends": tx.t("SIEGE_HUD_ENDS_IN", [HudWidget.clock_text(maxf(at - elapsed, 0.0))]),
		"total_s": at,
		"elapsed_s": elapsed,
		"index": idx,
		"phases": phases,
		"rush": rush,
		"enemies": enemy_icons(s),
		"warning": tx.t(w["key"], w["args"]) if not w.is_empty() else "",
	}


## The enemies left by type as icons and counts: engines in the warning range first (their icon
## lit), then ENEMY_ORDER; types with none are left out. Empty outside waves.
static func enemy_icons(state: SiegeState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or not state.in_wave():
		return out
	var alive := state.alive_by_type()
	var warned: Array[int] = []
	for type: int in [SiegeIds.ENEMY_TOWER, SiegeIds.ENEMY_RAM]:
		var e := nearest_engine(state, type)
		if not e.is_empty() and float(e["m"]) <= ENGINE_WARN_M:
			warned.append(type)
			out.append({"icon": SiegeIds.ENEMY_NAMES[type], "n": alive[type], "warn": true})
	for type in ENEMY_ORDER:
		if type < alive.size() and alive[type] > 0 and not warned.has(type):
			out.append({"icon": SiegeIds.ENEMY_NAMES[type], "n": alive[type], "warn": false})
	return out


## The nearest live engine of `type` and how far it still has to go (to the gate for a ram, to
## the moat edge for a tower): {"e": SiegeEnemyState, "m": float}, or {} for none.
static func nearest_engine(state: SiegeState, type: int) -> Dictionary:
	var best: SiegeEnemyState = null
	var best_m := INF
	var end_m := state.path.moat_edge_m if type == SiegeIds.ENEMY_TOWER else state.path.length_m
	for e in state.enemies:
		if e.type != type or not e.alive():
			continue
		var m := maxf(end_m - e.prog_m, 0.0)
		if m < best_m:
			best_m = m
			best = e
	return {} if best == null else {"e": best, "m": best_m}


## The most urgent warning: {"key", "args", "level" 0..2}, or {} for none. In order: a Breach,
## boarders on the wall, a rush on, a siege tower or a ram closing in, a rush coming, a failing
## gate.
static func warning(state: SiegeState) -> Dictionary:
	if state == null:
		return {}
	if state.breach_s > 0.0:
		return {"key": "SIEGE_HUD_BREACH", "args": [ceili(state.breach_s)], "level": 2}
	if not state.in_wave():
		return {}
	if state.tar.boarded:
		return {"key": "SIEGE_HUD_BOARDED", "args": [], "level": 2}
	if state.rush_on():
		return {"key": "SIEGE_HUD_RUSH_ON", "args": [ceili(state.wave.rush_s)], "level": 2}
	var tower := nearest_engine(state, SiegeIds.ENEMY_TOWER)
	if not tower.is_empty() and float(tower["m"]) <= ENGINE_WARN_M:
		return {"key": "SIEGE_HUD_TOWER_ON_ROAD", "args": [roundi(tower["m"])], "level": 2}
	var ram := nearest_engine(state, SiegeIds.ENEMY_RAM)
	if not ram.is_empty() and float(ram["m"]) <= ENGINE_WARN_M:
		return {"key": "SIEGE_HUD_RAM_ON_ROAD", "args": [roundi(ram["m"])], "level": 2}
	# the next rush still ahead on the phase clock (a restarted client's rush_next may be stale)
	for t in rush_times(state):
		var ahead := t - state.phase_elapsed_s
		if ahead > 0.0:
			if ahead <= 15.0:
				return {"key": "SIEGE_WARN_RUSH", "args": [], "level": 1}
			break
	if gate_low(state):
		return {"key": "SIEGE_HUD_GATE_FAILING_SHORT", "args": [], "level": 1}
	return {}


static func gate_low(state: SiegeState) -> bool:
	return state != null and state.gate_hp < state.gate_max * GATE_LOW_FRAC


## The current phase's rush times (wave seconds) from the shift.
static func rush_times(state: SiegeState) -> Array[float]:
	var out: Array[float] = []
	if state == null or state.content == null or state.phase_index < 0:
		return out
	var phases: Array = state.content.shift.get("phases", [])
	if state.phase_index >= phases.size():
		return out
	for t: Variant in (phases[state.phase_index] as Dictionary).get("rushes_at_s", []):
		out.append(float(t))
	return out


## The red world tags: {"at": art px over the engine's head, "text"} for the nearest live tower and
## ram in the warning range, in that order.
static func world_tags(state: SiegeState, strings: GameStrings) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or not state.in_wave() or state.path == null:
		return out
	var kinds := [
		[SiegeIds.ENEMY_TOWER, "SIEGE_HUD_TOWER_ON_ROAD", SiegeHudWorld.TOWER_HEAD_PX],
		[SiegeIds.ENEMY_RAM, "SIEGE_HUD_RAM_ON_ROAD", SiegeHudWorld.RAM_HEAD_PX],
	]
	for k: Array in kinds:
		var near := nearest_engine(state, int(k[0]))
		if near.is_empty() or float(near["m"]) > ENGINE_WARN_M:
			continue
		var e: SiegeEnemyState = near["e"]
		var art := state.path.to_art(state.path.point_at(e.prog_m, e.lat_m))
		(
			out
			. append(
				{
					"at": Vector2i(roundi(art.x), roundi(art.y) - int(k[2])),
					"text": strings.t(str(k[1]), [roundi(near["m"])]),
				}
			)
		)
	return out


## The five station rows: [{"id", "icon", "name", "riders" (slots), "count", "cap", "full", "mine"
## (the local rider is on it), "going" (the local rider is coupling to it), "hot" (Autopilot's pick
## for the local rider)}]. `here` is where the local rider still is while it couples (-1: its
## target).
static func station_rows(
	state: SiegeState, strings: GameStrings, own: SiegeRiderState, here: int = -1
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	var hot := SiegeAutopilot.hot_target(state, own) if own != null else -1
	var at := own.target if own != null and here < 0 else here
	for id in SiegeIds.STATION_COUNT:
		var slots: Array[int] = []
		for r in state.riders:
			if r.target == id:
				slots.append(r.slot)
		var cap := state.station_cap(id)
		(
			out
			. append(
				{
					"id": id,
					"icon": SiegeIds.STATION_NAMES[id],
					"name": strings.t(SiegeGame.station_key(id)),
					"riders": slots,
					"count": slots.size(),
					"cap": cap,
					"full": slots.size() >= cap,
					"mine": own != null and at == id,
					"going": own != null and own.target == id and at != id,
					"hot": id == hot,
				}
			)
		)
	return out


## Raw watts as a share of the rider's FTP, in whole percent.
static func pct_ftp(rider: SiegeRiderState) -> int:
	if rider == null or rider.ftp <= 0.0:
		return 0
	return roundi(rider.raw_w / rider.ftp * 100.0)


## The teammate cards, every rider but the local one, slot order, at most MAX_CARDS: [{"slot",
## "shape", "color", "name", "w" (-1: no data), "pct", "icon" (the station), "afk", "mark",
## "mark_kind" ("" lamp, "od", "alarm", "dim"), "lamp" (HudRiderNumbers.UNDER, IN_BAND, OVER)}].
## `tracks` holds one HudRiderNumbers per slot between calls: the lamp's hysteresis on snapshot data.
static func crew_cards(game: SiegeGame, tracks: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var s := game.state
	var me := own_rider(game)
	var tx := strings_of(game)
	for r in s.riders:
		if r == me or out.size() >= MAX_CARDS:
			continue
		var look := look_of(game, r.slot)
		var afk := r.afk or not r.connected
		var track: HudRiderNumbers = tracks.get(r.slot, null)
		if track == null:
			track = HudRiderNumbers.new()
			tracks[r.slot] = track
		var band := rider_band(game, r)
		track.set_band(band.x, band.y)
		track.push_power(s.t, r.raw_w)
		var mark := ""
		var mark_kind := ""
		if afk:
			mark = tx.t("SIEGE_HUD_MARK_AFK")
			mark_kind = "dim"
		elif r.rescue:
			mark = tx.t("SIEGE_HUD_MARK_RESCUE")
			mark_kind = "alarm"
		elif r.od_state == SiegeIds.OD_ACTIVE:
			mark = "%s %s" % [tx.t("SIEGE_HUD_MARK_OD"), HudWidget.clock_text(r.od_s)]
			mark_kind = "od"
		(
			out
			. append(
				{
					"slot": r.slot,
					"shape": str(look["shape"]),
					"color": look["color"],
					"name": rider_name(game, r),
					"w": roundi(r.raw_w) if r.connected else -1,
					"pct": pct_ftp(r),
					"icon": SiegeIds.STATION_NAMES[clampi(r.target, 0, SiegeIds.STATION_COUNT - 1)],
					"afk": afk,
					"mark": mark,
					"mark_kind": mark_kind,
					"lamp": track.band_state(),
				}
			)
		)
	return out


## The band a rider is judged against: the sprint band in Overdrive, else the plan's target +-5%.
static func rider_band(game: SiegeGame, r: SiegeRiderState) -> Vector2:
	var s := game.state
	if r.od_state == SiegeIds.OD_ACTIVE:
		return SiegeOverdrive.band_w(s.content, r.ftp)
	var plan := game.hud_plan(r.peer)
	var ph := plan.phase(s.phase_index)
	if ph == null:
		return Vector2.ZERO
	var w := float(applied_w(phase_pct(ph, s.phase_elapsed_s), r.ftp, r.ftp_verified))
	return Vector2(w * (1.0 - ERG_BAND), w * (1.0 + ERG_BAND))


## The right column's fort and gold: {"gate", "gate_max", "low", "gate_frac", "curtain",
## "curtain_max", "curtain_frac", "litres", "gold", "gold_big"}. The gold's size follows the shop:
## NUM in waves, where it can't be spent, KEY while it is the number that decides.
static func fort_face(state: SiegeState, rider: SiegeRiderState) -> Dictionary:
	var curtain_max := roundi(state.curtain_max())
	var curtain := ceili(state.tar.curtain_hp)
	return {
		"gate": ceili(state.gate_hp),
		"gate_max": roundi(state.gate_max),
		"low": gate_low(state),
		"gate_frac": state.gate_hp / maxf(state.gate_max, 1.0),
		"curtain": curtain,
		"curtain_max": curtain_max,
		"curtain_frac": float(curtain) / maxf(float(curtain_max), 1.0),
		"litres": floori(state.tar.cauldron_l),
		"gold": floori(rider.gold) if rider != null else 0,
		"gold_big": state.shop_open(),
	}


## The Overdrive plate's face: {"mode": OD_*, "top", "sub", "fill": 0..1, "enabled"}. A closed plate
## says why, from the rules' own gate (SiegeOverdrive.blocked_reason).
static func overdrive_face(game: SiegeGame) -> Dictionary:
	var s := game.state if game != null else null
	var r := own_rider(game)
	var tx := strings_of(game)
	var cfg := s.content if s != null else null
	var cooldown_s := cfg.num("overdrive.cooldown_s", 90.0) if cfg != null else 90.0
	var duration_s := cfg.num("overdrive.duration_s", 30.0) if cfg != null else 30.0
	if s == null or r == null:
		return _od(OD_CLOSED, tx.t("SIEGE_HUD_OVERDRIVE"), "", 0.0, false)
	match r.od_state:
		SiegeIds.OD_ACTIVE, SiegeIds.OD_PENDING:
			return _od(
				OD_ACTIVE,
				tx.t("SIEGE_HUD_OD_ON", [HudWidget.clock_text(r.od_s)]),
				tx.t("SIEGE_HUD_OD_DOUBLE"),
				clampf(r.od_s / duration_s, 0.0, 1.0),
				false
			)
		SiegeIds.OD_COOLDOWN:
			return _od(
				OD_COOLDOWN,
				tx.t("SIEGE_HUD_OD_RECHARGING"),
				HudWidget.clock_text(r.od_cd_s),
				1.0 - clampf(r.od_cd_s / cooldown_s, 0.0, 1.0),
				false
			)
	if r.od_prompt:
		return _od(OD_PROMPT, tx.t("SIEGE_HUD_OD_READY"), tx.t("SIEGE_HUD_OD_SURGE"), 1.0, true)
	# the rules' own gate (a human, READY, a WORK phase with >= 30 s left, no rescue, not AFK,
	# pedalling): the plate only takes a press when it would start Overdrive
	var why := SiegeOverdrive.blocked_reason(s, r, phase_info(s))
	if why == "":
		return _od(OD_READY, tx.t("SIEGE_HUD_OD_READY"), tx.t("SIEGE_HUD_OD_PRESS"), 1.0, true)
	return _od(OD_CLOSED, tx.t("SIEGE_HUD_OVERDRIVE"), tx.t(_od_why_key(s, why)), 0.0, false)


static func _od(mode: String, top: String, sub: String, fill: float, enabled: bool) -> Dictionary:
	return {"mode": mode, "top": top, "sub": sub, "fill": fill, "enabled": enabled}


static func _od_why_key(s: SiegeState, why: String) -> String:
	match why:
		SiegeOverdrive.WHY_TOO_LATE:
			return "SIEGE_HUD_OD_WHY_LATE"
		SiegeOverdrive.WHY_RESCUE:
			return "SIEGE_HUD_OD_WHY_RESCUE"
		SiegeOverdrive.WHY_AFK:
			return "SIEGE_HUD_OD_WHY_AFK"
		SiegeOverdrive.WHY_COASTING:
			return "SIEGE_HUD_OD_WHY_COASTING"
	return "SIEGE_HUD_OD_WHY_WARMUP" if s.phase_kind == Wl.WARMUP else "SIEGE_HUD_OD_WHY_WAVES"


## The phase as the rules' SiegePhaseInfo, from the state (as SiegeGame._refresh_prompts does).
static func phase_info(s: SiegeState) -> SiegePhaseInfo:
	var info := SiegePhaseInfo.new()
	info.index = s.phase_index
	info.kind = s.phase_kind
	info.role = s.role
	info.number = s.wave_no
	info.waves = s.waves_total
	info.elapsed_s = s.phase_elapsed_s
	info.duration_s = s.phase_duration_s
	info.remaining_s = s.phase_remaining_s
	return info

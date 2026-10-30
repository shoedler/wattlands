class_name SiegeHudModel
extends RefCounted
## What the Siege HUD says (docs/games/siege.md 3 "HUD"), as pure functions of the state, so the
## host and a client (its state rebuilt from snapshots) show the same and the tests read it
## without any Control. The Controls in this folder only format and draw what these return.

## The gate counts as failing below this share of its max.
const GATE_LOW_FRAC := 0.3
## Engines nearer than this to the gate (rams) or the moat (towers) raise the warning.
const ENGINE_WARN_M := 200.0
## The Overdrive button's modes.
const OD_CLOSED := "closed"
const OD_READY := "ready"
const OD_PROMPT := "prompt"
const OD_ACTIVE := "active"
const OD_COOLDOWN := "cooldown"
## Enemy types in the wave info, in this order.
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
	"SIEGE_HUD_CURTAIN",
	"SIEGE_HUD_CAULDRONS",
	"SIEGE_HUD_WAVE",
	"SIEGE_HUD_WARMUP_WAVE",
	"SIEGE_HUD_ENEMIES_LEFT",
	"SIEGE_HUD_QUEUED",
	"SIEGE_HUD_ENEMY_COUNT",
	"SIEGE_HUD_ROUTE",
	"SIEGE_HUD_CONNECTING",
	"SIEGE_HUD_CAP",
	"SIEGE_HUD_OVERDRIVE",
	"SIEGE_HUD_OVERDRIVE_READY",
	"SIEGE_HUD_OVERDRIVE_ON",
	"SIEGE_HUD_OVERDRIVE_COOLDOWN",
	"SIEGE_HUD_TEAM_WATTS",
	"SIEGE_HUD_RUSHES",
	"SIEGE_HUD_BREACH",
	"SIEGE_HUD_VICTORY",
	"SIEGE_HUD_RAM_ON_ROAD",
	"SIEGE_HUD_TOWER_ON_ROAD",
	"SIEGE_HUD_RUSH_ON",
	"SIEGE_HUD_BTN_PREV",
	"SIEGE_HUD_BTN_NEXT",
	"SIEGE_HUD_BTN_MINE",
	"SIEGE_HUD_BTN_HOT",
	"SIEGE_HUD_MARK_OD",
	"SIEGE_HUD_MARK_RESCUE",
	"SIEGE_HUD_MARK_AFK",
	"SIEGE_PROMPT_OVERDRIVE",
	"SIEGE_WARN_RUSH",
	"SIEGE_WARN_GATE_LOW",
	"SIEGE_WARN_BOARDED",
	"SIEGE_PHASE_BUILD_BREAK",
	"SIEGE_PHASE_BREAK_1",
	"SIEGE_STATION_MINE",
	"SIEGE_STATION_BALLISTA",
	"SIEGE_STATION_ONAGER",
	"SIEGE_STATION_ARROWS",
	"SIEGE_STATION_TAR",
	"SIEGE_ENEMY_SPEAR",
	"SIEGE_ENEMY_SHIELD",
	"SIEGE_ENEMY_CHARIOT",
	"SIEGE_ENEMY_RAM",
	"SIEGE_ENEMY_TOWER",
	"SIEGE_PAD",
	"SIEGE_SHOP_TITLE",
	"SIEGE_SHOP_RECOMMENDED",
	"SIEGE_SHOP_COUNTDOWN",
	"SIEGE_SHOP_COST",
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


static func phase_remaining_s(state: SiegeState) -> float:
	if state == null or state.phase_duration_s <= 0.0:
		return 0.0
	return maxf(state.phase_duration_s - state.phase_elapsed_s, 0.0)


## "Wave 2/3", "Warm-up wave", "Break 1", "Build break", "The fort stands!".
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
			return strings.t("SIEGE_HUD_VICTORY")
	return ""


## The enemies left by type in two lines ("Spearmen 12   Shield bearers 3" ...; types with none
## are left out, "+3 waiting" joins the end). Empty outside waves.
static func enemy_lines(state: SiegeState, strings: GameStrings) -> Array[String]:
	var out: Array[String] = []
	if state == null or not state.in_wave():
		return out
	var alive := state.alive_by_type()
	var parts: Array[String] = []
	for type in ENEMY_ORDER:
		if type < alive.size() and alive[type] > 0:
			var name := strings.t("SIEGE_ENEMY_" + SiegeIds.ENEMY_NAMES[type].to_upper())
			parts.append(strings.t("SIEGE_HUD_ENEMY_COUNT", [name, alive[type]]))
	var queued := state.queued()
	if queued > 0:
		parts.append(strings.t("SIEGE_HUD_QUEUED", [queued]))
	if parts.is_empty():
		return out
	var split := ceili(parts.size() / 2.0)
	out.append("   ".join(parts.slice(0, split)))
	if parts.size() > split:
		out.append("   ".join(parts.slice(split)))
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
		return {"key": "SIEGE_WARN_BOARDED", "args": [], "level": 2}
	if state.rush_on():
		return {"key": "SIEGE_HUD_RUSH_ON", "args": [ceili(state.wave.rush_s)], "level": 2}
	var tower := nearest_engine(state, SiegeIds.ENEMY_TOWER)
	if not tower.is_empty() and float(tower["m"]) <= ENGINE_WARN_M:
		return {"key": "SIEGE_HUD_TOWER_ON_ROAD", "args": [roundi(tower["m"])], "level": 2}
	var ram := nearest_engine(state, SiegeIds.ENEMY_RAM)
	if not ram.is_empty() and float(ram["m"]) <= ENGINE_WARN_M:
		return {"key": "SIEGE_HUD_RAM_ON_ROAD", "args": [roundi(ram["m"])], "level": 2}
	var rushes := rush_times(state)
	var next := state.wave.rush_next
	if next < rushes.size() and rushes[next] - state.phase_elapsed_s <= 15.0:
		return {"key": "SIEGE_WARN_RUSH", "args": [], "level": 1}
	if state.gate_hp < state.gate_max * GATE_LOW_FRAC:
		return {"key": "SIEGE_WARN_GATE_LOW", "args": [], "level": 1}
	return {}


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


## The rush markers as fractions (0..1) of the wave ([] without rushes).
static func rush_fractions(state: SiegeState) -> Array[float]:
	var out: Array[float] = []
	var d := state.phase_duration_s if state != null else 0.0
	if d <= 0.0:
		return out
	for t in rush_times(state):
		out.append(clampf(t / d, 0.0, 1.0))
	return out


## The five route-card rows: [{"id", "name", "riders" (slots), "count", "cap", "full", "mine"
## (the local rider is on it), "hot" (Autopilot's pick for the local rider)}].
static func station_rows(
	state: SiegeState, strings: GameStrings, own: SiegeRiderState
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	var hot := SiegeAutopilot.hot_target(state, own) if own != null else -1
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
					"name": strings.t(SiegeGame.station_key(id)),
					"riders": slots,
					"count": slots.size(),
					"cap": cap,
					"full": slots.size() >= cap,
					"mine": own != null and own.target == id,
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


## The Overdrive button's face: {"mode": OD_*, "text", "fill": 0..1, "enabled"}.
static func overdrive_face(game: SiegeGame) -> Dictionary:
	var s := game.state if game != null else null
	var r := own_rider(game)
	var strings := strings_of(game)
	var cfg := s.content if s != null else null
	var cooldown_s := cfg.num("overdrive.cooldown_s", 90.0) if cfg != null else 90.0
	var duration_s := cfg.num("overdrive.duration_s", 30.0) if cfg != null else 30.0
	if s == null or r == null:
		return {
			"mode": OD_CLOSED,
			"text": strings.t("SIEGE_HUD_OVERDRIVE"),
			"fill": 0.0,
			"enabled": false
		}
	match r.od_state:
		SiegeIds.OD_ACTIVE, SiegeIds.OD_PENDING:
			return {
				"mode": OD_ACTIVE,
				"text": strings.t("SIEGE_HUD_OVERDRIVE_ON", [ceili(r.od_s)]),
				"fill": clampf(r.od_s / duration_s, 0.0, 1.0),
				"enabled": false,
			}
		SiegeIds.OD_COOLDOWN:
			return {
				"mode": OD_COOLDOWN,
				"text": strings.t("SIEGE_HUD_OVERDRIVE_COOLDOWN", [ceili(r.od_cd_s)]),
				"fill": 1.0 - clampf(r.od_cd_s / cooldown_s, 0.0, 1.0),
				"enabled": false,
			}
	if r.od_prompt:
		return {
			"mode": OD_PROMPT,
			"text": strings.t("SIEGE_PROMPT_OVERDRIVE"),
			"fill": 1.0,
			"enabled": true
		}
	var in_work := s.in_wave() and s.phase_kind == Wl.WORK
	return {
		"mode": OD_READY if in_work else OD_CLOSED,
		"text":
		"%s  %s" % [strings.t("SIEGE_HUD_OVERDRIVE"), strings.t("SIEGE_HUD_OVERDRIVE_READY")],
		"fill": 1.0,
		"enabled": in_work,
	}


## The curtain card's text: "80 / 200" and "Cauldrons 210 L".
static func curtain_text(state: SiegeState) -> String:
	if state == null:
		return ""
	return "%d / %d" % [ceili(state.tar.curtain_hp), roundi(state.curtain_max())]


static func cauldron_text(state: SiegeState, strings: GameStrings) -> String:
	if state == null:
		return ""
	return strings.t("SIEGE_HUD_CAULDRONS", [floori(state.tar.cauldron_l)])

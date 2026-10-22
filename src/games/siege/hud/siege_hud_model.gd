class_name SiegeHudModel
extends RefCounted
## What the Siege HUD says, as pure functions of the state (so the same text shows on the host
## and on a client, from the snapshot-rebuilt state, and the tests can read it without any
## Control). The Controls in this folder only format and draw what these return.

## Ram warning window: the push comes at waves.json ram_push.at_left_s left; warn this long
## before it.
const RAM_WARN_LEAD_S := 20.0
## The gate counts as failing below this share of its max.
const GATE_LOW_FRAC := 0.3
## The Overdrive button's modes.
const OD_CLOSED := "closed"
const OD_READY := "ready"
const OD_PROMPT := "prompt"
const OD_ACTIVE := "active"
const OD_COOLDOWN := "cooldown"


static func strings_of(game: SiegeGame) -> GameStrings:
	if game != null and game.ctx != null and game.ctx.strings != null:
		return game.ctx.strings
	return GameStrings.new()


## The local rider's state (null when the local peer has no wheel or there is no state).
static func own_rider(game: SiegeGame) -> SiegeRiderState:
	if game == null or game.state == null or game.ctx == null:
		return null
	return game.state.rider(game.ctx.local_peer)


## Seconds of the current phase: the state's when the host filled it, else the shift's plan
## (every peer has the shift; a client's state never learns the duration).
static func phase_duration_s(game: SiegeGame) -> float:
	var s := game.state if game != null else null
	if s == null:
		return 0.0
	if s.phase_duration_s > 0.0:
		return s.phase_duration_s
	if s.content != null and s.phase_index >= 0:
		var phases: Array = s.content.shift.get("phases", [])
		if s.phase_index < phases.size():
			return float((phases[s.phase_index] as Dictionary).get("duration_s", 0.0))
	return 0.0


static func phase_remaining_s(game: SiegeGame) -> float:
	var s := game.state if game != null else null
	if s == null:
		return 0.0
	var d := phase_duration_s(game)
	if d <= 0.0:
		return 0.0
	return maxf(d - s.phase_elapsed_s, 0.0)


## "Wave 2/3", "Warm-up wave", "Break 1", "Build break", "The siege is lifted".
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


## The remaining enemies by type, two lines: "Raiders 12   Shield wall 3" and
## "Horsemen 5   Battering ram 1" (types with none are left out; "+3 waiting" joins the end).
static func enemy_lines(state: SiegeState, strings: GameStrings) -> Array[String]:
	var out: Array[String] = []
	if state == null or not (state.in_wave() or state.in_cooldown()):
		return out
	var alive := state.alive_by_type()
	var names := {
		SiegeIds.ENEMY_RAIDERS: "SIEGE_ENEMY_RAIDERS",
		SiegeIds.ENEMY_SHIELD_WALL: "SIEGE_ENEMY_SHIELD_WALL",
		SiegeIds.ENEMY_HORSEMEN: "SIEGE_ENEMY_HORSEMEN",
		SiegeIds.ENEMY_RAM: "SIEGE_ENEMY_RAM",
	}
	var parts: Array[String] = []
	for type in [
		SiegeIds.ENEMY_RAIDERS,
		SiegeIds.ENEMY_SHIELD_WALL,
		SiegeIds.ENEMY_HORSEMEN,
		SiegeIds.ENEMY_RAM
	]:
		if alive[type] > 0:
			parts.append(strings.t("SIEGE_HUD_ENEMY_COUNT", [strings.t(names[type]), alive[type]]))
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


## The most urgent warning line: {"key": String, "args": Array, "level": 0..2} or {} for none.
## Breach, a rush, a ram on the road, the ram push coming, the horn before the roads change, a
## failing gate, in that order.
static func warning(game: SiegeGame) -> Dictionary:
	var s := game.state if game != null else null
	if s == null:
		return {}
	if s.breach_s > 0.0:
		return {"key": "SIEGE_HUD_BREACH", "args": [ceili(s.breach_s)], "level": 2}
	if s.rush_on():
		return {"key": "SIEGE_HUD_RUSH_ON", "args": [], "level": 2}
	if s.in_wave():
		if s.alive_by_type()[SiegeIds.ENEMY_RAM] > 0:
			return {"key": "SIEGE_HUD_RAM_ON_ROAD", "args": [], "level": 2}
		var push_at := 60.0
		if s.content != null:
			push_at = float(
				(s.content.waves.get("ram_push", {}) as Dictionary).get("at_left_s", 60.0)
			)
		var left := phase_remaining_s(game)
		if left > push_at and left <= push_at + RAM_WARN_LEAD_S:
			return {"key": "SIEGE_WARN_RAM", "args": [ceili(left - push_at)], "level": 1}
		if s.wave.horn_s > 0.0:
			return {"key": "SIEGE_WARN_HORN", "args": [ceili(s.wave.horn_s)], "level": 1}
		if s.gate_hp < s.gate_max * GATE_LOW_FRAC:
			return {"key": "SIEGE_WARN_GATE_LOW", "args": [], "level": 1}
	return {}


## "GEN" or "T3".
static func target_short(strings: GameStrings, target: int) -> String:
	if SiegeIds.is_pad(target):
		return strings.t("SIEGE_HUD_TARGET_PAD", [target])
	return strings.t("SIEGE_HUD_TARGET_GEN")


## "Generator" or "Tower 3 (Ballista)" (the tower's name when one stands on the pad).
static func target_long(state: SiegeState, strings: GameStrings, target: int) -> String:
	if not SiegeIds.is_pad(target):
		return strings.t("SIEGE_HUD_ROUTE_GEN")
	var text := strings.t("SIEGE_HUD_ROUTE_PAD", [target])
	if state != null and state.pad(target).built():
		var type := state.pad(target).type
		text += " (%s)" % strings.t("SIEGE_TOWER_%s" % SiegeIds.TOWER_NAMES[type].to_upper())
	return text


## Raw watts as a share of the rider's FTP, in whole percent.
static func pct_ftp(rider: SiegeRiderState) -> int:
	if rider == null or rider.ftp <= 0.0:
		return 0
	return roundi(rider.raw_w / rider.ftp * 100.0)


## The kind of the plan phase now (Wl.WARMUP, WORK or RECOVERY; COOLDOWN after the shift's last
## phase), from the state or, on a client whose state never learns it, from the shift's plan.
static func phase_kind(game: SiegeGame) -> String:
	var s := game.state if game != null else null
	if s == null:
		return ""
	if s.phase_kind != "":
		return s.phase_kind
	if s.role == SiegeIds.ROLE_COOLDOWN:
		return Wl.COOLDOWN
	if s.content != null and s.phase_index >= 0:
		var phases: Array = s.content.shift.get("phases", [])
		if s.phase_index < phases.size():
			return str((phases[s.phase_index] as Dictionary).get("kind", ""))
	return ""


## Whether the Overdrive prompt shows for the local rider: the host's flag, or (on a client,
## whose snapshot carries no prompt) the rules' own SiegeOverdrive.prompt on the state rebuilt
## from the snapshot and the shift's plan.
static func overdrive_prompt(game: SiegeGame) -> bool:
	var r := own_rider(game)
	if r == null:
		return false
	if r.od_prompt:
		return true
	if game.ctx.role != Wl.CLIENT:
		return false
	var info := SiegePhaseInfo.new()
	info.index = game.state.phase_index
	info.kind = phase_kind(game)
	info.role = game.state.role
	info.remaining_s = phase_remaining_s(game)
	return SiegeOverdrive.prompt(game.state, r, info)


## The Overdrive button's face: {"mode": OD_*, "text": String, "fill": 0..1 (cooldown or active
## progress), "enabled": bool}.
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
	if overdrive_prompt(game):
		return {
			"mode": OD_PROMPT,
			"text": strings.t("SIEGE_PROMPT_OVERDRIVE"),
			"fill": 1.0,
			"enabled": true,
		}
	var in_work := s.role == SiegeIds.ROLE_WAVE and phase_kind(game) == Wl.WORK
	return {
		"mode": OD_READY if in_work else OD_CLOSED,
		"text": strings.t("SIEGE_HUD_OVERDRIVE_READY"),
		"fill": 1.0,
		"enabled": in_work,
	}


## The wave's rush markers as fractions (0..1) of its length ([] without rushes).
static func rush_fractions(game: SiegeGame) -> Array[float]:
	var out: Array[float] = []
	var s := game.state if game != null else null
	if s == null or s.phase_index < 0 or s.phase_index >= game.metas.size():
		return out
	var d := phase_duration_s(game)
	if d <= 0.0:
		return out
	for t: Variant in game.metas[s.phase_index].get("rushes_at_s", []):
		out.append(clampf(float(t) / d, 0.0, 1.0))
	return out


## Every string key the HUD uses (the tests check each one exists).
const STRING_KEYS: Array[String] = [
	"SIEGE_HUD_GATE",
	"SIEGE_HUD_DENARII",
	"SIEGE_HUD_WAVE",
	"SIEGE_HUD_WARMUP_WAVE",
	"SIEGE_HUD_VICTORY",
	"SIEGE_HUD_ENEMY_COUNT",
	"SIEGE_HUD_QUEUED",
	"SIEGE_HUD_RAM_ON_ROAD",
	"SIEGE_HUD_RUSHES",
	"SIEGE_HUD_RUSH_ON",
	"SIEGE_HUD_BREACH",
	"SIEGE_HUD_ROUTE",
	"SIEGE_HUD_ROUTE_GEN",
	"SIEGE_HUD_ROUTE_PAD",
	"SIEGE_HUD_CONNECTING",
	"SIEGE_HUD_TARGET_GEN",
	"SIEGE_HUD_TARGET_PAD",
	"SIEGE_HUD_BTN_PREV",
	"SIEGE_HUD_BTN_NEXT",
	"SIEGE_HUD_BTN_GEN",
	"SIEGE_HUD_BTN_HOT",
	"SIEGE_HUD_MARK_OD",
	"SIEGE_HUD_MARK_RESCUE",
	"SIEGE_HUD_MARK_AFK",
	"SIEGE_HUD_OVERDRIVE",
	"SIEGE_HUD_OVERDRIVE_READY",
	"SIEGE_HUD_OVERDRIVE_ON",
	"SIEGE_HUD_OVERDRIVE_COOLDOWN",
	"SIEGE_PROMPT_OVERDRIVE",
	"SIEGE_WARN_HORN",
	"SIEGE_WARN_RAM",
	"SIEGE_WARN_GATE_LOW",
	"SIEGE_PHASE_BUILD_BREAK",
	"SIEGE_PHASE_BREAK_1",
	"SIEGE_ENEMY_RAIDERS",
	"SIEGE_ENEMY_SHIELD_WALL",
	"SIEGE_ENEMY_HORSEMEN",
	"SIEGE_ENEMY_RAM",
	"SIEGE_TOWER_BALLISTA",
	"SIEGE_TOWER_SCORPION",
	"SIEGE_TOWER_CALTROP",
	"SIEGE_SHOP_TITLE",
	"SIEGE_SHOP_COUNTDOWN",
	"SIEGE_SHOP_PICK_TAG",
	"SIEGE_SHOP_ITEM_COST",
	"SIEGE_SHOP_BUILD_BALLISTA",
	"SIEGE_SHOP_BUILD_SCORPION",
	"SIEGE_SHOP_BUILD_CALTROP",
	"SIEGE_SHOP_GEN_LEVEL",
	"SIEGE_SHOP_UPGRADE_ON_PAD",
	"SIEGE_ITEM_UPGRADE_1",
	"SIEGE_ITEM_UPGRADE_2",
	"SIEGE_ITEM_UPGRADE_3",
	"SIEGE_ITEM_GENERATOR_1",
	"SIEGE_ITEM_GENERATOR_2",
	"SIEGE_ITEM_GENERATOR_3",
	"SIEGE_ITEM_IRON_BANDS",
	"SIEGE_ITEM_REPAIR",
	"SIEGE_ITEM_RESERVE_FLYWHEEL",
	"SIEGE_ITEM_AQUEDUCT_DRIVE",
	"SIEGE_ITEM_SAVE",
]

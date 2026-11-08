class_name FishingHudModel
extends RefCounted
## What Turbo Reel's HUD shows, as plain functions of the game (tests check them without a HUD):
## each rider's shown action and its icon, the leaderboard rows, the time left, the local fish
## row and gaff meter, the menu chips' labels. Every key used here is in
## content/fishing/strings.csv (KEYS); a missing translation falls back to the key's English.

## Shown actions: FishingConst.A_* plus SPRINT (driving above 105 % FTP-equivalent).
const SPRINT := 100
const KEY_POINTS := "FISHING_HUD_POINTS"
const KEY_DISTANCE := "FISHING_HUD_DISTANCE"
const KEY_SPRINT := "FISHING_HUD_SPRINT"
const KEY_SPIN := "FISHING_HUD_SPIN"
const KEY_TROPHY := "FISHING_HUD_TROPHY"
const KEY_YOU := "FISHING_HUD_YOU"
const KEY_TIME_UP := "FISHING_HUD_TIME_UP"
const KEY_OVERTIME := "FISHING_HUD_OVERTIME"
const KEY_CAST := "FISHING_MENU_CAST"
const KEY_DRIVE_ON := "FISHING_MENU_DRIVE_ON"
const KEY_TURN := "FISHING_MENU_TURN"
const KEY_SPRINTING := "FISHING_ACTION_SPRINT"
const KEY_RPM := "FISHING_HUD_RPM"
const KEY_WATTS := "FISHING_HUD_WATTS"
const KEY_BPM := "FISHING_HUD_BPM"
const KEY_FTP := "FISHING_HUD_FTP"
const KEY_KNOTS := "FISHING_HUD_KNOTS"
const KEY_KMH := "FISHING_HUD_KMH"
const KEY_TARGET := "FISHING_HUD_TARGET"
const KEY_NOW := "FISHING_HUD_NOW"
const KEY_STRAIN := "FISHING_HUD_STRAIN"
const KEY_SLACK := "FISHING_HUD_SLACK"
const KEY_JIG := "FISHING_HUD_JIG"
const KEY_JIG_HOLD := "FISHING_HUD_JIG_HOLD"
const KEY_JIG_IN := "FISHING_HUD_JIG_IN"
const KEY_JIG_RECAST := "FISHING_HUD_JIG_RECAST"
const KEY_CREW_TARGET := "FISHING_HUD_CREW_TARGET"
const KEY_CREW_NOW := "FISHING_HUD_CREW_NOW"
## The most crew strips shown (one per other rider in a fight).
const CREW_MAX := 3
## Knots per m/s.
const KNOTS_PER_MPS := 1.943844
## FishingConst.ACTION_NAMES -> FISHING_ACTION_<NAME> (the leaderboard's action column).
const ACTION_PREFIX := "FISHING_ACTION_"
const KEYS: Array[String] = [
	KEY_POINTS,
	KEY_DISTANCE,
	KEY_SPRINT,
	KEY_SPIN,
	KEY_TROPHY,
	KEY_YOU,
	KEY_TIME_UP,
	KEY_OVERTIME,
	KEY_CAST,
	KEY_DRIVE_ON,
	KEY_TURN,
	KEY_SPRINTING,
	KEY_RPM,
	KEY_WATTS,
	KEY_BPM,
	KEY_FTP,
	KEY_KNOTS,
	KEY_KMH,
	KEY_TARGET,
	KEY_NOW,
	KEY_STRAIN,
	KEY_SLACK,
	KEY_JIG,
	KEY_JIG_HOLD,
	KEY_JIG_IN,
	KEY_JIG_RECAST,
	KEY_CREW_TARGET,
	KEY_CREW_NOW,
]
## English stand-ins when a key has no translation (headless tests without ctx.strings).
const FALLBACK := {
	KEY_POINTS: "{0} pts",
	KEY_DISTANCE: "{0} m",
	KEY_SPRINT: "Sprint!",
	KEY_SPIN: "Easy spin",
	KEY_TROPHY: "Trophy!",
	KEY_YOU: "YOU",
	KEY_TIME_UP: "Time is up",
	KEY_OVERTIME: "Overtime: land your fish",
	KEY_CAST: "Cast: {species}",
	KEY_DRIVE_ON: "Drive on",
	KEY_TURN: "Turn around",
	KEY_SPRINTING: "Sprinting",
	KEY_RPM: "rpm",
	KEY_WATTS: "W",
	KEY_BPM: "bpm",
	KEY_FTP: "{0}% FTP",
	KEY_KNOTS: "{0} kn",
	KEY_KMH: "{0} km/h",
	KEY_TARGET: "Target",
	KEY_NOW: "now",
	KEY_STRAIN: "strain",
	KEY_SLACK: "slack",
	KEY_JIG: "Jig it home",
	KEY_JIG_HOLD: "Hold",
	KEY_JIG_IN: "In: bites come sooner",
	KEY_JIG_RECAST: "Recasts at the boat",
	KEY_CREW_TARGET: "Target {0} W",
	KEY_CREW_NOW: "now {0} W",
}

static var _flat_cache: Vector3 = Vector3(-1, -1, 0)


static func strings_of(game: FishingGame) -> GameStrings:
	if game != null and game.ctx != null and game.ctx.strings != null:
		return game.ctx.strings
	return GameStrings.new()


## `key` translated with `args`, or its FALLBACK (with {0} / {name} filled) when untranslated.
static func tr_key(game: FishingGame, key: String, args: Variant = []) -> String:
	var tx := strings_of(game)
	if tx.has(key):
		return tx.t(key, args)
	var s := str(FALLBACK.get(key, key))
	if args is Array:
		for i in (args as Array).size():
			s = s.replace("{%d}" % i, str(args[i]))
	elif args is Dictionary:
		for k: String in args:
			s = s.replace("{%s}" % k, str(args[k]))
	return s


## The local rider (null without a state or a boat).
static func own_rider(game: FishingGame) -> FishingRiderState:
	if game == null or game.state == null or game.ctx == null:
		return null
	return game.state.rider_of_peer(game.ctx.local_peer)


## "m:ss" below an hour, else "h:mm:ss".
static func clock(seconds: float) -> String:
	return HudWidget.clock_text(seconds)


## The action a rider shows: AFK, paused, sprint (driving above 105 %), else its action.
static func shown_action(r: FishingRiderState) -> int:
	if r.afk or r.stale:
		return FishingConst.A_AFK
	if r.paused:
		return FishingConst.A_PAUSED
	var sprinting := r.p_eff_w > FishingConst.SPRINT_P_FRAC * FishingConst.P_EFF_REF_W
	if r.action == FishingConst.A_DRIVE and sprinting:
		return SPRINT
	return r.action


## The icon sprite of a shown action.
static func icon_of(action: int) -> String:
	match action:
		SPRINT:
			return "icon_sprint"
		FishingConst.A_MENU, FishingConst.A_CAST, FishingConst.A_WAIT:
			return "icon_wait"
		FishingConst.A_FIGHT:
			return "icon_fight"
		FishingConst.A_LAND:
			return "icon_landed"
		FishingConst.A_PAUSED:
			return "icon_paused"
		FishingConst.A_AFK:
			return "icon_afk"
	return "icon_drive"


## The action's word for the leaderboard.
static func action_text(game: FishingGame, action: int) -> String:
	if action == SPRINT:
		return tr_key(game, KEY_SPRINTING)
	var names: Array = FishingConst.ACTION_NAMES
	var key := ACTION_PREFIX + str(names[clampi(action, 0, names.size() - 1)]).to_upper()
	var tx := strings_of(game)
	return tx.t(key) if tx.has(key) else str(names[clampi(action, 0, names.size() - 1)])


## A rider's name (the slot's, else "P<n>").
static func name_of(game: FishingGame, slot: int) -> String:
	if game != null and game.ctx != null and slot >= 0 and slot < game.ctx.players.size():
		var n := game.ctx.players[slot].name
		if n != "":
			return n
	return "P%d" % (slot + 1)


## Leaderboard rows, most points first (ties: slot order): [{slot, name, points, action, local}].
static func board(game: FishingGame) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if game == null or game.state == null:
		return out
	var me := own_rider(game)
	for r in game.state.riders:
		(
			out
			. append(
				{
					"slot": r.slot,
					"name": name_of(game, r.slot),
					"points": r.points,
					"action": shown_action(r),
					"local": me != null and me.slot == r.slot,
				}
			)
		)
	out.sort_custom(_before)
	return out


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["points"]) != int(b["points"]):
		return int(a["points"]) > int(b["points"])
	return int(a["slot"]) < int(b["slot"])


## The clock line: time left, "Time is up" / overtime once play is over.
static func time_text(game: FishingGame) -> String:
	var st := game.state if game != null else null
	if st == null:
		return ""
	if st.time_up:
		for r in st.riders:
			if r.in_fight():
				return tr_key(game, KEY_OVERTIME)
		return tr_key(game, KEY_TIME_UP)
	return clock(st.time_left_s())


## The species' display name ("" for none).
static func species_name(game: FishingGame, sp: int) -> String:
	if sp < 0 or sp >= FishingConst.SPECIES.size():
		return ""
	var key := "FISHING_SPECIES_" + str(FishingConst.SPECIES[sp]).to_upper()
	var tx := strings_of(game)
	return tx.t(key) if tx.has(key) else str(FishingConst.SPECIES[sp]).capitalize()


## The fish row: {"visible", "sp", "name", "d_m" (line out), "reel" (0..1 of the line reeled
## in, FishingRiderState.reel), "stamina"} (with a fish on).
static func fish_row(game: FishingGame, r: FishingRiderState) -> Dictionary:
	var on := r != null and r.in_fight() and r.fish.sp >= 0 and not r.fish.off_line
	if not on:
		return {"visible": false, "sp": -1, "name": "", "d_m": 0, "reel": 0.0, "stamina": 0.0}
	return {
		"visible": true,
		"sp": r.fish.sp,
		"name": species_name(game, r.fish.sp),
		"d_m": roundi(r.line_m()),
		"reel": clampf(r.reel, 0.0, 1.0),
		"stamina": clampf(r.fish.s, 0.0, 1.0),
	}


## True while the fight panel stands in for the cruise box: a fish on the line in a fight (the
## Landing and a lost fish keep the cruise box, so raw W and %FTP always show).
static func fight_panel_up(game: FishingGame, r: FishingRiderState) -> bool:
	return r != null and r.action == FishingConst.A_FIGHT and bool(fish_row(game, r)["visible"])


## True while the jig panel is up: Free Roam, the lure out (the cast and the wait).
static func jig_up(game: FishingGame, r: FishingRiderState) -> bool:
	if r == null or game == null or game.state == null or not game.state.roam:
		return false
	return r.action == FishingConst.A_CAST or r.action == FishingConst.A_WAIT


## The cast's dx the lure is jigged home from: `prev` (0 when none) or the lure's distance now,
## whichever is more while the jig panel is up (a recast puts the lure back out at the same
## spot), 0 once it is not. Clients do not get the cast's dx, so the panel follows the lure.
static func jig_dx0(game: FishingGame, r: FishingRiderState, prev: float) -> float:
	if not jig_up(game, r):
		return 0.0
	return maxf(prev, absf(r.lure_dx))


## The jig panel's row for the local rider `r`: {"visible", "d_m" (line out to the lure), "fill"
## (0..1 of the way home from `dx0`), "hold_w" (JIG_FTP_FRAC of FTP, rounded up), "on" (in the
## lure band at `power` W, `cadence` rpm and the power at hold_w or more)}.
static func jig_row(
	game: FishingGame, r: FishingRiderState, dx0: float, power: float, cadence: float
) -> Dictionary:
	if not jig_up(game, r):
		return {"visible": false, "d_m": 0, "fill": 0.0, "hold_w": 0, "on": false}
	var hold := ceili(FishingConst.JIG_FTP_FRAC * r.ftp - 1e-6)
	var in_band := r.pub_hi > r.pub_lo and cadence >= r.pub_lo and cadence <= r.pub_hi
	return {
		"visible": true,
		"d_m": roundi(r.line_m()),
		"fill": clampf(1.0 - absf(r.lure_dx) / maxf(dx0, 1e-6), 0.0, 1.0) if dx0 > 0.0 else 0.0,
		"hold_w": hold,
		"on": in_band and roundi(power) >= hold,
	}


## The crew strips: one per other rider with a fish on in a fight, in the leaderboard's order, at
## most CREW_MAX: [{"slot", "name", "species", "d_m", "reel", "target_w", "now_w", "off"}] (off:
## the watts now are more than NOW_BAND off the target).
static func crew(game: FishingGame) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if game == null or game.state == null:
		return out
	var me := own_rider(game)
	for row in board(game):
		var r := game.state.rider(int(row["slot"]))
		if r == null or (me != null and r.slot == me.slot) or not fight_panel_up(game, r):
			continue
		var f := fish_row(game, r)
		out.append(
			{
				"slot": r.slot,
				"name": str(row["name"]),
				"species": str(f["name"]),
				"d_m": int(f["d_m"]),
				"reel": float(f["reel"]),
				"target_w": roundi(r.applied_target_w),
				"now_w": roundi(r.power_w),
				"off": FishingPanelRows.off_target(r.power_w, r.applied_target_w),
			}
		)
		if out.size() >= CREW_MAX:
			break
	return out


## The boat's speed in knots, one decimal ("18.4").
static func knots_text(v_mps: float) -> String:
	return "%.1f" % (absf(v_mps) * KNOTS_PER_MPS)


## The speed (km/h) `power_w` would ride on a flat road (SpeedModel at grade 0) for a rider of
## `rider_kg` with the model's bike mass; cached for the last whole watt.
static func flat_kmh(power_w: float, rider_kg: float) -> float:
	var w := roundf(maxf(power_w, 0.0))
	if w == _flat_cache.x and rider_kg == _flat_cache.y:
		return _flat_cache.z
	var mass := rider_kg + SpeedModel.DEFAULT_MASS_OFFSET_KG
	var kmh := SpeedModel.steady_state_speed(w, 0.0, mass) * 3.6 if w > 0.0 else 0.0
	_flat_cache = Vector3(w, rider_kg, kmh)
	return kmh


## The gaff meter during a Landing: {"visible", "fill", "phase" (KEY_SPRINT, KEY_SPIN or
## KEY_TROPHY)}.
static func gaff(r: FishingRiderState) -> Dictionary:
	if r == null or r.action != FishingConst.A_LAND:
		return {"visible": false, "fill": 0.0, "phase": ""}
	var phase := KEY_SPRINT if r.state_t < FishingConst.GAFF_S else KEY_SPIN
	if r.gaff >= 1.0:
		phase = KEY_TROPHY
	return {"visible": true, "fill": clampf(r.gaff, 0.0, 1.0), "phase": phase}


## The menu chips of the local rider in A_MENU: [{"entry", "text", "selected", "hint"}]: a cast
## entry names its species (hint = its index), drive on and turn around have hint -1.
static func chips(game: FishingGame, r: FishingRiderState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if r == null or r.action != FishingConst.A_MENU:
		return out
	for i in r.menu.size():
		var e := r.menu[i]
		var text := ""
		var hint := -1
		if e == FishingConst.M_DRIVE_ON:
			text = tr_key(game, KEY_DRIVE_ON)
		elif e == FishingConst.M_TURN:
			text = tr_key(game, KEY_TURN)
		elif e >= 0 and e < r.hint_count():
			hint = e
			var sp := int(r.hints[4 * e])
			text = tr_key(game, KEY_CAST, {"species": species_name(game, sp), "0": ""})
		else:
			continue
		out.append({"entry": e, "text": text, "selected": i == r.selected, "hint": hint})
	return out

class_name FishingHudModel
extends RefCounted
## What Fishing's HUD Controls show, as plain functions of the game (tests check them without a
## HUD): the local lane, the phase chip (label, time left or elapsed, next phase from the rider's
## own plan, else from the lane state), the fish row, the gaff meter, the catch board and each
## lane's status text. Every key used here is in content/fishing/strings.csv.

const STATUS_KEYS: Array[String] = [
	"FISHING_STATUS_RIDE_OUT",
	"FISHING_STATUS_PICK",
	"FISHING_STATUS_CAST",
	"FISHING_STATUS_REEL",
	"FISHING_STATUS_STRIKE",
	"FISHING_STATUS_FIGHT",
	"FISHING_STATUS_LANDING",
	"FISHING_STATUS_IDLE",
	"FISHING_STATUS_HOME",
]
const SPECIES_KEYS: Array[String] = [
	"FISHING_SPECIES_MACKEREL",
	"FISHING_SPECIES_MAHI",
	"FISHING_SPECIES_TUNA",
	"FISHING_SPECIES_MARLIN"
]
const KEY_RESCUE := "FISHING_STATUS_RESCUE"
const KEY_AFK := "FISHING_STATUS_AFK"
const KEY_COOLDOWN := "FISHING_HUD_COOLDOWN"
const KEY_LEFT := "FISHING_HUD_LEFT"
const KEY_NEXT := "FISHING_HUD_NEXT"
const KEY_DISTANCE := "FISHING_HUD_DISTANCE"
const KEY_GAFF := "FISHING_HUD_GAFF"
const KEY_SPRINT := "FISHING_HUD_SPRINT"
const KEY_SPIN := "FISHING_HUD_SPIN"
const KEY_TROPHY := "FISHING_HUD_TROPHY"
const KEY_POINTS := "FISHING_HUD_POINTS"
const KEY_FISH := "FISHING_HUD_FISH"
const KEY_HOOKUP := "FISHING_HUD_HOOKUP"
const KEY_ENDS_IN := "FISHING_HUD_FISHING_LEFT"
const KEY_STRAIN := "FISHING_HUD_STRAIN"
const KEY_SLACK := "FISHING_HUD_SLACK"
const KEY_RPM := "FISHING_HUD_RPM"
const KEY_WATTS := "FISHING_HUD_WATTS"
const KEY_PICK := "FISHING_HUD_PICK"
const KEY_YOU := "FISHING_HUD_YOU"
const KEY_FISH_ON := "FISHING_HUD_FISH_ON"
## Every key the HUD uses (the HUD test checks each is in strings.csv).
const KEYS: Array[String] = [
	KEY_RESCUE,
	KEY_AFK,
	KEY_COOLDOWN,
	KEY_LEFT,
	KEY_NEXT,
	KEY_DISTANCE,
	KEY_GAFF,
	KEY_SPRINT,
	KEY_SPIN,
	KEY_TROPHY,
	KEY_POINTS,
	KEY_FISH,
	KEY_HOOKUP,
	KEY_ENDS_IN,
	KEY_STRAIN,
	KEY_SLACK,
	KEY_RPM,
	KEY_WATTS,
	KEY_PICK,
	KEY_YOU,
	KEY_FISH_ON,
]
## Brief 3.5: W and rpm >= 48 px in the local lane (kit widgets), >= 32 px in a FishingLaneHud.
const LANE_NUMBER_PX := 34


static func strings_of(game: FishingGame) -> GameStrings:
	if game != null and game.ctx != null and game.ctx.strings != null:
		return game.ctx.strings
	return GameStrings.new()


## The local rider's lane (null without a state or a lane).
static func local_lane(game: FishingGame) -> FishingLaneState:
	if game == null or game.state == null or game.ctx == null:
		return null
	return game.state.lane_of_peer(game.ctx.local_peer)


## The local rider's slot (0 when unknown).
static func local_slot(game: FishingGame) -> int:
	var p := game.ctx.local_player() if game != null and game.ctx != null else null
	return p.slot_index if p != null else 0


## "m:ss" below an hour, else "h:mm:ss".
static func clock(seconds: float) -> String:
	var s := maxi(floori(seconds), 0)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


## The local rider's plan (the same pre-roll every peer has), null when it can't be built.
static func local_plan(game: FishingGame) -> EffortPlan:
	if game == null or game.content == null or not game.content.ok or game.ctx == null:
		return null
	var slot := local_slot(game)
	if slot < 0 or slot >= game.slots.size():
		return null
	var p := game.ctx.local_player()
	var reel := int(p.options.get("reel_pct", FishingConst.REEL_PCT_DEFAULT)) if p != null else 60
	var typed: Array[FishingPlanSlot] = []
	for s: Variant in game.slots[slot]:
		if s is FishingPlanSlot:
			typed.append(s)
	return FishingPlanBuilder.build(game.content.trip, typed, reel)


## The phase chip: {"label", "left_s" (-1 open-ended), "elapsed_s", "next"} for lane `l` whose
## phase started at game time `start_t`; `plan` may be null (labels then come from the state).
static func phase_chip(
	game: FishingGame, l: FishingLaneState, plan: EffortPlan, start_t: float
) -> Dictionary:
	var tx := strings_of(game)
	var out := {"label": "", "left_s": -1.0, "elapsed_s": 0.0, "next": ""}
	if l == null:
		return out
	var t := game.state.t if game.state != null else 0.0
	out["elapsed_s"] = maxf(t - start_t, 0.0)
	var idx := l.phase_index
	if plan != null and idx >= 0 and idx < plan.size() and l.state != FishingConst.ST_HOME:
		var ph := plan.phase(idx)
		out["label"] = tx.t(ph.label)
		if not ph.open_ended:
			out["left_s"] = maxf(ph.duration_s - float(out["elapsed_s"]), 0.0)
		out["next"] = (
			tx.t(plan.phase(idx + 1).label) if idx + 1 < plan.size() else tx.t(KEY_COOLDOWN)
		)
		return out
	out["label"] = status_text(game, l)
	out["next"] = tx.t(_next_key(l.state))
	return out


static func _next_key(st: int) -> String:
	match st:
		FishingConst.ST_RIDE_OUT, FishingConst.ST_LANDING:
			return STATUS_KEYS[FishingConst.ST_REEL]
		FishingConst.ST_PICK, FishingConst.ST_CAST, FishingConst.ST_REEL, FishingConst.ST_STRIKE:
			return STATUS_KEYS[FishingConst.ST_FIGHT]
		FishingConst.ST_FIGHT:
			return STATUS_KEYS[FishingConst.ST_LANDING]
	return KEY_COOLDOWN


## The species' display name ("" for none).
static func species_name(game: FishingGame, sp: int) -> String:
	if sp < 0 or sp >= SPECIES_KEYS.size():
		return ""
	return strings_of(game).t(SPECIES_KEYS[sp])


## The fish row: {"visible", "sp", "name", "d_m", "stamina"} (visible only with a fish on).
static func fish_row(game: FishingGame, l: FishingLaneState) -> Dictionary:
	var on := (
		l != null
		and l.fish.sp >= 0
		and not l.fish.off_line
		and l.state in [FishingConst.ST_STRIKE, FishingConst.ST_FIGHT, FishingConst.ST_LANDING]
	)
	if not on:
		return {"visible": false, "sp": -1, "name": "", "d_m": 0, "stamina": 0.0}
	return {
		"visible": true,
		"sp": l.fish.sp,
		"name": species_name(game, l.fish.sp),
		"d_m": roundi(l.fish.d),
		"stamina": clampf(l.fish.s, 0.0, 1.0),
	}


## The gaff meter during a Landing: {"visible", "fill", "phase" (KEY_SPRINT, KEY_SPIN or
## KEY_TROPHY)}.
static func gaff(l: FishingLaneState) -> Dictionary:
	if l == null or l.state != FishingConst.ST_LANDING:
		return {"visible": false, "fill": 0.0, "phase": ""}
	var phase := KEY_SPRINT if l.state_t < FishingConst.GAFF_S else KEY_SPIN
	if l.gaff >= 1.0:
		phase = KEY_TROPHY
	return {"visible": true, "fill": clampf(l.gaff, 0.0, 1.0), "phase": phase}


## The catch board, newest last: [[lane, species, grade], ...] (at most 5).
static func board(state: FishingState) -> Array:
	var out: Array = []
	if state == null:
		return out
	for i in state.catches.size() / 3:
		out.append([state.catches[3 * i], state.catches[3 * i + 1], state.catches[3 * i + 2]])
	while out.size() > FishingConst.CATCH_BOARD:
		out.pop_front()
	return out


## "x1.5" for the hookup level's multiplier (level = fights on now).
static func hookup_text(level: int) -> String:
	var m := FishingConst.hookup_mult(level)
	return "x%s" % (str(int(m)) if is_equal_approx(m, roundf(m)) else "%.1f" % m)


## A lane's one-line status: rescue, AFK, else its lane state (fight: the species).
static func status_text(game: FishingGame, l: FishingLaneState) -> String:
	var tx := strings_of(game)
	if l == null:
		return ""
	if l.rescue:
		return tx.t(KEY_RESCUE)
	if l.afk or l.stale:
		return tx.t(KEY_AFK)
	var st := clampi(l.state, 0, STATUS_KEYS.size() - 1)
	if st == FishingConst.ST_FIGHT and l.fish.sp < 0:
		return tx.t(KEY_FISH_ON)
	return tx.t(STATUS_KEYS[st], {"species": species_name(game, l.fish.sp)})


## The slot look of `slot` from ctx.players (Wl.slot_look without one).
static func look(game: FishingGame, slot: int) -> Dictionary:
	if game != null and game.ctx != null and slot >= 0 and slot < game.ctx.players.size():
		var p := game.ctx.players[slot]
		return {"color": p.color, "shape": p.shape, "pattern": p.pattern, "hollow": p.hollow}
	return Wl.slot_look(slot)


## The band marker position 0..1 of `rpm` on a FishingLaneHud's band scale (50-130 rpm).
static func rpm_frac(rpm: float) -> float:
	return clampf((rpm - 50.0) / 80.0, 0.0, 1.0)

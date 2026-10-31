class_name TankCues
extends RefCounted
## The local rider's own prompts, toasts and banners (brief 2.6, GAME_SDK 10.2). Owner: module.
##
## ctx.hud.toast and banner take a peer: `ctx.local_peer` on the host draws on the host only and
## sends nothing, and a client's call is always local. So every peer runs this same code for its
## own rider and passes ctx.local_peer, and no peer ever raises a prompt for another one:
##   - the host calls on_event() with the events it just sent and on_state() after each step;
##   - a client calls on_event() from apply_event() and on_state() from apply_snapshot().
## Prompts follow the replicated state (a running telegraph and the rider's own can-evade flag, the
## steam window), raised once when they come up; sprint prompts only show to a rider who can sprint
## for them: "Surge to evade" in a SIM WORK phase past the first 300 s (TankRiderState.can_evade,
## never in WARMUP, RECOVERY or ERG phases: brief 2.3, 2.4), "Surge to overpressure" in the steam
## window. The arc generator's stall is announced to the whole crew, like the dynamo's.
## v3: "Seat: <seat>" to the rider who just moved seats.
## Free roam (brief 2.10, 3.6): "Turn around" to the Drive rider when the tank
## stands at a turning place, "Engage" to everyone when it halts for a strongpoint or a heavy tank,
## "Turning round" on a turn and "Time up" when the roam phase's min_s passed.
## v4: to the whole crew, "Stage restarts" after a tow, "Ambush: Secondaries" when a near threat bursts
## from the bushes, "It got away" when one flees (the HUD's plate shows TANK LOST itself).

const PROMPT_NONE := ""
const PROMPT_EVADE := "evade"
const PROMPT_OVER := "over"
const PROMPT_KEYS := {
	PROMPT_EVADE: "TANK_PROMPT_EVADE",
	PROMPT_OVER: "TANK_PROMPT_OVER",
}
## Shell type -> the "loaded" toast.
const LOADED_KEYS := {
	TankIds.SHELL_LIGHT: "TANK_TOAST_LOADED_LIGHT",
	TankIds.SHELL_HEAVY: "TANK_TOAST_LOADED_HEAVY",
	TankIds.SHELL_OVER: "TANK_TOAST_OVERPRESSURE",
}
const BANNER_S := 3.0

var ctx: GameContext = null

var _prompt: String = PROMPT_NONE
var _stalled: bool = false
var _arc_stalled: bool = false
var _rescue: bool = false
var _regroup: bool = false
var _all_afk: bool = false
var _at_end: int = 0
var _engaging: bool = false
## peer -> was on reserve at the last call; empty until the first call, which only records.
var _reserve: Dictionary = {}


func _init(p_ctx: GameContext) -> void:
	ctx = p_ctx


## The prompt the local rider shows now (PROMPT_*): "Surge to evade" while a telegraphed shot is
## coming and this rider can evade (any engine in a SIM WORK phase), else "Surge to overpressure"
## in the steam window.
static func prompt_of(state: TankState, rider: TankRiderState) -> String:
	if state == null or rider == null or state.seg.kind != Wl.WORK:
		return PROMPT_NONE
	if rider.afk or rider.rescue or state.all_afk:
		return PROMPT_NONE
	if rider.can_evade and telegraph_running(state):
		return PROMPT_EVADE
	var st := state.station_of(rider.slot)
	if st is TankSteamState:
		return PROMPT_OVER if (st as TankSteamState).window_s > 0.0 else PROMPT_NONE
	return PROMPT_NONE


## True while some enemy or the Behemoth shows a telegraph (from the replicated telegraph times), or
## v4: an evadable shell is still in the air (a surge can make it miss until it lands).
static func telegraph_running(state: TankState) -> bool:
	if state.boss.telegraph_s > 0.0:
		return true
	for e in state.enemies:
		if e.telegraph_s > 0.0:
			return true
	for s in state.shells:
		if s.evadable and s.left_s > 0.0:
			return true
	return false


## True while the arc generator is stalled: its room says so, or its rider is in a rescue hold.
static func arc_stalled(state: TankState) -> bool:
	var st := state.station(TankIds.ENGINE_ARC)
	if st == null:
		return false
	if (st as TankArcState).stalled:
		return true
	var holder := state.rider_at(st.slot)
	return holder != null and holder.rescue


## True while the dynamo is stalled: its station says so, or its rider is in a rescue hold.
static func dynamo_stalled(state: TankState) -> bool:
	var st := state.station(TankIds.ENGINE_DYNAMO)
	if st == null:
		return false
	if (st as TankDynamoState).stalled:
		return true
	var holder := state.rider_at(st.slot)
	return holder != null and holder.rescue


## State-driven cues for the local rider, after a host step or an applied snapshot.
func on_state(state: TankState) -> void:
	var me := state.rider(ctx.local_peer) if state != null else null
	if me == null:
		return
	var prompt := prompt_of(state, me)
	if prompt != _prompt and prompt != PROMPT_NONE:
		_toast(str(PROMPT_KEYS[prompt]))
	_prompt = prompt
	var stalled := dynamo_stalled(state)
	if stalled and not _stalled:
		_toast("TANK_TOAST_DYNAMO_STALLED")
	_stalled = stalled
	var arc := arc_stalled(state)
	if arc and not _arc_stalled:
		_toast("TANK_TOAST_ARC_STALLED")
	_arc_stalled = arc
	var own_stall := me.engine == TankIds.ENGINE_DYNAMO or me.engine == TankIds.ENGINE_ARC
	if me.rescue and not _rescue and not own_stall:
		_toast("TANK_TOAST_STAGGER")
	_rescue = me.rescue
	var regroup := state.seg.regroup and state.seg.kind == Wl.WORK
	if regroup and not _regroup:
		_toast("TANK_TOAST_REGROUP")
	_regroup = regroup
	_reserve_cues(state)
	_roam_cues(state, me)


## Free roam: "Turn around" for the driver at a map end (once per arrival, not while turning),
## "Engage" for everyone when the tank halts to fight.
func _roam_cues(state: TankState, me: TankRiderState) -> void:
	var r := state.roam
	if not r.active:
		return
	var drives := me.engine == TankIds.ENGINE_DIESEL
	var end := r.at_end if r.turn_s <= 0.0 else 0
	if end != 0 and end != _at_end and drives and not state.in_cooldown():
		_toast("TANK_TOAST_TURN_AROUND")
	_at_end = end
	if r.engaging and not _engaging:
		_toast("TANK_TOAST_ENGAGE")
	_engaging = r.engaging


## "<name> on reserve" when a rider goes AFK or drops, and "No power" when every rider has. The
## first call only records who is on reserve (a rejoining client's first snapshot, for one).
func _reserve_cues(state: TankState) -> void:
	var primed := not _reserve.is_empty()
	for r in state.riders:
		var away := r.afk or not r.connected
		if primed and away and not bool(_reserve.get(r.peer, false)):
			var slot := ctx.player(r.peer)
			_toast("TANK_TOAST_RESERVE", [slot.name if slot != null else str(r.peer)])
		_reserve[r.peer] = away
	if primed and state.all_afk and not _all_afk:
		_toast("TANK_TOAST_ALL_AFK")
	_all_afk = state.all_afk


## The cues of one event (ints cast), for the local rider.
func on_event(state: TankState, e: Dictionary) -> void:
	var me := state.rider(ctx.local_peer) if state != null else null
	var slot := me.slot if me != null else -1
	match str(e.get("type", "")):
		TankEvents.SEGMENT:
			_segment_banner(state, int(e.get("i", -1)))
		TankEvents.SEAT:
			if int(e.get("s", -2)) == slot:
				_seat_toast(int(e.get("to", 0)))
		TankEvents.BREAKDOWN:
			_toast("TANK_TOAST_BREAKDOWN")
		TankEvents.REPAIRED:
			_toast("TANK_TOAST_REPAIRED", [int(e.get("hp", 0))])
		TankEvents.OVERRUN:
			_overrun_toast(int(e.get("sg", 0)))
		TankEvents.EVADE:
			if int(e.get("ok", 0)) != 0:
				_toast("TANK_TOAST_EVADED")
		TankEvents.LATCH:
			if int(e.get("s", -2)) == slot and LOADED_KEYS.has(int(e.get("sh", 0))):
				_toast(str(LOADED_KEYS[int(e.get("sh", 0))]))
		TankEvents.BOSS_PHASE:
			_boss_banner(int(e.get("p", 0)))
		TankEvents.TURN:
			_toast("TANK_TOAST_TURNING")
		TankEvents.TIME_UP:
			_toast("TANK_TOAST_TIME_UP")
		TankEvents.STAGE_RESTART:
			_toast("TANK_TOAST_RESTART")
		TankEvents.AMBUSH:
			_toast("TANK_TOAST_AMBUSH")
		TankEvents.ESCAPED:
			_toast("TANK_TOAST_ESCAPED")


func _segment_banner(state: TankState, index: int) -> void:
	if state == null or state.content == null:
		return
	var label := str(state.content.segment(index).get("label", ""))
	if label != "":
		ctx.hud.banner("TANK_BANNER_SEGMENT", [ctx.strings.t(label)], BANNER_S, ctx.local_peer)


## v3: the local rider arrived on a seat (engine code `code`).
func _seat_toast(code: int) -> void:
	var engine := TankIds.engine_of(code)
	_toast("TANK_TOAST_SEAT", [ctx.strings.t(str(TankIds.SEAT_LABELS.get(engine, "")))])


func _overrun_toast(seg_code: int) -> void:
	match TankIds.seg_of(seg_code):
		TankIds.SEG_ADVANCE:
			_toast("TANK_TOAST_OVERRUN_ADVANCE")
		TankIds.SEG_GUN_LINE:
			_toast("TANK_TOAST_OVERRUN_GUN_LINE")
		TankIds.SEG_BOSS:
			_toast("TANK_TOAST_BEHEMOTH_WITHDRAWS")


func _boss_banner(phase: int) -> void:
	var key := ""
	match phase:
		TankIds.BOSS_PHASE_1:
			key = "TANK_BANNER_BOSS"
		TankIds.BOSS_PHASE_2:
			key = "TANK_BANNER_BOSS_PHASE2"
		TankIds.BOSS_DEAD:
			key = "TANK_BANNER_VICTORY"
		TankIds.BOSS_WITHDRAWN:
			key = "TANK_BANNER_WITHDRAWN"
	if key != "":
		ctx.hud.banner(key, [], BANNER_S, ctx.local_peer)


func _toast(key: String, args: Array = []) -> void:
	ctx.hud.toast(key, args, ctx.local_peer)

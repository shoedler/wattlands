class_name TankCues
extends RefCounted
## The local rider's own prompts, toasts and banners (brief 2.6, GAME_SDK 10.2). Owner: module.
##
## ctx.hud.toast and banner take a peer: `ctx.local_peer` on the host draws on the host only and
## sends nothing, and a client's call is always local. So every peer runs this same code for its
## own rider and passes ctx.local_peer, and no peer ever raises a prompt for another one:
##   - the host calls on_event() with the events it just sent and on_state() after each step;
##   - a client calls on_event() from apply_event() and on_state() from apply_snapshot().
## Prompts follow the replicated state (the station's prompt flag, the steam window), raised once
## when they come up; sprint prompts only show in WORK phases (never in WARMUP, RECOVERY or ERG
## gun lines, which carry no prompt flag: brief 2.3).

const PROMPT_NONE := ""
const PROMPT_RAM := "ram"
const PROMPT_DODGE := "dodge"
const PROMPT_OVER := "over"
const PROMPT_KEYS := {
	PROMPT_RAM: "TANK_PROMPT_RAM",
	PROMPT_DODGE: "TANK_PROMPT_DODGE",
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
var _rescue: bool = false
var _regroup: bool = false


func _init(p_ctx: GameContext) -> void:
	ctx = p_ctx


## The prompt the local rider's station shows now (PROMPT_*): "Surge to ram" on the diesel or
## the Bulwark, "Surge to dodge" at the boss, "Surge to overpressure" in the steam window.
static func prompt_of(state: TankState, rider: TankRiderState) -> String:
	if state == null or rider == null or state.seg.kind != Wl.WORK:
		return PROMPT_NONE
	if rider.afk or rider.rescue or state.all_afk:
		return PROMPT_NONE
	var st := state.station_of(rider.slot)
	if st is TankSteamState:
		return PROMPT_OVER if (st as TankSteamState).window_s > 0.0 else PROMPT_NONE
	if st is TankDieselState and (st as TankDieselState).prompt:
		return PROMPT_DODGE if state.seg.seg == TankIds.SEG_BOSS else PROMPT_RAM
	return PROMPT_NONE


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
	if me.rescue and not _rescue and me.engine != TankIds.ENGINE_DYNAMO:
		_toast("TANK_TOAST_STAGGER")
	_rescue = me.rescue
	var regroup := state.seg.regroup and state.seg.kind == Wl.WORK
	if regroup and not _regroup:
		_toast("TANK_TOAST_REGROUP")
	_regroup = regroup


## The cues of one event (ints cast), for the local rider.
func on_event(state: TankState, e: Dictionary) -> void:
	var me := state.rider(ctx.local_peer) if state != null else null
	var slot := me.slot if me != null else -1
	match str(e.get("type", "")):
		TankEvents.SEGMENT:
			_segment_banner(state, int(e.get("i", -1)))
		TankEvents.ROTATION:
			_rotation_toast(slot, e)
		TankEvents.BREAKDOWN:
			_toast("TANK_TOAST_BREAKDOWN")
		TankEvents.REPAIRED:
			_toast("TANK_TOAST_REPAIRED", [int(e.get("hp", 0))])
		TankEvents.OVERRUN:
			_overrun_toast(int(e.get("sg", 0)))
		TankEvents.RAM:
			if int(e.get("s", -2)) == slot:
				_toast("TANK_TOAST_RAM_HIT" if int(e.get("ok", 0)) != 0 else "TANK_TOAST_RAM_MISS")
		TankEvents.DODGE:
			if int(e.get("s", -2)) == slot:
				_toast("TANK_TOAST_DODGED")
		TankEvents.LATCH:
			if int(e.get("s", -2)) == slot and LOADED_KEYS.has(int(e.get("sh", 0))):
				_toast(str(LOADED_KEYS[int(e.get("sh", 0))]))
		TankEvents.BOSS_PHASE:
			_boss_banner(int(e.get("p", 0)))


func _segment_banner(state: TankState, index: int) -> void:
	if state == null or state.content == null:
		return
	var label := str(state.content.segment(index).get("label", ""))
	if label != "":
		ctx.hud.banner("TANK_BANNER_SEGMENT", [ctx.strings.t(label)], BANNER_S, ctx.local_peer)


func _rotation_toast(slot: int, e: Dictionary) -> void:
	for pair: Variant in e.get("r", []):
		if pair is Array and (pair as Array).size() == 2 and int(pair[0]) == slot:
			var engine := TankIds.engine_of(int(pair[1]))
			_toast(
				"TANK_TOAST_ROTATION", [ctx.strings.t(str(TankIds.ENGINE_LABELS.get(engine, "")))]
			)


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

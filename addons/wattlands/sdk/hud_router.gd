class_name HudRouter
extends HudFeed
## `ctx.hud` with network routing (BRIEF 3.6, 3.9; docs/OWNERSHIP.md HUD7-HUD9, C1, C27).
## "Drawing locally" means emitting this peer's WlEventBus HUD signals (power_band_changed,
## roster_changed, toast_requested, banner_requested, readout_changed), which the HudLayer
## reads.
##
## HOST and SOLO (the authority):
##   power_band(peer, lo, hi): a rider simulated here (the host's own rider or a bot) gets
##     LocalRider.set_power_band (its gauge and MockTrainer); a remote rider gets a
##     `directive` {kind: power_band, lo_w, hi_w}; the host's bus emits power_band_changed
##     for every rider. (0, 0) clears. The GameHost clears a rider's band at its cool-down.
##   teammate_status(peer, status): stored and sent to every peer in the 2 Hz roster.
##   toast/banner(..., peer): Wl.ALL_PEERS draws here and sends a `hud` message to every
##     client; peer == the local rider draws here only (nothing is sent); another human peer
##     gets a `hud` message only; a bot has no HUD (dropped).
## CLIENT: everything draws locally only. power_band for the client's own rider also feeds
##   its LocalRider (gauge and MockTrainer) and sends nothing (C27).
## readout(id, text) is always local.

## The HUD's view of a teammate status changed locally (clients overlay it on the roster).
signal local_status_changed(peer: int, status: Dictionary)

var role: String = Wl.SOLO
var local_peer: int = 0
## Riders simulated on this peer: peer -> LocalRider. Private (W3 SAF-4): `ctx.hud` is
## this object, so a public map would hand a game every LocalRider (set_plan, start_phase,
## resume, the governor) past the DirectiveSink's checks. The GameHost sets it with
## bind_riders(); nothing reads it from outside.
var _riders: Dictionary = {}
## Every rider in the session: peer -> PlayerSlot.
var slots: Dictionary = {}
var bus: WlEventBus = null
var report: ReportCollector = null
## (peer: int, message: Dictionary) -> void: sends a game message to one peer, or to every
## client when peer is Wl.ALL_PEERS. Unset in SOLO.
var send: Callable = Callable()
## () -> Array [game_t, platform_t] for report events.
var clock_now: Callable = Callable()
## peer -> [lo_w, hi_w] (the latest published power band; cleared bands are erased).
var power_bands: Dictionary = {}
## peer -> {in_band, icon, text}
var statuses: Dictionary = {}


func is_authority() -> bool:
	return role == Wl.SOLO or role == Wl.HOST


## The riders simulated on this peer (peer -> LocalRider); the GameHost calls this once at
## setup. There is deliberately no getter.
func bind_riders(p_riders: Dictionary) -> void:
	_riders = p_riders


func power_band(peer: int, lo_w: float, hi_w: float) -> void:
	if is_nan(lo_w) or is_nan(hi_w) or is_inf(lo_w) or is_inf(hi_w) or lo_w < 0.0 or hi_w < lo_w:
		push_warning(
			"HudRouter: power_band(%d, %s, %s) ignored: needs 0 <= lo <= hi" % [peer, lo_w, hi_w]
		)
		return
	if lo_w == 0.0 and hi_w == 0.0:
		power_bands.erase(peer)
	else:
		power_bands[peer] = [lo_w, hi_w]
	if is_authority():
		if _riders.has(peer):
			(_riders[peer] as LocalRider).set_power_band(lo_w, hi_w)
		elif slots.has(peer):
			_send(
				peer,
				Protocol.game_msg(
					"directive",
					{
						"kind": NetMessages.DIRECTIVE_POWER_BAND,
						"peer": peer,
						"lo_w": lo_w,
						"hi_w": hi_w
					}
				)
			)
		else:
			push_warning("HudRouter: power_band for unknown peer %d" % peer)
			return
		_record("power_band", {"peer": peer, "lo_w": lo_w, "hi_w": hi_w})
	elif peer == local_peer and _riders.has(peer):
		(_riders[peer] as LocalRider).set_power_band(lo_w, hi_w)
	if bus != null:
		bus.power_band_changed.emit(peer, lo_w, hi_w)


func teammate_status(peer: int, status: Dictionary) -> void:
	var s := {
		"in_band": bool(status.get("in_band", false)),
		"icon": str(status.get("icon", "")),
		"text": str(status.get("text", "")),
	}
	statuses[peer] = s
	if not is_authority():
		local_status_changed.emit(peer, s)


func toast(key: String, args: Variant = [], peer: int = 0) -> void:
	_message("toast", key, args, 0.0, peer)


func banner(key: String, args: Variant = [], seconds: float = 3.0, peer: int = 0) -> void:
	_message("banner", key, args, seconds, peer)


func readout(id: String, text: String) -> void:
	if bus != null:
		bus.readout_changed.emit(id, text)


## The rider entered its cool-down: its power band is cleared everywhere it applies.
func clear_power_band(peer: int) -> void:
	if not power_bands.has(peer):
		return
	power_bands.erase(peer)
	if _riders.has(peer):
		(_riders[peer] as LocalRider).set_power_band(0.0, 0.0)
	if bus != null:
		bus.power_band_changed.emit(peer, 0.0, 0.0)


## The published band for `peer` ([0, 0] when none).
func band_of(peer: int) -> Array:
	return power_bands.get(peer, [0.0, 0.0])


## Draw a `hud` message that arrived from the host.
func draw_remote(kind: String, key: String, args: Variant, seconds: float) -> void:
	_draw(kind, key, args, seconds)


func _message(kind: String, key: String, args: Variant, seconds: float, peer: int) -> void:
	var safe_args: Variant = args if (args is Array or args is Dictionary) else [args]
	if not is_authority():
		_draw(kind, key, safe_args, seconds)
		return
	_record(kind, {"key": key, "peer": peer})
	if peer == Wl.ALL_PEERS:
		_draw(kind, key, safe_args, seconds)
		_send(Wl.ALL_PEERS, _hud_msg(kind, key, safe_args, seconds))
	elif peer == local_peer:
		_draw(kind, key, safe_args, seconds)
	elif _riders.has(peer):
		pass
	elif slots.has(peer):
		_send(peer, _hud_msg(kind, key, safe_args, seconds))
	else:
		push_warning("HudRouter: %s for unknown peer %d dropped" % [kind, peer])


func _hud_msg(kind: String, key: String, args: Variant, seconds: float) -> Dictionary:
	return Protocol.game_msg("hud", {"kind": kind, "key": key, "args": args, "seconds": seconds})


func _draw(kind: String, key: String, args: Variant, seconds: float) -> void:
	if bus == null:
		return
	if kind == "banner":
		bus.banner_requested.emit(key, args, seconds)
	else:
		bus.toast_requested.emit(key, args)


func _send(peer: int, msg: Dictionary) -> void:
	if send.is_valid():
		send.call(peer, msg)


func _record(kind: String, fields: Dictionary) -> void:
	if report == null:
		return
	var now: Array = clock_now.call() if clock_now.is_valid() else [0.0, 0.0]
	var f := fields.duplicate()
	f["kind"] = kind
	report.event(float(now[0]), float(now[1]), "hud", f)

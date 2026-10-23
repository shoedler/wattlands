class_name TankSyntheticRiders
extends RefCounted
## Synthetic compliant riders for the rules-level balance harness and the S8 stress test: the
## same model as the MockTrainer's `erg` profile (docs/GAME_SDK.md 20), without a trainer stack.
##
## - ERG phases (and the cool-down): the rider follows `compliance` x the applied target. The
##   applied target is what the governor would apply: the plan's value at that moment (ramps
##   included), replaced by the latest ERG `request` target of the phase, x 0.85 for an unverified
##   FTP, never below the floor max(30% FTP, 50 W), rising at most 30 W/s, falling at once; on a
##   SIM -> ERG switch it starts at min(the rider's power, the target). Power settles with a 2 s
##   first-order lag.
## - SIM phases: the rider rides `compliance` x the centre of the power band the game published
##   with ctx.hud.power_band, else exactly 90% FTP (the steam engine's rule), 1 s lag.
## - Cadence 90 rpm; P_eff is power x the slot's p_eff_per_w. No rescue, no AFK, always connected.
##
## It reads what the game sent through TankFakes' recording sinks (requests and power bands) and
## builds one InputFrame per tick from TankFakes.PhaseClock phases.

const SLEW_W_PER_S := 30.0
const ERG_TAU_S := 2.0
const SIM_TAU_S := 1.0
const CADENCE_RPM := 90.0
const UNVERIFIED := 0.85

var ctx: GameContext = null
var clock: TankFakes.PhaseClock = null
var dirs: TankFakes.Directives = null
var hud: TankFakes.Hud = null
var compliance: float = 1.0

## peer -> {power, applied_w, mode, phase, directed_pct, band_lo, band_hi, grades}
var _st: Dictionary = {}
var _req_seen: int = 0
var _band_seen: int = 0


func _init(p_ctx: GameContext, p_clock: TankFakes.PhaseClock, p_compliance: float) -> void:
	ctx = p_ctx
	clock = p_clock
	dirs = p_ctx.directives as TankFakes.Directives
	hud = p_ctx.hud as TankFakes.Hud
	compliance = p_compliance
	for p in ctx.players:
		_st[p.peer_id] = {
			"power": 0.0,
			"applied_w": 0.0,
			"mode": Wl.ERG,
			"phase": -1,
			"directed_pct": -1.0,
			"band_lo": 0.0,
			"band_hi": 0.0,
			"grades": {},
		}


## The latest mode_grade the game requested for `peer` with `reason` (0 before the first).
func last_grade(peer: int, reason: String) -> float:
	return float((_st[peer]["grades"] as Dictionary).get(reason, 0.0))


## The rider's applied ERG target as % FTP (0 in SIM), after the unverified factor and the slew.
func applied_pct(peer: int) -> float:
	var slot := ctx.player(peer)
	var s: Dictionary = _st[peer]
	if slot == null or s["mode"] != Wl.ERG or slot.ftp <= 0.0:
		return 0.0
	return float(s["applied_w"]) / slot.ftp * 100.0


func power_w(peer: int) -> float:
	return float(_st[peer]["power"] as float)


## The InputFrame of game tick `tick`; call clock.advance(t) and set dirs.t / hud.t first.
## `intents`: peer -> Array of raw intents for this tick.
func frame(tick: int, intents: Dictionary = {}) -> InputFrame:
	var dt := Wl.SIM_DT
	_absorb()
	var f := InputFrame.new()
	f.tick = tick
	f.t = tick * dt
	for p in ctx.players:
		var ph := clock.phase(p.peer_id, f.t)
		var s: Dictionary = _st[p.peer_id]
		var erg := ph.mode == Wl.ERG or ph.kind == Wl.COOLDOWN
		var new_phase := ph.index != int(s["phase"])
		if new_phase:
			s["phase"] = ph.index
			s["directed_pct"] = -1.0
		var tm := Telemetry.new()
		tm.peer_id = p.peer_id
		tm.t = f.t
		var want_w := 0.0
		var tau := SIM_TAU_S
		if erg:
			tau = ERG_TAU_S
			var pct := (
				float(s["directed_pct"]) if float(s["directed_pct"]) >= 0.0 else ph.planned_pct
			)
			var target := pct / 100.0 * p.ftp * (1.0 if p.ftp_verified else UNVERIFIED)
			target = maxf(target, maxf(0.3 * p.ftp, 50.0))
			target = floorf(target)
			var applied := float(s["applied_w"])
			if s["mode"] != Wl.ERG:
				applied = minf(float(s["power"]), target)
			elif applied < target:
				applied = minf(target, applied + SLEW_W_PER_S * dt)
			else:
				applied = target
			s["applied_w"] = applied
			s["mode"] = Wl.ERG
			want_w = compliance * applied
			tm.mode = Wl.ERG
			tm.applied_target_w = int(applied)
		else:
			s["mode"] = Wl.SIM
			s["applied_w"] = 0.0
			if float(s["band_lo"]) > 0.0:
				want_w = compliance * 0.5 * (float(s["band_lo"]) + float(s["band_hi"]))
			else:
				want_w = 0.9 * p.ftp
			tm.mode = Wl.SIM
		var power := float(s["power"])
		power += (want_w - power) * (1.0 - exp(-dt / tau))
		s["power"] = power
		tm.power_w = roundf(power)
		tm.p_eff_w = tm.power_w * p.p_eff_per_w
		tm.ftp_pct = tm.power_w / p.ftp * 100.0
		tm.cadence_rpm = CADENCE_RPM
		tm.phase_index = ph.index
		tm.intents = (intents.get(p.peer_id, []) as Array).duplicate(true)
		f.players[p.peer_id] = tm
		f.phase[p.peer_id] = ph
	return f


## Reads the directives and power bands the game sent since the last call.
func _absorb() -> void:
	while _req_seen < dirs.requests.size():
		var entry: Array = dirs.requests[_req_seen]
		_req_seen += 1
		var peer := int(entry[0])
		var d: Dictionary = entry[1]
		var s: Dictionary = _st.get(peer, {})
		if s.is_empty():
			continue
		if str(d.get("mode", "")) == Wl.ERG and d.has("target_pct"):
			s["directed_pct"] = float(d["target_pct"])
		if d.has("mode_grade"):
			(s["grades"] as Dictionary)[str(d.get("reason", ""))] = float(d["mode_grade"])
	while _band_seen < hud.power_band_at.size():
		var b: Array = hud.power_band_at[_band_seen]
		_band_seen += 1
		var bs: Dictionary = _st.get(int(b[1]), {})
		if not bs.is_empty():
			bs["band_lo"] = float(b[2])
			bs["band_hi"] = float(b[3])

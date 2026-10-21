class_name Telemetry
extends RefCounted
## One rider's latest state as the game sees it in `frame.players[peer]` and as a
## client sends it to the host at 5 Hz (BRIEF 3.6, 5.5 `telemetry`). Contract, frozen
## after W0.
##
## Every rider computes its own effort and P_eff (BRIEF 3.3) so the host never needs a
## weight. For a dropped peer the GameHost sets connected = false, power and cadence 0
## and age_s (seconds since the last telemetry).

var peer_id: int = 0
## Sender's platform time in seconds (monotonic, sim-speed aware).
var t: float = 0.0
var power_w: float = 0.0
var cadence_rpm: float = 0.0
## The trainer's reported (flywheel) speed, raw; distance_m integrates it. Games that move a
## vehicle integrate their own SpeedModel from p_eff_w (BRIEF 3.11).
var speed_kmh: float = 0.0
## Effort in the session's scaling mode: P/FTP (FAIR_FTP), P/kg (WKG) or W (RAW).
var effort: float = 0.0
var p_eff_w: float = 0.0
var wbal_j: float = 0.0
## Percent of FTP (raw power / FTP * 100).
var ftp_pct: float = 0.0
## Current trainer mode applied by the governor: "ERG", "SIM" or "OFF".
var mode: String = Wl.OFF
## Applied ERG target in whole watts (0 outside ERG).
var applied_target_w: int = 0
## Applied total SIM grade in % (0 outside SIM).
var applied_grade_pct: float = 0.0
## Virtual gear 1..24 (BRIEF 4.5).
var gear: int = 12
## Rules that changed the latest applied value (Wl.CLAMP_*).
var clamped_by: Array[String] = []
var rescue: bool = false
var coasting: bool = false
var afk: bool = false
var paused: bool = false
## Seconds the rider may still spend above 105% / 120% FTP before the duration limit latches.
var s_left_105: float = 300.0
var s_left_120: float = 60.0
## Gestures recognised since the previous telemetry (Wl.G_*).
var gestures: Array[StringName] = []
## Game intents since the previous telemetry (from local_intents, ctx.intents.send and,
## for Autopilot riders on the host, autopilot_intents).
var intents: Array = []
## Distance from the trainer's reported speed, metres.
var distance_m: float = 0.0
## The rider's current plan phase index as its governor follows it.
var phase_index: int = -1
## Directive acknowledgements since the previous telemetry (the rider's governor records):
## [{id, kind, requested: {...}, applied: {...}, clamped_by: [...], refused: bool,
##   reason: String, dropped: [{channel, reason}] (optional), t: float}].
var acks: Array = []
var connected: bool = true
## Seconds since this rider's latest telemetry arrived. The host sets it every tick for every
## remote rider (0 for local riders and bots); a dropped peer keeps counting.
var age_s: float = 0.0
## Seconds since the last fresh cadence value (measured or estimated).
var cadence_age_s: float = 0.0
## Applied haptic grade in % right now (after intensity and bounds), 0 when none.
var haptic_pct: float = 0.0


func to_dict() -> Dictionary:
	return {
		"peer": peer_id,
		"t": t,
		"power_w": power_w,
		"cadence_rpm": cadence_rpm,
		"speed_kmh": speed_kmh,
		"effort": effort,
		"p_eff_w": p_eff_w,
		"wbal_j": wbal_j,
		"ftp_pct": ftp_pct,
		"mode": mode,
		"applied_target_w": applied_target_w,
		"applied_grade_pct": applied_grade_pct,
		"gear": gear,
		"clamped_by": clamped_by.duplicate(),
		"rescue": rescue,
		"coasting": coasting,
		"afk": afk,
		"paused": paused,
		"s_left_105": s_left_105,
		"s_left_120": s_left_120,
		"gestures": _names(gestures),
		"intents": intents.duplicate(true),
		"distance_m": distance_m,
		"phase_index": phase_index,
		"acks": acks.duplicate(true),
		"connected": connected,
		"age_s": age_s,
		"cadence_age_s": cadence_age_s,
		"haptic_pct": haptic_pct,
	}


static func from_dict(d: Dictionary) -> Telemetry:
	var m := Telemetry.new()
	m.peer_id = int(d.get("peer", 0))
	m.t = float(d.get("t", 0.0))
	m.power_w = float(d.get("power_w", 0.0))
	m.cadence_rpm = float(d.get("cadence_rpm", 0.0))
	m.speed_kmh = float(d.get("speed_kmh", 0.0))
	m.effort = float(d.get("effort", 0.0))
	m.p_eff_w = float(d.get("p_eff_w", 0.0))
	m.wbal_j = float(d.get("wbal_j", 0.0))
	m.ftp_pct = float(d.get("ftp_pct", 0.0))
	m.mode = str(d.get("mode", Wl.OFF))
	m.applied_target_w = int(d.get("applied_target_w", 0))
	m.applied_grade_pct = float(d.get("applied_grade_pct", 0.0))
	m.gear = int(d.get("gear", 12))
	for c: Variant in d.get("clamped_by", []):
		m.clamped_by.append(str(c))
	m.rescue = bool(d.get("rescue", false))
	m.coasting = bool(d.get("coasting", false))
	m.afk = bool(d.get("afk", false))
	m.paused = bool(d.get("paused", false))
	m.s_left_105 = float(d.get("s_left_105", 300.0))
	m.s_left_120 = float(d.get("s_left_120", 60.0))
	for g: Variant in d.get("gestures", []):
		m.gestures.append(StringName(str(g)))
	var ints: Variant = d.get("intents", [])
	if ints is Array:
		m.intents = (ints as Array).duplicate(true)
	m.distance_m = float(d.get("distance_m", 0.0))
	m.phase_index = int(d.get("phase_index", -1))
	var a: Variant = d.get("acks", [])
	if a is Array:
		m.acks = (a as Array).duplicate(true)
	m.connected = bool(d.get("connected", true))
	m.age_s = float(d.get("age_s", 0.0))
	m.cadence_age_s = float(d.get("cadence_age_s", 0.0))
	m.haptic_pct = float(d.get("haptic_pct", 0.0))
	return m


func duplicate_telemetry() -> Telemetry:
	return Telemetry.from_dict(to_dict())


static func _names(arr: Array[StringName]) -> Array:
	var out: Array = []
	for s in arr:
		out.append(String(s))
	return out

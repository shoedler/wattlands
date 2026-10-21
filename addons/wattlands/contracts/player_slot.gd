class_name PlayerSlot
extends RefCounted
## One rider in a session (`ctx.players`, BRIEF 3.6). Contract, frozen after W0.
##
## The look (color, shape, pattern, hollow) is the slot's session look from Wl.slot_look()
## (BRIEF 3.9); the profile color shows only in menus. Bots have negative peer ids,
## is_bot = true, autopilot = true and a verified FTP (the lobby's bot FTP).

var peer_id: int = 0
var name: String = ""
var slot_index: int = 0
var color: Color = Color.WHITE
var shape: String = "circle"
var pattern: String = "solid"
var hollow: bool = false
## The rider's FTP in watts (ERG targets always come from it, in every scaling mode).
var ftp: float = 200.0
var ftp_verified: bool = false
## Wl.FAIR_FTP, Wl.WKG or Wl.RAW (the lobby's scaling mode).
var scaling_mode: String = Wl.FAIR_FTP
## P_eff per raw watt, computed by the rider's own client: 250 / FTP (FAIR_FTP),
## 75 / weight (WKG), 1 (RAW). Multiply raw W by it to get P_eff.
var p_eff_per_w: float = 1.25
## The scaling mode's mass for the speed model (BRIEF 3.3, 3.11): 75 unless RAW with
## the weight shared.
var rider_mass_kg: float = 75.0
var preferred_cadence_rpm: float = 90.0
## The rider accepts haptic effects (BRIEF 3.2). Governors drop haptics when false.
var haptics_on: bool = true
## Haptic intensity 0..1 (applied by the rider's governor; games never scale haptics).
var haptic_intensity: float = 0.7
var autopilot: bool = false
var is_bot: bool = false
## This rider's player_options values (game.json `player_options`, defaults filled in).
var options: Dictionary = {}


func apply_look(p_slot_index: int) -> void:
	slot_index = p_slot_index
	var look := Wl.slot_look(p_slot_index)
	color = look["color"]
	shape = look["shape"]
	pattern = look["pattern"]
	hollow = look["hollow"]


func to_dict() -> Dictionary:
	return {
		"peer_id": peer_id,
		"name": name,
		"slot_index": slot_index,
		"color": color.to_html(false),
		"shape": shape,
		"pattern": pattern,
		"hollow": hollow,
		"ftp": ftp,
		"ftp_verified": ftp_verified,
		"scaling_mode": scaling_mode,
		"p_eff_per_w": p_eff_per_w,
		"rider_mass_kg": rider_mass_kg,
		"preferred_cadence_rpm": preferred_cadence_rpm,
		"haptics_on": haptics_on,
		"haptic_intensity": haptic_intensity,
		"autopilot": autopilot,
		"is_bot": is_bot,
		"options": options.duplicate(true),
	}


static func from_dict(d: Dictionary) -> PlayerSlot:
	var s := PlayerSlot.new()
	s.peer_id = int(d.get("peer_id", 0))
	s.name = str(d.get("name", ""))
	s.slot_index = int(d.get("slot_index", 0))
	s.color = Color.from_string(str(d.get("color", "ffffff")), Color.WHITE)
	s.shape = str(d.get("shape", "circle"))
	s.pattern = str(d.get("pattern", "solid"))
	s.hollow = bool(d.get("hollow", false))
	s.ftp = float(d.get("ftp", 200.0))
	s.ftp_verified = bool(d.get("ftp_verified", false))
	s.scaling_mode = str(d.get("scaling_mode", Wl.FAIR_FTP))
	s.p_eff_per_w = float(d.get("p_eff_per_w", 1.25))
	s.rider_mass_kg = float(d.get("rider_mass_kg", 75.0))
	s.preferred_cadence_rpm = float(d.get("preferred_cadence_rpm", 90.0))
	s.haptics_on = bool(d.get("haptics_on", true))
	s.haptic_intensity = float(d.get("haptic_intensity", 0.7))
	s.autopilot = bool(d.get("autopilot", false))
	s.is_bot = bool(d.get("is_bot", false))
	var o: Variant = d.get("options", {})
	if o is Dictionary:
		s.options = (o as Dictionary).duplicate(true)
	return s

class_name RiderProfile
extends RefCounted
## The local rider profile, profile.json in Paths.user_dir() (BRIEF 3.2). No accounts.
## Frozen public fields after W0 (additive changes only); the platform agent owns loading,
## saving and the profile flows (WlSettings).

var display_name: String = "Rider"
var color: Color = Color("#D55E00")
## "metric" (default) or "imperial".
var units: String = "metric"
var weight_kg: float = 75.0
## Share weight with the host (only WKG/RAW scaling ever needs it; BRIEF 3.2, 3.3).
var share_weight: bool = false
var ftp_w: float = 200.0
## False until the rider types an FTP, finishes the FTP test or imports it from Strava.
var ftp_verified: bool = false
## Critical power (= FTP) and W' in joules for the W' balance model (BRIEF 3.4).
var cp_w: float = 200.0
var wprime_j: float = 20000.0
var preferred_cadence_rpm: float = 90.0
## "cassette" or "single_speed".
var drivetrain: String = "cassette"
## Trainer difficulty in % (scales SIM grade, BRIEF 4.6.6).
var difficulty_pct: float = 50.0
var haptics_on: bool = true
## 0..100 %.
var haptic_intensity_pct: float = 70.0
## Safety caps (BRIEF 4.6 defaults): user SIM grade range and the skip-warm-up opt-out.
var grade_min_pct: float = -5.0
var grade_max_pct: float = 10.0
var skip_warmup: bool = false
var autopilot_default: bool = false
## Pedal-scan menus even with a controller (Autopilot or pedal UI, BRIEF 3.5).
var pedal_ui: bool = true
var scan_interval_s: float = 1.6
var strava_auto_upload: bool = false
var metronome: bool = false
## Set once a profile was saved (first run creates "Rider", FTP 200, unverified).
var created: bool = false


## P_eff per raw watt in `mode` (BRIEF 3.3): 250/FTP, 75/weight or 1.
func p_eff_per_w(mode: String) -> float:
	return EffortScaling.p_eff_per_w(mode, ftp_w, weight_kg)


## The speed model's rider mass in `mode` (75 unless RAW with the weight shared).
func rider_mass_kg(mode: String) -> float:
	return EffortScaling.rider_mass_kg(mode, weight_kg, share_weight)


## A PlayerSlot for this rider (look and peer filled in by the lobby).
func to_slot(peer_id: int, scaling_mode: String) -> PlayerSlot:
	var s := PlayerSlot.new()
	s.peer_id = peer_id
	s.name = display_name
	s.ftp = ftp_w
	s.ftp_verified = ftp_verified
	s.scaling_mode = scaling_mode
	s.p_eff_per_w = p_eff_per_w(scaling_mode)
	s.rider_mass_kg = rider_mass_kg(scaling_mode)
	s.preferred_cadence_rpm = preferred_cadence_rpm
	s.haptics_on = haptics_on
	s.haptic_intensity = haptic_intensity_pct / 100.0
	s.autopilot = autopilot_default
	return s


func to_dict() -> Dictionary:
	return {
		"display_name": display_name, "color": color.to_html(false), "units": units,
		"weight_kg": weight_kg, "share_weight": share_weight, "ftp_w": ftp_w,
		"ftp_verified": ftp_verified, "cp_w": cp_w, "wprime_j": wprime_j,
		"preferred_cadence_rpm": preferred_cadence_rpm, "drivetrain": drivetrain,
		"difficulty_pct": difficulty_pct, "haptics_on": haptics_on,
		"haptic_intensity_pct": haptic_intensity_pct, "grade_min_pct": grade_min_pct,
		"grade_max_pct": grade_max_pct, "skip_warmup": skip_warmup,
		"autopilot_default": autopilot_default, "pedal_ui": pedal_ui,
		"scan_interval_s": scan_interval_s, "strava_auto_upload": strava_auto_upload,
		"metronome": metronome, "created": created,
	}


static func from_dict(d: Dictionary) -> RiderProfile:
	var p := RiderProfile.new()
	p.display_name = str(d.get("display_name", p.display_name))
	# from_string: a hand-edited, invalid color keeps the default instead of logging an error.
	p.color = Color.from_string(str(d.get("color", "")), p.color)
	p.units = str(d.get("units", p.units))
	p.weight_kg = float(d.get("weight_kg", p.weight_kg))
	p.share_weight = bool(d.get("share_weight", p.share_weight))
	p.ftp_w = float(d.get("ftp_w", p.ftp_w))
	p.ftp_verified = bool(d.get("ftp_verified", p.ftp_verified))
	p.cp_w = float(d.get("cp_w", p.ftp_w))
	p.wprime_j = float(d.get("wprime_j", p.wprime_j))
	p.preferred_cadence_rpm = float(d.get("preferred_cadence_rpm", p.preferred_cadence_rpm))
	p.drivetrain = str(d.get("drivetrain", p.drivetrain))
	p.difficulty_pct = float(d.get("difficulty_pct", p.difficulty_pct))
	p.haptics_on = bool(d.get("haptics_on", p.haptics_on))
	p.haptic_intensity_pct = float(d.get("haptic_intensity_pct", p.haptic_intensity_pct))
	p.grade_min_pct = float(d.get("grade_min_pct", p.grade_min_pct))
	p.grade_max_pct = float(d.get("grade_max_pct", p.grade_max_pct))
	p.skip_warmup = bool(d.get("skip_warmup", p.skip_warmup))
	p.autopilot_default = bool(d.get("autopilot_default", p.autopilot_default))
	p.pedal_ui = bool(d.get("pedal_ui", p.pedal_ui))
	p.scan_interval_s = float(d.get("scan_interval_s", p.scan_interval_s))
	p.strava_auto_upload = bool(d.get("strava_auto_upload", p.strava_auto_upload))
	p.metronome = bool(d.get("metronome", p.metronome))
	p.created = bool(d.get("created", p.created))
	return p

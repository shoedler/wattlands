class_name GovernorClamps
extends RefCounted
## The governor's absolute ERG clamps (BRIEF 4.6.1, 4.6.12) as pure functions. Tested in
## W0; the SafetyGovernor builds every other rule on top of these.
##   floor   = max(30% FTP, 50 W), rounded UP to whole watts; wins over every cap and
##             over rescue's 50%.
##   ceiling = min(150% FTP, 1000 W, the trainer's Supported Power Range max), rounded DOWN.
## Applied ERG targets are whole watts: the governed target is rounded down, the floor up,
## and caps compare that whole-watt value, so a target exactly at a cap is not "clamped".

const FLOOR_PCT := 30.0
const FLOOR_MIN_W := 50.0
const CEILING_PCT := 150.0
const CEILING_ABS_W := 1000.0
const UNVERIFIED_FACTOR := 0.85
const KICKR_MAX_W := 1800
## The FTP range a governor accepts (W4, SAF-1): the same 30-2000 W Settings clamps a profile
## into (WlSettings.PROFILE_RANGES), so a value from elsewhere (a host's session_start, a
## hand-edited file) can never set a rider's watt basis outside what the rider could enter.
const FTP_MIN_W := 30.0
const FTP_MAX_W := 2000.0


## True when `ftp_w` is a finite FTP inside FTP_MIN_W..FTP_MAX_W.
static func ftp_in_range(ftp_w: float) -> bool:
	return is_finite(ftp_w) and ftp_w >= FTP_MIN_W and ftp_w <= FTP_MAX_W


static func pct_to_w(pct: float, ftp_w: float) -> float:
	return pct * ftp_w / 100.0


static func w_to_pct(w: float, ftp_w: float) -> float:
	return 100.0 * w / maxf(ftp_w, 1.0)


## max(30% FTP, 50 W), rounded up.
static func floor_w(ftp_w: float) -> int:
	return int(ceil(maxf(pct_to_w(FLOOR_PCT, ftp_w), FLOOR_MIN_W) - 1e-9))


## min(150% FTP, 1000 W, trainer max), rounded down. trainer_max_w <= 0 means unknown.
static func ceiling_w(ftp_w: float, trainer_max_w: float = KICKR_MAX_W) -> int:
	var c := minf(pct_to_w(CEILING_PCT, ftp_w), CEILING_ABS_W)
	if trainer_max_w > 0.0:
		c = minf(c, trainer_max_w)
	return int(floor(c + 1e-9))


## The ramp_test profile's ceiling (BRIEF 3.2): min(1000 W, trainer max).
static func ramp_test_ceiling_w(trainer_max_w: float = KICKR_MAX_W) -> int:
	var c := CEILING_ABS_W
	if trainer_max_w > 0.0:
		c = minf(c, trainer_max_w)
	return int(floor(c + 1e-9))


static func unverified_factor(ftp_verified: bool) -> float:
	return 1.0 if ftp_verified else UNVERIFIED_FACTOR


## Whole-watt value of a governed target (rounded down).
static func whole_w(w: float) -> int:
	return int(floor(w + 1e-9))


## Absolute clamp only (no duration, warm-up, rescue or slew rules):
## {"w": int, "clamped_by": Array[String]} with Wl.CLAMP_CEILING and/or Wl.CLAMP_FLOOR.
## The floor wins over the ceiling (it can only exceed it at absurd FTPs).
static func clamp_absolute(target_w: float, ftp_w: float, trainer_max_w: float = KICKR_MAX_W) -> Dictionary:
	var clamped_by: Array[String] = []
	var w := whole_w(target_w)
	var ceil_w := ceiling_w(ftp_w, trainer_max_w)
	if w > ceil_w:
		w = ceil_w
		clamped_by.append(Wl.CLAMP_CEILING)
	var fl := floor_w(ftp_w)
	if w < fl:
		w = fl
		clamped_by.append(Wl.CLAMP_FLOOR)
	return {"w": w, "clamped_by": clamped_by}

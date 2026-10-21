class_name EffortScaling
extends RefCounted
## Effort scaling modes (BRIEF 3.3). Pure functions; tested in W0.
##   FAIR_FTP (default): effort = P / FTP; P_eff = (P / FTP) * 250 W for a 75 kg reference.
##   WKG: effort = P / weight; P_eff = (P / weight) * 75 for the same reference rider.
##   RAW: effort = P; P_eff = P; mass = the rider's weight only if shared, else 75 kg.
## ERG targets always come from each rider's own FTP; scaling only turns effort into game
## output. Each client computes its own effort and P_eff, so the host never needs a weight.

const REFERENCE_W := 250.0
const REFERENCE_KG := 75.0


static func effort(mode: String, power_w: float, ftp_w: float, weight_kg: float) -> float:
	match mode:
		Wl.WKG:
			return power_w / maxf(weight_kg, 1.0)
		Wl.RAW:
			return power_w
		_:
			return power_w / maxf(ftp_w, 1.0)


## P_eff per raw watt: 250 / FTP (FAIR_FTP), 75 / weight (WKG), 1 (RAW).
static func p_eff_per_w(mode: String, ftp_w: float, weight_kg: float) -> float:
	match mode:
		Wl.WKG:
			return REFERENCE_KG / maxf(weight_kg, 1.0)
		Wl.RAW:
			return 1.0
		_:
			return REFERENCE_W / maxf(ftp_w, 1.0)


static func p_eff_w(mode: String, power_w: float, ftp_w: float, weight_kg: float) -> float:
	return power_w * p_eff_per_w(mode, ftp_w, weight_kg)


## The speed model's rider mass: 75 kg unless RAW with the weight shared.
static func rider_mass_kg(mode: String, weight_kg: float, weight_shared: bool) -> float:
	if mode == Wl.RAW and weight_shared and weight_kg > 0.0:
		return weight_kg
	return REFERENCE_KG


## W/kg for display (only when the rider opted in to share/show weight).
static func wkg(power_w: float, weight_kg: float) -> float:
	return power_w / maxf(weight_kg, 1.0)


static func ftp_pct(power_w: float, ftp_w: float) -> float:
	return 100.0 * power_w / maxf(ftp_w, 1.0)

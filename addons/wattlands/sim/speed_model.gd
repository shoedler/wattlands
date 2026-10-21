class_name SpeedModel
extends RefCounted
## Shared vehicle speed model (BRIEF 3.11), integrated every sim step from P_eff:
##   v += dt * (eta * P_eff / max(v, 1) - m*g*(Crr*cos(th) + sin(th))
##              - 0.5*rho*CdA*(v + v_wind)*|v + v_wind|) / m,   v >= 0
## with Crr 0.004, CdA 0.32 m^2, rho 1.225, eta 0.97 and m = rider mass + 8 kg.
## A game may pass its own CdA, mass offset and a visual speed multiplier for feel.
## steady_state_speed() solves P*eta = v*(m*g*(Crr*cos + sin) + 0.5*rho*CdA*(v+v_wind)^2)
## by bisection on [0, 30] m/s; tests use it as the oracle.

const G := 9.80665
const DEFAULT_CRR := 0.004
const DEFAULT_CDA := 0.32
const DEFAULT_RHO := 1.225
const DEFAULT_ETA := 0.97
const DEFAULT_MASS_OFFSET_KG := 8.0

var crr: float = DEFAULT_CRR
var cda: float = DEFAULT_CDA
var rho: float = DEFAULT_RHO
var eta: float = DEFAULT_ETA
var rider_mass_kg: float = 75.0
var mass_offset_kg: float = DEFAULT_MASS_OFFSET_KG
## Multiplies the reported visual speed only (physics unchanged).
var visual_multiplier: float = 1.0
## Current physical speed, m/s.
var v_mps: float = 0.0
## Distance travelled, metres (physical).
var distance_m: float = 0.0


static func create(
	p_rider_mass_kg: float = 75.0,
	p_cda: float = DEFAULT_CDA,
	p_mass_offset_kg: float = DEFAULT_MASS_OFFSET_KG
) -> SpeedModel:
	var m := SpeedModel.new()
	m.rider_mass_kg = p_rider_mass_kg
	m.cda = p_cda
	m.mass_offset_kg = p_mass_offset_kg
	return m


func mass_kg() -> float:
	return rider_mass_kg + mass_offset_kg


## Advance by dt seconds with P_eff in watts, grade in %, headwind in m/s. Returns v (m/s).
func step(dt: float, p_eff_w: float, grade_pct: float = 0.0, wind_mps: float = 0.0) -> float:
	var m := mass_kg()
	var th := atan(grade_pct / 100.0)
	var drive := eta * maxf(p_eff_w, 0.0) / maxf(v_mps, 1.0)
	var gravity_roll := m * G * (crr * cos(th) + sin(th))
	var rel := v_mps + wind_mps
	var aero := 0.5 * rho * cda * rel * absf(rel)
	v_mps = maxf(0.0, v_mps + dt * (drive - gravity_roll - aero) / m)
	distance_m += v_mps * dt
	return v_mps


func speed_kmh() -> float:
	return v_mps * 3.6


func visual_speed_mps() -> float:
	return v_mps * visual_multiplier


func reset(v: float = 0.0) -> void:
	v_mps = v
	distance_m = 0.0


## Steady-state speed (m/s) for power p_w, by bisection on [0, 30] m/s.
static func steady_state_speed(
	p_w: float,
	grade_pct: float,
	mass_kg_total: float,
	p_cda: float = DEFAULT_CDA,
	p_crr: float = DEFAULT_CRR,
	wind_mps: float = 0.0,
	p_rho: float = DEFAULT_RHO,
	p_eta: float = DEFAULT_ETA
) -> float:
	var th := atan(grade_pct / 100.0)
	var target := p_w * p_eta
	var lo := 0.0
	var hi := 30.0
	for _i in 200:
		var mid := 0.5 * (lo + hi)
		var rel := mid + wind_mps
		var need := (
			mid
			* (mass_kg_total * G * (p_crr * cos(th) + sin(th)) + 0.5 * p_rho * p_cda * rel * rel)
		)
		if need < target:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)

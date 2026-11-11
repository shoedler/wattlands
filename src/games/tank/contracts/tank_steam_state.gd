class_name TankSteamState
extends TankStationState
## The steam engine (brief 2.4 Steam; v3: the Loader seat): boiler pressure, the Overpressure
## window, latching shells. The director sends its mode grade 8% x min(pressure, 1) in WORK SIM
## phases and 3% x min(pressure, 1) in WARMUP-kind ones (never above +3% in the warm-up, even if
## pressure overshoots 100% within a tick), 0 while loaded or cycling (brief 2.3 pattern 2;
## TankDirector.boiler_grade_pct).

## [snap] Pressure in % (0..150; 100% = 6 kJ of P_eff).
var pressure_pct: float = 0.0
## The part of `pressure_pct` the below-band trickle added (steam.below_band_gain; 0 in band). The boiler's grade
## follows only the pressure earned in band, `grade_pressure_pct()`, so a rider under the window is never loaded
## more because the trickle gave them progress. Host only; not on the wire.
var trickle_pct: float = 0.0
## [snap] Seconds left of the 5 s "Surge to overpressure" window at 100%; 0 when none.
var window_s: float = 0.0
## [snap] Overpressure is building (100 -> 150% on 3 kJ while the sprint rule holds).
var over: bool = false
## Seconds since Overpressure started (the shell latches at 150% or after 30 s).
var over_s: float = 0.0
## [snap] A shell is latched (riding the hoist or in the breech): pressure cannot build and the
## cadence band is (50, 120). On the latch its type goes straight into TankHullState.loaded (the
## latch event carries it too); the ride up the hoist is view-only animation.
var loaded: bool = false
## [snap] The 6 s breech cycle after the shot is running (same rules as loaded).
var cycling: bool = false
## The sprint rule holds (Overpressure counts energy only then).
var sprinting: bool = false

# --- v3 loader: the 3-round ready rack (brief "Combat changes", Main gun reload) -------------------
## The Loader in band fills a ready rack of TankConst.RACK_MAX shells, one per tanks.json
## steam.full_j; the Gun fires from it, and each shot chambers the next shell (about 1 s at the
## loading elevation) before the gun re-lays. The rules builder implements the cycle; the view's
## turret windows (the rack with its manipulator, the breech with its rammer) and the HUD's rack pips
## read these.

## [snap] Shells ready in the rack, 0..TankConst.RACK_MAX.
var rack: int = 0
## [snap] A round sits chambered in the breech (ready to fire; TankHullState.loaded holds its type).
var chamber: bool = false
## [snap] Seconds left of chambering the next shell from the rack after a shot; 0 when none.
var chamber_s: float = 0.0
## [snap] The loader's cycle phase for the shell it is working on, 0..1 (0 idle or just begun, 1
## stowed in the rack); the view maps it onto the r6 loader's steps (hoist, stow, ...).
var load_t: float = 0.0


## The pressure the boiler's grade follows: what was earned in band, never the trickle's share.
func grade_pressure_pct() -> float:
	return maxf(pressure_pct - trickle_pct, 0.0)

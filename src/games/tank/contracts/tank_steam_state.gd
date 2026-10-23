class_name TankSteamState
extends TankStationState
## The steam engine (brief 2.4 Steam, the Citadel's loader): boiler pressure, the Overpressure
## window, latching shells. The director sends its mode grade 8% x min(pressure, 1) (3% x
## pressure in WARMUP-kind segments), 0 while loaded or cycling (brief 2.3 pattern 2).

## [snap] Pressure in % (0..150; 100% = 6 kJ of P_eff).
var pressure_pct: float = 0.0
## [snap] Seconds left of the 5 s "Surge to overpressure" window at 100%; 0 when none.
var window_s: float = 0.0
## [snap] Overpressure is building (100 -> 150% on 3 kJ while the sprint rule holds).
var over: bool = false
## Seconds since Overpressure started (the shell latches at 150% or after 30 s).
var over_s: float = 0.0
## [snap] A shell is latched (riding the hoist or in the breech): pressure cannot build and the
## cadence band is (50, 120).
var loaded: bool = false
## [snap] The 6 s breech cycle after the shot is running (same rules as loaded).
var cycling: bool = false
## The sprint rule holds (Overpressure counts energy only then).
var sprinting: bool = false

class_name TankHullState
extends TankRecord
## The crew's tank as a vehicle (G0 contract): hull, drive, berm, breakdown and the main gun.
## The rules (TankRules) write it on the host; TankSnapshot carries the [snap] fields; the view
## and HUD read it. Units: TankConst.

## TankIds.TANK_* and its code.
var tank: String = TankIds.TANK_BULWARK
var code: int = 1
## Hull size in art px (tanks.json hull_px).
var hull_w: int = 192
var hull_h: int = 72

# --- Drive (brief 2.4 Drive) -------------------------------------------------------------------------
## [snap] World x of the hull's rear edge in art px (the camera follows it).
var x_px: float = 0.0
## Game metres driven in the current segment (terrain and encounters key on it).
var distance_m: float = 0.0
## [snap] Game speed in m/s (SpeedModel on the driver's P_eff; 0 while stopped).
var speed_mps: float = 0.0
## [snap] The terrain grade under the tank in % before difficulty (the director pushes it with
## course_grade at 2 Hz in grade_source "game" phases).
var grade_pct: float = 0.0
## Tracks locked: dug in at a gun line, holding at the boss, or "Regroup" before min_s.
var holding: bool = false
## [snap] Seconds of a failed-Ram stall left.
var stall_s: float = 0.0
## Stopped by an obstacle (its id; 0 none).
var blocked_by: int = 0
## The driver is in band: enemy hit chances x evasive_hit_mult.
var evasive: bool = false

# --- Hull HP and breakdown (brief 2.4) ---------------------------------------------------------------
## [snap]
var hp: float = 100.0
## [snap]
var hp_max: float = 100.0
## [snap] At 0 HP: no movement or fire, damage ignored, until repair_j reaches the repair energy.
var breakdown: bool = false
## [snap] Joules of the diesel's (or Bulwark's) P_eff paid toward the repair.
var repair_j: float = 0.0

# --- Dig in (gun lines) ------------------------------------------------------------------------------
## [snap] Mud berm HP (absorbs hits first; +1 per 250 J in band; max 40).
var berm_hp: float = 0.0
## Joules banked toward the next berm HP.
var berm_j: float = 0.0
## [snap] The tank traps were shoved aside (the last gun fell).
var traps_cleared: bool = false

# --- Main gun (brief 2.4 Gun) ------------------------------------------------------------------------
## [snap] TankIds.FACE_RIGHT or FACE_LEFT.
var facing: int = TankIds.FACE_RIGHT
## [snap] Barrel elevation in degrees (-5..+30).
var elev_deg: float = 0.0
## The elevation the gun is slewing to.
var elev_target_deg: float = 0.0
## [snap] Seconds of a traverse (a facing flip) left; 0 when not traversing.
var traverse_s: float = 0.0
## [snap] TankIds.SHELL_* in the breech (SHELL_NONE when empty).
var loaded: int = TankIds.SHELL_NONE
## [snap] Seconds of the breech cycle left after a shot (nothing loads before it ends).
var breech_s: float = 0.0
## [snap] The id of the enemy, obstacle or boss part auto-aim (or the rider) targets; 0 none.
## Boss parts: TankBossState.PART_ID_BASE + part index.
var target_id: int = 0
## Seconds left of auto-aim's pause after a manual nudge.
var aim_pause_s: float = 0.0
## Citadel secondaries: seconds to the next shot (fore, aft).
var secondary_cd_s: Array[float] = [0.0, 0.0]

class_name TankConst
extends RefCounted
## Units, screen geometry and the shared numeric rules every builder must agree on (G0 contract).
## Content numbers (HP, damage, energies) live in content/tank/*.json, not here.
##
## Units: positions and sizes in art px of pixel_base 640 x 360; distances driven in game metres;
## time in game seconds (0.05 s ticks); energy in joules of P_eff; effort in % FTP.
## World x: art px along the road, 0 at the start of the current segment, growing to the right.
## The tank's rear sits at screen x REAR_SCREEN_X, so screen x = world x - camera_x where
## camera_x = TankHullState.x_px - REAR_SCREEN_X.

## Ground line (the bottom of the tracks) in art px.
const GROUND_Y := 296
## The hull's rear edge on screen.
const REAR_SCREEN_X := 16
const SCREEN_W := 640
## World scroll: 0.4 x game speed at 20 art px per visual metre, so 8 art px per game metre
## (80% FTP on the flat ~ 8.2 m/s ~ 66 px/s).
const WORLD_SCROLL := 0.4
const PX_PER_VISUAL_M := 20.0
const PX_PER_M := WORLD_SCROLL * PX_PER_VISUAL_M
## The HUD covers y 0..HUD_TOP_H and HUD_BOTTOM_Y..360 only (brief 3).
const HUD_TOP_H := 60
const HUD_BOTTOM_Y := 300

## The first 300 s of the plan: no evade, Overpressure, sprint prompt or haptic
## (PhaseState.plan_elapsed_s < FIRST_S), brief 2.3, 2.7.
const FIRST_S := 300.0

## The Hangar's last seconds are the countdown: the ceiling bars go dark, the red beacons turn, the
## hull is lowered off its stand and the hangar door opens (TankSegments.hangar_countdown_s).
const HANGAR_COUNTDOWN_S := 10.0

## Steam "building" is >= 90% FTP (brief 2.3). The SIM mock rider rides exactly 90% FTP with no
## published band (GAME_SDK 20), and power arrives in whole watts, so the comparison keeps a small
## tolerance (ADR "Steam 90% float tolerance"): building when
## power_w >= 0.90 x FTP - max(STEAM_TOL_W, STEAM_TOL_PCT% x FTP).
const STEAM_BUILD_PCT := 90.0
const STEAM_TOL_PCT := 0.5
const STEAM_TOL_W := 1.0

## Snapshot budget (brief 2.6) and the caps it is measured at.
const SNAPSHOT_MAX_BYTES := 4096
const MAX_ENEMIES := 16
const MAX_SHELLS := 24
## Host-side intent rate limit per peer (brief 2.6).
const INTENTS_PER_S := 5

## v3 (brief "Combat changes"): the Loader's ready rack holds this many main-gun shells (the r6
## turret window draws three).
const RACK_MAX := 3
## 0.3.1 (no seat lock): a rider's trainer switches ERG <-> SIM at most once in this long (BRIEF 4.5,
## the PlanValidator's 30 s): a seat move whose mode differs waits for it (TankSeatPlan.follow).
const SWITCH_GAP_S := 30.0
## 0.3.1: an Autopilot-seated crew rider stays at least this long on a seat (no thrashing; at least
## the trainer's SWITCH_GAP_S), a solo rider AUTO_STAY_SOLO_S (it works every seat alone).
const AUTO_STAY_S := 60.0
const AUTO_STAY_SOLO_S := 30.0
## v4: the near panel's span ahead of the hull's front in rules px. The view maps 0..NEAR_SPAN_PX onto
## nose..panel edge on every canvas, so the rules never depend on the canvas (TankFarMap).
const NEAR_SPAN_PX := 200.0
## v4: the far field's end (m): a retiring enemy is gone past it; nothing spawns beyond it.
const FAR_SPAWN_M := 2600.0


## True when a rider at `power_w` raw watts with FTP `ftp_w` counts as building steam.
static func steam_building(power_w: float, ftp_w: float) -> bool:
	if ftp_w <= 0.0:
		return false
	var tol := maxf(STEAM_TOL_W, STEAM_TOL_PCT / 100.0 * ftp_w)
	return power_w >= STEAM_BUILD_PCT / 100.0 * ftp_w - tol


## True in the first 300 s of the plan (PhaseState.plan_elapsed_s), where abilities, sprint
## prompts and haptics are off.
static func in_first_window(plan_elapsed_s: float) -> bool:
	return plan_elapsed_s < FIRST_S


## Game metres to world art px.
static func m_to_px(m: float) -> float:
	return m * PX_PER_M

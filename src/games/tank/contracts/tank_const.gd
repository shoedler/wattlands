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
const SCREEN_H := 360
## World scroll: 0.4 x game speed at 20 art px per visual metre, so 8 art px per game metre
## (80% FTP on the flat ~ 8.2 m/s ~ 66 px/s).
const WORLD_SCROLL := 0.4
const PX_PER_VISUAL_M := 20.0
const PX_PER_M := WORLD_SCROLL * PX_PER_VISUAL_M
## The HUD covers y 0..HUD_TOP_H and HUD_BOTTOM_Y..360 only (brief 3).
const HUD_TOP_H := 60
const HUD_BOTTOM_Y := 300
## The app's PANIC button owns art x >= 503 and y >= 316 (GAME_SDK 10.1).
const PANIC_X := 503
const PANIC_Y := 316

## The first 300 s of the plan: no Ram, dodge, Overpressure, sprint prompt or haptic
## (PhaseState.plan_elapsed_s < FIRST_S), brief 2.3, 2.7.
const FIRST_S := 300.0

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

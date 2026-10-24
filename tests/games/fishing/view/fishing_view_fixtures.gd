class_name FishingViewFixtures
extends RefCounted
## Hand-made riders for the view and HUD tests and the art preview: a configured FishingGame
## (FishingFakes context) whose riders are then put driving, stopped at a menu, waiting, in a
## fight or a Landing, so the presentation is checked without running the rules.

const F := preload("res://tests/games/fishing/fishing_fakes.gd")


## A configured game with `n` riders; the local rider sits in `local_slot`.
static func make_game(
	n: int, local_slot: int = 0, role: String = Wl.SOLO, content_id: String = "roam_30"
) -> FishingGame:
	var ctx := F.make_ctx(n, 0, content_id, role, local_slot + 1)
	return F.make_game(ctx)


static func set_drive(
	r: FishingRiderState, x_m: float, v_mps: float = 5.0, heading: int = 1
) -> void:
	r.action = FishingConst.A_DRIVE
	r.x_m = x_m
	r.heading = heading
	r.v_mps = v_mps * float(heading)
	r.pitch_deg = clampf(v_mps * 0.8, 0.0, 8.0)
	r.wake = clampf(v_mps / 7.0, 0.0, 1.0)
	r.p_eff_w = 240.0
	r.cadence_ema = 90.0
	r.hints.clear()
	r.menu.clear()
	r.fish.sp = FishingConst.SP_NONE


## Stopped with three fish on offer (mackerel shallow ahead, bream deeper behind, a snapper),
## the menu [cast 0, cast 1, cast 2, drive on, turn] with `selected` lit.
static func set_menu(r: FishingRiderState, x_m: float, selected: int = 0) -> void:
	set_drive(r, x_m, 0.0)
	r.action = FishingConst.A_MENU
	r.wake = 0.0
	r.pitch_deg = 0.0
	r.cadence_ema = 0.0
	r.hints.assign([0.0, 22.0, 4.0, 0.4, 1.0, -18.0, 9.0, 0.7, 2.0, 34.0, 14.0, 0.9])
	r.menu.assign([0, 1, 2, FishingConst.M_DRIVE_ON, FishingConst.M_TURN])
	r.selected = selected


static func set_wait(
	r: FishingRiderState, x_m: float, sp: int = 4, lure_dx: float = -12.0, depth: float = 30.0
) -> void:
	set_drive(r, x_m, 0.0)
	r.action = FishingConst.A_WAIT
	r.wake = 0.0
	r.pitch_deg = 0.0
	r.target_sp = sp
	r.lure_dx = lure_dx
	r.lure_depth = depth
	r.cadence_ema = 70.0


## A fight with species `sp`, `d` m behind the stern at `depth` m, the given meters.
static func set_fight(
	r: FishingRiderState,
	x_m: float,
	sp: int = 8,
	d: float = 40.0,
	depth: float = 200.0,
	strain: float = 0.4,
	slack: float = 0.1
) -> void:
	set_drive(r, x_m, 0.0)
	r.action = FishingConst.A_FIGHT
	r.wake = 0.0
	r.pitch_deg = 0.0
	r.fish.sp = sp
	r.fish.d = d
	r.fish.hook_depth_m = depth
	r.fish.z = 1.0
	r.fish.s = 0.6
	r.fish.off_line = false
	r.fish.run_active = false
	r.strain = strain
	r.slack = slack
	r.cadence_ema = 92.0
	r.power_w = 260.0


static func set_land(r: FishingRiderState, x_m: float, sp: int = 3, t: float = 5.0) -> void:
	set_fight(r, x_m, sp, 4.0, 1.0, 0.0, 0.0)
	r.action = FishingConst.A_LAND
	r.state_t = t
	r.gaff = 0.4

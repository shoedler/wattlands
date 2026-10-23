class_name FishingViewFixtures
extends RefCounted
## Hand-made FishingState for the view and HUD tests: a configured FishingGame (FishingFakes
## context, e2e_2min content) whose lanes are then set to a pick, a fight, a Landing or the ride
## home, so the presentation is checked without the rules.

const F := preload("res://tests/games/fishing/fishing_fakes.gd")


## A configured game with `n` riders; the local rider sits in `local_slot`.
static func make_game(
	n: int, local_slot: int = 0, role: String = Wl.SOLO, content_id: String = "e2e_2min"
) -> FishingGame:
	var ctx := F.make_ctx(n, 0, content_id, role, local_slot + 1)
	return F.make_game(ctx)


## A pick with three hints: bird pile 50 m (strength 0.9), current seam 65 m (0.5), drop-off
## 80 m (0.2); `selected` highlighted.
static func set_pick(l: FishingLaneState, selected: int = 1) -> void:
	l.state = FishingConst.ST_PICK
	l.phase_kind = Wl.RECOVERY
	(
		l
		. hints
		. assign(
			[
				float(FishingConst.SPOT_BIRD_PILE),
				50.0,
				0.9,
				float(FishingConst.SPOT_CURRENT_SEAM),
				65.0,
				0.5,
				float(FishingConst.SPOT_DROP_OFF),
				80.0,
				0.2,
			]
		)
	)
	l.selected = selected
	l.fish.sp = FishingConst.SP_NONE


static func set_reel(l: FishingLaneState, lure_d: float = 60.0) -> void:
	l.state = FishingConst.ST_REEL
	l.hints.clear()
	l.lure_d = lure_d
	l.cadence_ema = 88.0


## A fight with species `sp` at distance `d` (m), depth `z`, the given meters.
static func set_fight(
	l: FishingLaneState,
	sp: int = 1,
	d: float = 60.0,
	z: float = 0.5,
	strain: float = 0.3,
	slack: float = 0.1
) -> void:
	l.state = FishingConst.ST_FIGHT
	l.phase_kind = Wl.WORK
	l.hints.clear()
	l.fish.sp = sp
	l.fish.d = d
	l.fish.z = z
	l.fish.s = 0.7
	l.fish.off_line = false
	l.fish.run_active = false
	l.strain = strain
	l.slack = slack
	l.pub_lo = 82
	l.pub_hi = 98
	l.cadence_ema = 90.0
	l.power_w = 210.0


static func set_landing(l: FishingLaneState, t: float = 5.0, gaff: float = 0.4) -> void:
	set_fight(l, 0, 8.0, 0.3, 0.0, 0.0)
	l.state = FishingConst.ST_LANDING
	l.state_t = t
	l.gaff = gaff


static func set_home(l: FishingLaneState) -> void:
	l.state = FishingConst.ST_HOME
	l.fish.sp = FishingConst.SP_NONE
	l.power_w = 120.0


## A view for `game`, in the tree under `parent`.
static func make_view(game: FishingGame, parent: Node) -> FishingView:
	var v := game.make_view() as FishingView
	parent.add_child(v)
	return v

extends RefCounted
## Fixtures for the HUD tests: TankFixtures' states for crews 1-4 (the Bastion's fourth rider on
## the arc generator), wrapped in a TankGame whose ctx names the riders, so the Controls build and
## draw from them headless.

const F := preload("res://tests/games/tank/tank_fakes.gd")


## The fixture state of `kind` ("advance", "gun_line", "boss") for `crew` 1..4.
static func state(crew: int, kind: String = "advance") -> TankState:
	match kind:
		"gun_line":
			return TankFixtures.gun_line(crew)
		"boss":
			return TankFixtures.boss(crew)
	return TankFixtures.state(crew)


## A TankGame (not configured: its ctx and state are set directly) for `s`, the local rider `local`.
static func game(s: TankState, local: int = 1) -> TankGame:
	var ctx := F.make_ctx(s.riders.size(), 0, "ashfall_road", Wl.SOLO, local)
	var g := TankGame.new()
	g.ctx = ctx
	g.content = s.content
	g.state = s
	return g


## A local telemetry sample.
static func tm(power: float, cadence: float, mode: String = Wl.SIM, target: int = 0) -> Telemetry:
	var t := Telemetry.new()
	t.power_w = power
	t.cadence_rpm = cadence
	t.mode = mode
	t.applied_target_w = target
	t.wbal_j = 15000.0
	t.gear = 14
	return t

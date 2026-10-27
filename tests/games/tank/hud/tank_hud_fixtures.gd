extends RefCounted
## Fixtures for the HUD tests: TankFixtures' states for crews 1-3, and the Bastion for crew 4 (the
## Citadel's state plus a fourth rider on the arc generator in a room at the front), wrapped in a
## TankGame whose ctx names the riders, so the Controls build and draw from them headless.

const F := preload("res://tests/games/tank/tank_fakes.gd")
const ARC := "arc"


## The fixture state of `kind` ("advance", "gun_line", "boss") for `crew` 1..4.
static func state(crew: int, kind: String = "advance") -> TankState:
	var base := mini(crew, 3)
	var s: TankState
	match kind:
		"gun_line":
			s = TankFixtures.gun_line(base)
		"boss":
			s = TankFixtures.boss(base)
		_:
			s = TankFixtures.state(base)
	if crew >= 4:
		add_arc_rider(s)
	return s


## The Bastion's fourth rider (peer 4, slot 3) on the arc generator, its room at the front.
static func add_arc_rider(s: TankState) -> TankRiderState:
	var r := TankRiderState.new()
	r.slot = 3
	r.peer = 4
	r.ftp = 260.0
	r.engine = ARC
	r.raw_w = roundf(0.7 * r.ftp)
	r.cadence_rpm = 88.0
	r.ftp_pct = 70.0
	r.in_band = true
	s.riders.append(r)
	s.crew = 4
	var st := TankStationState.make(ARC)
	st.slot = 3
	st.peer = 4
	st.in_band = true
	s.stations.append(st)
	return s.riders[-1]


## A TankGame (not configured: its ctx and state are set directly) for `s`, the local rider `local`.
static func game(s: TankState, local: int = 1) -> TankGame:
	var ctx := F.make_ctx(mini(s.riders.size(), 3), 0, "ashfall_road", Wl.SOLO, local)
	if s.riders.size() >= 4:
		var p := PlayerSlot.new()
		p.peer_id = 4
		p.name = "Rider 4"
		p.apply_look(3)
		p.ftp = 260.0
		ctx.players.append(p)
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

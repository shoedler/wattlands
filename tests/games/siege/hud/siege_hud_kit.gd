class_name SiegeHudKit
extends RefCounted
## Shared builders for the Siege HUD's tests: a game on the short shift standing in any phase, with
## the mock's numbers (FTP 200, phases as src/games/siege/art/hud_mock.mjs lays them out), and the
## local rider's telemetry.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const FIX := preload("res://tests/games/siege/fixtures/siege_fixtures.gd")


## A game on `content_id` with the fixture's riders, standing in phase `index`, `elapsed_s` in.
static func game(
	index: int = 4, elapsed_s: float = 105.0, content_id: String = "short"
) -> SiegeGame:
	var g := F.make_game(F.make_ctx(3, 1, content_id, Wl.SOLO, 1))
	var st := FIX.mid_wave(FIX.content(content_id))
	g.state = st
	g.content = st.content
	stand(g, index, elapsed_s)
	return g


## Puts the state in phase `index` of the shift (past the end: the cool-down), `elapsed_s` in.
static func stand(g: SiegeGame, index: int, elapsed_s: float) -> void:
	var st := g.state
	var phases: Array = st.content.shift["phases"]
	var metas := SiegePlanBuilder.phase_metas(st.content.shift, g.ctx.content_id)
	st.phase_index = index
	st.phase_elapsed_s = elapsed_s
	st.waves_total = SiegePlanBuilder.wave_count(st.content.shift)
	if index < phases.size():
		st.role = str(metas[index]["role"])
		st.wave_no = int(metas[index]["number"])
		st.phase_kind = str(phases[index]["kind"])
		st.phase_duration_s = float(phases[index]["duration_s"])
	else:
		st.role = SiegeIds.ROLE_COOLDOWN
		st.wave_no = 0
		st.phase_kind = Wl.COOLDOWN
		st.phase_duration_s = 180.0
	st.phase_remaining_s = maxf(st.phase_duration_s - elapsed_s, 0.0)
	if not st.in_wave():
		st.enemies.clear()


## A rider's telemetry at time `t`: ERG at `applied` unless `mode` says otherwise.
static func tm(
	t: float, w: float, rpm: float = 90.0, applied: int = 190, mode: String = Wl.ERG, hr: int = 0
) -> Telemetry:
	var x := Telemetry.new()
	x.t = t
	x.peer_id = 1
	x.power_w = w
	x.cadence_rpm = rpm
	x.mode = mode
	x.applied_target_w = applied if mode == Wl.ERG else 0
	x.gear = 12
	x.wbal_j = HudRiderNumbers.wprime_j()
	x.heart_rate_bpm = hr
	x.ftp_pct = w / 2.0
	return x


## A cockpit with no HR sensor known, fed `seconds` of the same telemetry.
static func cockpit(
	seconds: float = 4.0, w: float = 190.0, rpm: float = 90.0, applied: int = 190, hr: int = 0
) -> SiegeCockpitModel:
	var c := SiegeCockpitModel.new()
	c.wkg_override_kg = 0.0
	c.numbers.sensor_status_override = TrainerDevice.STATUS_DISCONNECTED
	ride(c, 0.0, seconds, w, rpm, applied, hr)
	return c


static func ride(
	c: SiegeCockpitModel,
	from_s: float,
	to_s: float,
	w: float,
	rpm: float = 90.0,
	applied: int = 190,
	hr: int = 0,
	mode: String = Wl.ERG
) -> void:
	var t := from_s
	while t <= to_s + 1e-6:
		c.feed(tm(t, w, rpm, applied, mode, hr))
		t += 0.05


## A Control set up on the game and in the tree's reach (the caller adds it).
static func ctl(c: SiegeHudCtl, g: SiegeGame, rect: Rect2i) -> SiegeHudCtl:
	c.setup(g, rect)
	c.size = Vector2(rect.size) * 2.0
	return c

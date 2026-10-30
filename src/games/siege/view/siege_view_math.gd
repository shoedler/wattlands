class_name SiegeViewMath
extends RefCounted
## The view's formulas (docs/games/siege.md 3 "View"), pure so the tests and the HUD can read
## them: the wheel's rim speed and turn from P_eff, its walkers by P_eff with hysteresis, which
## station a rider's path is lit to, and the gate, curtain, coat and rack stages.

## Rim speed 1.2 m/s at 250 W of P_eff, linear, at most 3 m/s.
const RIM_MPS_AT_250 := 1.2
const RIM_MAX_MPS := 3.0
## Walkers: 1 below 150 W, 2 from 150 W, 3 from 300 W; a count drops again only 20 W below
## its threshold.
const WALKER_W := [150.0, 300.0]
const WALKER_HYST_W := 20.0
## A walker's stride on the treadwheel's floor (m of rim per walk cycle).
const STRIDE_M := 1.4


static func rim_speed(p_eff_w: float) -> float:
	return clampf(RIM_MPS_AT_250 * maxf(p_eff_w, 0.0) / 250.0, 0.0, RIM_MAX_MPS)


## Degrees a wheel of radius `r_m` turns per second at `p_eff_w`.
static func wheel_deg_per_s(p_eff_w: float, r_m: float = 7.0) -> float:
	return rad_to_deg(rim_speed(p_eff_w) / maxf(r_m, 0.1))


## The walkers in a wheel at `p_eff_w`, given how many walked there before (`prev`, 0 for none).
static func walkers_for(p_eff_w: float, prev: int) -> int:
	var n := 1
	for i in WALKER_W.size():
		var thr: float = WALKER_W[i]
		# a count already above this threshold keeps it until 20 W below
		var keep := prev >= i + 2
		if p_eff_w >= thr or (keep and p_eff_w >= thr - WALKER_HYST_W):
			n = i + 2
	return n


## The station rider `r`'s powered path is lit to, or -1 (no rider, disconnected): the target,
## lit through the 2 s reconnect; the mine in breaks and the cool-down, where all output goes.
static func lit_station(state: SiegeState, r: SiegeRiderState) -> int:
	if state == null or r == null or not r.connected:
		return -1
	if state.shop_open() or state.in_cooldown() or state.done:
		return SiegeIds.STATION_MINE
	return clampi(r.target, 0, SiegeIds.STATION_COUNT - 1)


## The gate's damage stage: 0 whole (above 2/3), 1 (above 1/3), 2 (above 0), 3 breached (no HP
## left, or a Breach running).
static func gate_stage(gate_hp: float, gate_max: float, breach_s: float = 0.0) -> int:
	if breach_s > 0.0 or gate_hp <= 0.0:
		return 3
	var f := gate_hp / maxf(gate_max, 1.0)
	if f > 2.0 / 3.0:
		return 0
	if f > 1.0 / 3.0:
		return 1
	return 2


## A 0..3 stage of a 0..1 fill (0 empty, 3 above 2/3).
static func fill_stage(f: float) -> int:
	if f <= 0.01:
		return 0
	return clampi(ceili(f * 3.0), 1, 3)


static func curtain_stage(tar: SiegeTarState) -> int:
	return fill_stage(tar.curtain_hp / maxf(tar.curtain_max, 1.0)) if tar != null else 0


static func coat_stage(tar: SiegeTarState) -> int:
	return fill_stage(tar.coat) if tar != null else 0


## The arrow organ's loaded racks (bit k = rack k): every rack but the one fired last, which
## shows empty until its reload passes half (`arm` of the next rack, 0..1).
static func rack_mask(rack: int, arm: float) -> int:
	var last := posmod(rack - 1, 3)
	return 7 if arm >= 0.5 else 7 & ~(1 << last)


## Travel yaw (deg, atan2(dy, dx)) of an enemy at `prog` on `path`, turned round when it
## retreats.
static func enemy_yaw(path: SiegePath, prog: float, st: int) -> float:
	var d := path.dir_at(prog)
	var yaw := rad_to_deg(atan2(d.y, d.x))
	return yaw + 180.0 if st == SiegeIds.EN_RETREAT else yaw
